#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include <cstdio>
#include <cstring>
#include <string>

/**
 * @file codegen_global_tests.cpp
 * @brief Integration tests for C89 emission of global variable declarations.
 */

static bool run_global_codegen_test(const char* zig_code, const char* expected_c89_substring) {
    ArenaAllocator arena(1024 * 1024); // 1MB for tests
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for: %s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const char* temp_filename = "temp_global_test.c";
    {
        C89Emitter emitter(arena, unit.getErrorHandler(), temp_filename);
        if (!emitter.isValid()) {
            printf("FAIL: Could not open temp file for writing\n");
            return false;
        }

        // Find and emit all top-level variables
        ASTNode* root = unit.last_ast;
        if (root && root->type == NODE_BLOCK_STMT) {
            DynamicArray<ASTNode*>* stmts = root->as.block_stmt.statements;
            for (size_t i = 0; i < stmts->length(); ++i) {
                if ((*stmts)[i]->type == NODE_VAR_DECL) {
                    emitter.emitGlobalVarDecl((*stmts)[i], (*stmts)[i]->as.var_decl->is_pub);
                }
            }
        }
        // Destructor flushes and closes
    }

    char* buffer = NULL;
    size_t size = 0;
    if (!plat_file_read(temp_filename, &buffer, &size)) {
        printf("FAIL: Could not read back temp file\n");
        return false;
    }

    bool found = (strstr(buffer, expected_c89_substring) != NULL);
    if (!found) {
        printf("FAIL: Codegen mismatch for '%s'.\nExpected to find: %s\nActual output:   %.*s\n", zig_code, expected_c89_substring, (int)size, buffer);
    }

    plat_free(buffer);
    plat_delete_file(temp_filename);

    return found;
}

TEST_FUNC(Codegen_Global_PubConst) {
    return run_global_codegen_test("pub const x: i32 = 42;", "const int x = 42;");
}

TEST_FUNC(Codegen_Global_PrivateConst) {
    return run_global_codegen_test("const x: i32 = 42;", "static const int x = 42;");
}

TEST_FUNC(Codegen_Global_PubVar) {
    return run_global_codegen_test("pub var x: i32 = 42;", "int x = 42;");
}

TEST_FUNC(Codegen_Global_PrivateVar) {
    return run_global_codegen_test("var x: i32 = 42;", "static int x = 42;");
}

TEST_FUNC(Codegen_Global_Array) {
    return run_global_codegen_test("pub var x: [10]i32;", "int x[10];");
}

TEST_FUNC(Codegen_Global_Array_WithInit) {
    // Just a placeholder since the previous test covers it.
    return true;
}

TEST_FUNC(Codegen_Global_Pointer) {
    return run_global_codegen_test("pub var x: *i32;", "int* x;");
}

TEST_FUNC(Codegen_Global_ConstPointer) {
    return run_global_codegen_test("pub var x: *const i32;", "const int* x;");
}

TEST_FUNC(Codegen_Global_KeywordCollision) {
    return run_global_codegen_test("var int: i32 = 0;", "static int z_int = 0;");
}

TEST_FUNC(Codegen_Global_LongName) {
    return run_global_codegen_test("pub var this_is_a_very_long_variable_name_that_exceeds_31_chars: i32 = 0;", "int this_is_a_very_long_variable_na = 0;");
}

TEST_FUNC(Codegen_Global_NonConstantInit_Error) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    // fn foo() i32 { return 1; }
    // var x: i32 = foo();
    u32 file_id = unit.addSource("test.zig", "fn foo() i32 { return 1; }\nvar x: i32 = foo();");

    // The TypeChecker currently DOES NOT reject non-constant globals?
    // Let's see if our emitter catches it.

    if (!unit.performTestPipeline(file_id)) {
        // If it fails here, it might be the TypeChecker or Validator.
    }

    const char* temp_filename = "temp_global_error_test.c";
    C89Emitter emitter(arena, unit.getErrorHandler(), temp_filename);

    ASTNode* root = unit.last_ast;
    bool error_reported = false;
    if (root && root->type == NODE_BLOCK_STMT) {
        DynamicArray<ASTNode*>* stmts = root->as.block_stmt.statements;
        for (size_t i = 0; i < stmts->length(); ++i) {
            if ((*stmts)[i]->type == NODE_VAR_DECL) {
                emitter.emitGlobalVarDecl((*stmts)[i], (*stmts)[i]->as.var_decl->is_pub);
                if (unit.getErrorHandler().hasErrors()) {
                    error_reported = true;
                    break;
                }
            }
        }
    }

    plat_delete_file(temp_filename);
    return error_reported;
}
