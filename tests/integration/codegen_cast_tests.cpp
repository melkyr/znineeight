#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include "c89_validator.hpp"
#include <cstdio>
#include <cstring>
#include <string>

/**
 * @file codegen_cast_tests.cpp
 * @brief Integration tests for @intCast and @floatCast emission in C89Emitter.
 */

static bool run_cast_codegen_test(const char* zig_code, const char* expected_c89_substring) {
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
    const char* temp_filename = "temp_cast_test.c";
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

    // For validation, we need a dummy runtime header that declares the helpers
    // Since we don't have it easily accessible here, we might just skip C89 validation
    // or provide a minimal mock one.
    // The C89Validator adds a compatibility header which might be enough if we don't use too many helpers.
    // Actually, createGCCValidator might fail if it can't find zig_runtime.h.

    plat_free(buffer);
    plat_delete_file(temp_filename);

    return found;
}

TEST_FUNC(Codegen_IntCast_SafeWidening) {
    // Same signedness, larger or equal size
    return run_cast_codegen_test(
        "fn my_test(x: i32) i64 { return @intCast(i64, x); }",
        "return (__int64)x;"
    );
}

TEST_FUNC(Codegen_IntCast_Narrowing) {
    // Same signedness, smaller size
    return run_cast_codegen_test(
        "fn my_test(x: i64) i32 { return @intCast(i32, x); }",
        "return __bootstrap_i32_from_i64(x);"
    );
}

TEST_FUNC(Codegen_IntCast_SignednessMismatch) {
    // i32 to u32
    return run_cast_codegen_test(
        "fn my_test(x: i32) u32 { return @intCast(u32, x); }",
        "return __bootstrap_u32_from_i32(x);"
    );
}

TEST_FUNC(Codegen_FloatCast_SafeWidening) {
    return run_cast_codegen_test(
        "fn my_test(x: f32) f64 { return @floatCast(f64, x); }",
        "return (double)x;"
    );
}

TEST_FUNC(Codegen_FloatCast_Narrowing) {
    return run_cast_codegen_test(
        "fn my_test(x: f64) f32 { return @floatCast(f32, x); }",
        "return __bootstrap_f32_from_f64(x);"
    );
}
