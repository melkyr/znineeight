#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include <cstdio>

/**
 * @file codegen_integer_tests.cpp
 * @brief Integration tests for integer literal code generation in C89Emitter.
 */

static bool run_codegen_int_test(const char* zig_code, const char* expected_c89) {
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
        printf("FAIL: Could not extract expression\n");
        return false;
    }

    // If it's a return statement, get the expression
    if (expr->type == NODE_RETURN_STMT) {
        expr = expr->as.return_stmt.expression;
    }

    if (!expr || expr->type != NODE_INTEGER_LITERAL) {
        printf("FAIL: Not an integer literal, type=%d\n", expr ? expr->type : -1);
        return false;
    }

    // Use C89Emitter to emit to a temp file
    const char* temp_file = "temp_codegen_int.c";
    C89Emitter emitter(arena, unit.getErrorHandler(), temp_file);
    if (!emitter.isValid()) {
        printf("FAIL: Could not open temp file\n");
        return false;
    }

    emitter.emitIntegerLiteral(&expr->as.integer_literal);
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

    // Clean up
    // plat_delete_file(temp_file); // If we had it. We don't have plat_delete_file in platform.hpp yet.

    return match;
}

TEST_FUNC(Codegen_Int_i32) {
    return run_codegen_int_test("fn foo() i32 { return 42; }", "42");
}

TEST_FUNC(Codegen_Int_u32) {
    return run_codegen_int_test("fn foo() u32 { return 42u; }", "42U");
}

TEST_FUNC(Codegen_Int_i64) {
    return run_codegen_int_test("fn foo() i64 { return 42l; }", "42i64");
}

TEST_FUNC(Codegen_Int_u64) {
    return run_codegen_int_test("fn foo() u64 { return 42ul; }", "42ui64");
}

TEST_FUNC(Codegen_Int_usize) {
    // Use @intCast to force usize type, which constant-folds back to a literal with resolved_type=usize
    return run_codegen_int_test("fn foo() usize { return @intCast(usize, 42); }", "42");
}

TEST_FUNC(Codegen_Int_u8) {
    return run_codegen_int_test("fn foo() u8 { return @intCast(u8, 42); }", "42");
}

TEST_FUNC(Codegen_Int_HexToDecimal) {
    return run_codegen_int_test("fn foo() i32 { return 0x1F; }", "31");
}

TEST_FUNC(Codegen_Int_LargeU64) {
    // 18446744073709551615 is too large for signed i64, so it should be inferred as u64
    // But lexer requires 'ul' or similar if it's explicitly unsigned?
    // Let's check lexer.cpp: if value > 4294967295 but no suffix, it still tries to parse as u64?
    // Actually, parseInteger always uses u64.
    // visitIntegerLiteral: if !is_unsigned, it checks if it fits in i32, else i64.
    // If it's larger than i64 max, it will be negative if cast to i64.
    return run_codegen_int_test("fn foo() u64 { return 18446744073709551615ul; }", "18446744073709551615ui64");
}
