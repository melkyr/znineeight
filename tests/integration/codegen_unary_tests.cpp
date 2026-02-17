#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include "c89_validator.hpp"
#include <cstdio>
#include <cstring>
#include <string>

/**
 * @file codegen_unary_tests.cpp
 * @brief Integration tests for unary operator emission in C89Emitter.
 */

static bool run_unary_codegen_test(const char* zig_code, const char* expected_c89_substring) {
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
    const char* temp_filename = "temp_unary_test.c";
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

TEST_FUNC(Codegen_Unary_Negation) {
    return run_unary_codegen_test(
        "fn my_test(a: i32) i32 { return -a; }",
        "return -a;"
    );
}

TEST_FUNC(Codegen_Unary_Plus) {
    return run_unary_codegen_test(
        "fn my_test(a: i32) i32 { return +a; }",
        "return +a;"
    );
}

TEST_FUNC(Codegen_Unary_LogicalNot) {
    return run_unary_codegen_test(
        "fn my_test(a: bool) bool { return !a; }",
        "return !a;"
    );
}

TEST_FUNC(Codegen_Unary_BitwiseNot) {
    return run_unary_codegen_test(
        "fn my_test(a: u32) u32 { return ~a; }",
        "return ~a;"
    );
}

TEST_FUNC(Codegen_Unary_AddressOf) {
    return run_unary_codegen_test(
        "fn my_test() void { var x: i32 = 42; var p: *i32 = &x; }",
        "p = &x;"
    );
}

TEST_FUNC(Codegen_Unary_Dereference) {
    return run_unary_codegen_test(
        "fn my_test(p: *i32) i32 { return p.*; }",
        "return *p;"
    );
}

TEST_FUNC(Codegen_Unary_Nested) {
    return run_unary_codegen_test(
        "fn my_test(p: *i32) i32 { return -p.*; }",
        "return -*p;"
    );
}

TEST_FUNC(Codegen_Unary_Mixed) {
    return run_unary_codegen_test(
        "fn my_test(a: i32, b: bool) i32 { if (!b) { return -a; } return a; }",
        "if (!b) {\n        return -a;\n    }"
    );
}
