#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include "c89_validator.hpp"
#include <cstdio>
#include <cstring>
#include <string>

/**
 * @file codegen_binary_tests.cpp
 * @brief Integration tests for binary operator emission in C89Emitter.
 */

static bool run_binary_codegen_test(const char* zig_code, const char* expected_c89_substring) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for: %s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    std::string generated_c;
    const char* temp_filename = "temp_binary_test.c";
    {
        C89Emitter emitter(unit, temp_filename);
        if (!emitter.isValid()) {
            printf("FAIL: Could not open temp file for writing\n");
            return false;
        }

        emitter.emitPrologue();

        ASTNode* root = unit.last_ast;
        if (root && root->type == NODE_BLOCK_STMT) {
            DynamicArray<ASTNode*>* stmts = root->as.block_stmt.statements;
            for (size_t i = 0; i < stmts->length(); ++i) {
                if ((*stmts)[i]->type == NODE_FN_DECL) {
                    emitter.emitFnDecl((*stmts)[i]->as.fn_decl);
                }
            }
        }
    }

    char* buffer = NULL;
    size_t size = 0;
    if (!plat_file_read(temp_filename, &buffer, &size)) {
        printf("FAIL: Could not read back temp file\n");
        return false;
    }
    generated_c = std::string(buffer, size);

    bool found = (generated_c.find(expected_c89_substring) != std::string::npos);
    if (!found) {
        printf("FAIL: Codegen mismatch for '%s'.\nExpected to find: %s\nActual output:   %s\n", zig_code, expected_c89_substring, generated_c.c_str());
    }

    C89Validator* validator = createGCCValidator();
    ValidationResult res = validator->validate(generated_c);
    if (!res.isValid) {
        printf("FAIL: Generated C code is not valid C89 for: %s\n", zig_code);
        for (size_t i = 0; i < res.errors.size(); ++i) {
            printf("  Error: %s\n", res.errors[i].c_str());
        }
        printf("--- Generated Code ---\n%s\n----------------------\n", generated_c.c_str());
        found = false;
    }
    delete validator;

    plat_free(buffer);
    plat_delete_file(temp_filename);

    return found;
}

TEST_FUNC(Codegen_Binary_Arithmetic) {
    return run_binary_codegen_test(
        "fn my_test(a: i32, b: i32) i32 { return a + b * 2 / (10 - a) % 3; }",
        "return a + b * 2 / (10 - a) % 3;"
    );
}

TEST_FUNC(Codegen_Binary_Comparison) {
    return run_binary_codegen_test(
        "fn my_test(a: i32, b: i32) bool { return a == b and a != 0 or b < 10 and a >= b; }",
        "return a == b && a != 0 || b < 10 && a >= b;"
    );
}

TEST_FUNC(Codegen_Binary_Bitwise) {
    return run_binary_codegen_test(
        "fn my_test(a: u32, b: u32) u32 { return (a & b) | (a ^ b) ^ (a << 1) >> 2; }",
        "return (a & b) | (a ^ b) ^ (a << 1) >> 2;"
    );
}

TEST_FUNC(Codegen_Binary_CompoundAssignment) {
    return run_binary_codegen_test(
        "fn my_test(a: *i32, b: i32) void { a.* += b; a.* -= 1; a.* *= 2; a.* /= 2; a.* %= 3; }",
        "*a += b;\n    *a -= 1;\n    *a *= 2;\n    *a /= 2;\n    *a %= 3;"
    );
}

TEST_FUNC(Codegen_Binary_BitwiseCompoundAssignment) {
    return run_binary_codegen_test(
        "fn my_test(a: *u32, b: u32) void { a.* &= b; a.* |= 1; a.* ^= 0xF; a.* <<= 1; a.* >>= 2; }",
        "*a &= b;\n    *a |= 1;\n    *a ^= 15;\n    *a <<= 1;\n    *a >>= 2;"
    );
}

TEST_FUNC(Codegen_Binary_Wrapping) {
    return run_binary_codegen_test(
        "fn my_test(a: u32, b: u32) u32 { return a +% b -% 1 *% a; }",
        "return a + b - 1 * a;"
    );
}

TEST_FUNC(Codegen_Binary_Logical_Keywords) {
    // Zig uses 'and' and 'or' which map to '&&' and '||'
    return run_binary_codegen_test(
        "fn my_test(a: bool, b: bool) bool { return a and b or !a; }",
        "return a && b || !a;"
    );
}
