#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include "c89_validator.hpp"
#include <cstdio>
#include <cstring>
#include <string>

/**
 * @file codegen_array_indexing_tests.cpp
 * @brief Integration tests for array indexing emission in C89Emitter.
 */

static bool run_array_codegen_test(const char* zig_code, const char* expected_c89_substring) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    std::string generated_c;
    const char* temp_filename = "temp_array_test.c";
    {
        C89Emitter emitter(arena, unit.getErrorHandler(), temp_filename);
        if (!emitter.isValid()) {
            printf("FAIL: Could not open temp file for writing\n");
            return false;
        }

        emitter.emitPrologue();

        ASTNode* root = unit.last_ast;
        if (root && root->type == NODE_BLOCK_STMT) {
            DynamicArray<ASTNode*>* stmts = root->as.block_stmt.statements;
            // 1. First pass: Emit type definitions
            for (size_t i = 0; i < stmts->length(); ++i) {
                emitter.emitTypeDefinition((*stmts)[i]);
            }
            // 2. Second pass: Emit global declarations and functions
            for (size_t i = 0; i < stmts->length(); ++i) {
                ASTNode* stmt = (*stmts)[i];
                if (stmt->type == NODE_VAR_DECL) {
                    emitter.emitGlobalVarDecl(stmt, true);
                } else if (stmt->type == NODE_FN_DECL) {
                    emitter.emitFnDecl(stmt->as.fn_decl);
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
        printf("FAIL: Codegen mismatch for:\n%s\nExpected to find: %s\nActual output:   %s\n", zig_code, expected_c89_substring, generated_c.c_str());
    }

    C89Validator* validator = createGCCValidator();
    ValidationResult res = validator->validate(generated_c);
    if (!res.isValid) {
        printf("FAIL: Generated C code is not valid C89 for:\n%s\n", zig_code);
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

static bool run_array_error_test(const char* zig_code, const char* expected_error) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected pipeline failure for:\n%s\nBut it succeeded.\n", zig_code);
        return false;
    }

    return unit.hasErrorMatching(expected_error);
}

TEST_FUNC(Codegen_Array_Simple) {
    const char* source =
        "fn foo(arr: [5]i32) i32 {\n"
        "    return arr[0];\n"
        "}";
    return run_array_codegen_test(source, "return arr[0];");
}

TEST_FUNC(Codegen_Array_MultiDim) {
    const char* source =
        "fn foo(matrix: [3][4]i32) i32 {\n"
        "    return matrix[1][2];\n"
        "}";
    return run_array_codegen_test(source, "return matrix[1][2];");
}

TEST_FUNC(Codegen_Array_Pointer) {
    const char* source =
        "fn foo(ptr: *[5]i32) i32 {\n"
        "    return ptr[1];\n"
        "}";
    // Zig ptr[1] for *[5]i32 -> C (*ptr)[1]
    return run_array_codegen_test(source, "return (*ptr)[1];");
}

TEST_FUNC(Codegen_Array_Const) {
    const char* source =
        "const global_arr: [3]i32 = .{ ._0 = 1, ._1 = 2, ._2 = 3 };\n"
        "fn foo() i32 {\n"
        "    return global_arr[2];\n"
        "}";
    return run_array_codegen_test(source, "return global_arr[2];");
}

TEST_FUNC(Codegen_Array_ExpressionIndex) {
    const char* source =
        "fn foo(arr: [10]i32, i: i32) i32 {\n"
        "    return arr[i + 1];\n"
        "}";
    return run_array_codegen_test(source, "return arr[i + 1];");
}

TEST_FUNC(Codegen_Array_NestedMember) {
    const char* source =
        "const S = struct { data: [5]i32 };\n"
        "fn foo(s: S) i32 {\n"
        "    return s.data[0];\n"
        "}";
    return run_array_codegen_test(source, "return s.data[0];");
}

TEST_FUNC(Codegen_Array_OOB_Error) {
    const char* source =
        "fn foo() i32 {\n"
        "    var arr: [3]i32 = undefined;\n"
        "    return arr[3];\n"
        "}";
    return run_array_error_test(source, "out of bounds");
}

TEST_FUNC(Codegen_Array_NonIntegerIndex_Error) {
    const char* source =
        "fn foo(arr: [3]i32) i32 {\n"
        "    return arr[1.5];\n"
        "}";
    return run_array_error_test(source, "must be an integer");
}

TEST_FUNC(Codegen_Array_NonArrayBase_Error) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    return x[0];\n"
        "}";
    return run_array_error_test(source, "Cannot index into a non-array type");
}
