#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file arithmetic_tests.cpp
 * @brief Integration tests for arithmetic, comparison, and logical expressions.
 */

static bool run_arithmetic_test(const char* expr_code, TypeKind expected_kind, const char* expected_c89) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    // Wrap expression in a function to use TestCompilationUnit's extraction logic
    // We use 'arithmetic_func' because 'test' is a keyword in Zig.
    std::string source = "fn arithmetic_func() void { ";
    source += expr_code;
    source += "; }";

    u32 file_id = unit.addSource("test.zig", source.c_str());
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for: %s\n", expr_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateExpressionType(expected_kind)) return false;
    if (!unit.validateExpressionEmission(expected_c89)) return false;

    return true;
}

// --- Integer Arithmetic ---

TEST_FUNC(ArithmeticIntegration_IntAdd) {
    return run_arithmetic_test("1 + 2", TYPE_I32, "1 + 2");
}

TEST_FUNC(ArithmeticIntegration_IntSub) {
    return run_arithmetic_test("10 - 5", TYPE_I32, "10 - 5");
}

TEST_FUNC(ArithmeticIntegration_IntMul) {
    return run_arithmetic_test("3 * 4", TYPE_I32, "3 * 4");
}

TEST_FUNC(ArithmeticIntegration_IntDiv) {
    return run_arithmetic_test("20 / 4", TYPE_I32, "20 / 4");
}

TEST_FUNC(ArithmeticIntegration_IntMod) {
    return run_arithmetic_test("7 % 3", TYPE_I32, "7 % 3");
}

// --- Float Arithmetic ---

TEST_FUNC(ArithmeticIntegration_FloatAdd) {
    return run_arithmetic_test("1.5 + 2.5", TYPE_F64, "1.5 + 2.5");
}

TEST_FUNC(ArithmeticIntegration_FloatSub) {
    return run_arithmetic_test("5.0 - 1.25", TYPE_F64, "5.0 - 1.25");
}

TEST_FUNC(ArithmeticIntegration_FloatMul) {
    return run_arithmetic_test("2.0 * 3.14", TYPE_F64, "2.0 * 3.14");
}

TEST_FUNC(ArithmeticIntegration_FloatDiv) {
    return run_arithmetic_test("10.0 / 4.0", TYPE_F64, "10.0 / 4.0");
}

// --- Comparisons ---

TEST_FUNC(ArithmeticIntegration_IntEq) {
    return run_arithmetic_test("1 == 1", TYPE_BOOL, "1 == 1");
}

TEST_FUNC(ArithmeticIntegration_IntNe) {
    return run_arithmetic_test("1 != 2", TYPE_BOOL, "1 != 2");
}

TEST_FUNC(ArithmeticIntegration_IntLt) {
    return run_arithmetic_test("5 < 10", TYPE_BOOL, "5 < 10");
}

TEST_FUNC(ArithmeticIntegration_IntLe) {
    return run_arithmetic_test("5 <= 5", TYPE_BOOL, "5 <= 5");
}

TEST_FUNC(ArithmeticIntegration_IntGt) {
    return run_arithmetic_test("10 > 5", TYPE_BOOL, "10 > 5");
}

TEST_FUNC(ArithmeticIntegration_IntGe) {
    return run_arithmetic_test("10 >= 10", TYPE_BOOL, "10 >= 10");
}

// --- Logical Operators ---

TEST_FUNC(ArithmeticIntegration_LogicalAnd) {
    return run_arithmetic_test("true and false", TYPE_BOOL, "1 && 0");
}

TEST_FUNC(ArithmeticIntegration_LogicalOr) {
    return run_arithmetic_test("false or true", TYPE_BOOL, "0 || 1");
}

TEST_FUNC(ArithmeticIntegration_LogicalNot) {
    return run_arithmetic_test("!true", TYPE_BOOL, "!1");
}

// --- Unary Minus ---

TEST_FUNC(ArithmeticIntegration_UnaryMinus) {
    return run_arithmetic_test("-42", TYPE_I32, "-42");
}

// --- Parentheses & Precedence ---

TEST_FUNC(ArithmeticIntegration_Parentheses) {
    return run_arithmetic_test("(1 + 2) * 3", TYPE_I32, "(1 + 2) * 3");
}

TEST_FUNC(ArithmeticIntegration_NestedParentheses) {
    return run_arithmetic_test("((1 + 2) * (3 + 4))", TYPE_I32, "((1 + 2) * (3 + 4))");
}

// --- Literal Promotion ---

TEST_FUNC(ArithmeticIntegration_Int8LiteralPromotion) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "fn arithmetic_func() void {\n"
        "    var a: i8 = 10;\n"
        "    a + 5;\n" // 5 should be promoted to i8
        "}";

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateExpressionType(TYPE_I8)) return false;
    if (!unit.validateExpressionEmission("a + 5")) return false;

    return true;
}

// --- Negative Tests ---

TEST_FUNC(ArithmeticIntegration_TypeMismatchError) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    // i32 and f64 are not compatible without explicit cast in bootstrap
    const char* source = "fn arithmetic_func() void { var x: i32 = 1; var y: f64 = 2.0; x + y; }";

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected type mismatch error but pipeline succeeded.\n");
        return false;
    }

    return true;
}

TEST_FUNC(ArithmeticIntegration_FloatModuloError) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source = "fn arithmetic_func() void { 3.14 % 2.0; }";

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected float modulo error but pipeline succeeded.\n");
        return false;
    }

    return true;
}

TEST_FUNC(ArithmeticIntegration_BoolArithmeticError) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source = "fn arithmetic_func() void { true + false; }";

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected boolean arithmetic error but pipeline succeeded.\n");
        return false;
    }

    return true;
}
