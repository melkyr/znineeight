#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include "c89_validator.hpp"
#include <cstdio>
#include <cstring>
#include <string>

/**
 * @file codegen_function_tests.cpp
 * @brief Integration tests for function definition emission in C89Emitter.
 */

static bool run_function_codegen_test(const char* zig_code, const char* expected_c89_substring) {
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
    const char* temp_filename = "temp_function_test.c";
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

TEST_FUNC(Codegen_Fn_Simple) {
    return run_function_codegen_test("fn foo() void {}", "static void foo(void) {");
}

TEST_FUNC(Codegen_Fn_Public) {
    return run_function_codegen_test("pub fn foo() void {}", "void foo(void) {");
}

TEST_FUNC(Codegen_Fn_Params) {
    return run_function_codegen_test(
        "fn add(a: i32, b: i32) i32 { return a + b; }",
        "static int add(int a, int b) {\n    return a + b;\n}"
    );
}

TEST_FUNC(Codegen_Fn_Pointers) {
    return run_function_codegen_test(
        "fn process(p: *i32) *i32 { return p; }",
        "static int* process(int* p) {\n    return p;\n}"
    );
}

TEST_FUNC(Codegen_Fn_Call) {
    return run_function_codegen_test(
        "fn bar() void {} fn foo() void { bar(); }",
        "static void foo(void) {\n    bar();\n}"
    );
}

TEST_FUNC(Codegen_Fn_KeywordParam) {
    return run_function_codegen_test(
        "fn my_test(int: i32) void {}",
        "static void my_test(int z_int) {"
    );
}

TEST_FUNC(Codegen_Fn_MangledCall) {
    // Should use mangled name for keywords
    return run_function_codegen_test(
        "fn register() void {} fn my_test() void { register(); }",
        "static void z_register(void) {\n}\n\nstatic void my_test(void) {\n    z_register();\n}"
    );
}
