#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include "c89_validator.hpp"
#include <cstdio>
#include <cstring>
#include <string>

/**
 * @file codegen_local_tests.cpp
 * @brief Integration tests for local variable emission in C89Emitter.
 */

static bool run_local_codegen_test(const char* zig_code, const char* expected_c89_substring) {
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
    const char* temp_filename = "temp_local_test.c";
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

TEST_FUNC(Codegen_Local_Simple) {
    return run_local_codegen_test("fn my_test() void { var x: i32 = 42; }", "int x = 42;");
}

TEST_FUNC(Codegen_Local_AfterStatement) {
    return run_local_codegen_test("fn foo() void {} fn my_test() void { foo(); var x: i32 = 42; }", "void my_test(void) {\n    int x = 42;\n    foo();\n}");
}

TEST_FUNC(Codegen_Local_Const) {
    // Should keep const if constant-initialized
    return run_local_codegen_test("fn my_test() void { const x: i32 = 42; }", "const int x = 42;");
}

TEST_FUNC(Codegen_Local_Undefined) {
    return run_local_codegen_test("fn my_test() void { var x: i32 = undefined; }", "int x;\n}");
}

TEST_FUNC(Codegen_Local_Shadowing) {
    return run_local_codegen_test(
        "fn my_test() void { var x: i32 = 1; { var x: i32 = 2; } }",
        "int x = 1;\n    {\n        int x_1 = 2;\n    }"
    );
}

TEST_FUNC(Codegen_Local_IfStatement) {
    return run_local_codegen_test(
        "fn my_test(c: bool) void { if (c) { var x: i32 = 1; } else { var x: i32 = 2; } }",
        "if (c) {\n        int x = 1;\n    } else {\n        int x_1 = 2;\n    }"
    );
}

TEST_FUNC(Codegen_Local_WhileLoop) {
    return run_local_codegen_test(
        "fn my_test() void { var i: i32 = 0; while (i < 10) { var x: i32 = i; i = i + 1; } }",
        "while (i < 10) {\n        int x;\n        x = i;\n        i = i + 1;\n    }"
    );
}

TEST_FUNC(Codegen_Local_Return) {
    return run_local_codegen_test(
        "fn my_test(a: i32) i32 { return a + 1; }",
        "int my_test(int a) {\n    return a + 1;\n}"
    );
}

TEST_FUNC(Codegen_Local_MultipleBlocks) {
    return run_local_codegen_test(
        "fn my_test() void { { var x: i32 = 1; } { var x: i32 = 2; } }",
        "{\n        int x = 1;\n    }\n    {\n        int x_1 = 2;\n    }"
    );
}
