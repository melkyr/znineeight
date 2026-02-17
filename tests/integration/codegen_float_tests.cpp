#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include <cstdio>

/**
 * @file codegen_float_tests.cpp
 * @brief Integration tests for float literal code generation in C89Emitter.
 */

static bool run_codegen_float_test(const char* zig_code, const char* expected_c89) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline failed for '%s'\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTNode* expr = unit.extractTestExpression();
    if (!expr) {
        printf("FAIL: Could not extract expression from '%s'\n", zig_code);
        return false;
    }

    // If it's a return statement, get the expression
    if (expr->type == NODE_RETURN_STMT) {
        expr = expr->as.return_stmt.expression;
    }

    if (!expr || expr->type != NODE_FLOAT_LITERAL) {
        printf("FAIL: Not a float literal, type=%d for '%s'\n", expr ? expr->type : -1, zig_code);
        return false;
    }

    // Use C89Emitter to emit to a temp file
    const char* temp_file = "temp_codegen_float.c";
    C89Emitter emitter(unit, temp_file);
    if (!emitter.isValid()) {
        printf("FAIL: Could not open temp file\n");
        return false;
    }

    emitter.emitFloatLiteral(&expr->as.float_literal);
    emitter.close();

    // Read back and verify
    PlatFile f = plat_open_file(temp_file, false);
    if (f == PLAT_INVALID_FILE) {
        printf("FAIL: Could not read back temp file\n");
        return false;
    }

    char buf[1024];
    size_t bytes = plat_read_file_raw(f, buf, sizeof(buf) - 1);
    buf[bytes] = '\0';
    plat_close_file(f);

    bool match = (plat_strcmp(buf, expected_c89) == 0);
    if (!match) {
        printf("FAIL: zig='%s'\n  Expected: '%s'\n  Actual:   '%s'\n", zig_code, expected_c89, buf);
    }
    return match;
}

TEST_FUNC(Codegen_Float_f64) {
    return run_codegen_float_test("fn foo() f64 { return 3.14159; }", "3.14159");
}

TEST_FUNC(Codegen_Float_f32) {
    return run_codegen_float_test("fn foo() f32 { return @floatCast(f32, 3.14); }", "3.14f");
}

TEST_FUNC(Codegen_Float_WholeNumber) {
    return run_codegen_float_test("fn foo() f64 { return 2.0; }", "2.0");
}

TEST_FUNC(Codegen_Float_Scientific) {
    // 1e20 might be emitted as 1e+20 or 1e20 depending on sprintf
    // Let's check what it actually emits and adapt if needed, but 1e+20 is common.
    // Actually, %.15g for 1e20 might produce 1e+20.
    return run_codegen_float_test("fn foo() f64 { return 1e20; }", "1e+20");
}

TEST_FUNC(Codegen_Float_HexConversion) {
    // 0x1.Ap2 = 1.625 * 4 = 6.5
    return run_codegen_float_test("fn foo() f64 { return 0x1.Ap2; }", "6.5");
}
