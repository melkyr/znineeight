#include "test_framework.hpp"
#include "test_utils.hpp"
#include "error_handler.hpp"
#include "type_checker.hpp"

static bool check_binary_op(const char* op, const char* lhs_type, const char* rhs_type, bool should_pass, ErrorCode expected_code = (ErrorCode)0) {
    char source_buffer[256];
    snprintf(source_buffer, sizeof(source_buffer),
             "fn test_fn() { var a: %s = undefined; var b: %s = undefined; var c = a %s b; }",
             lhs_type, rhs_type, op);

    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source_buffer);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser.parse();

    TypeChecker type_checker(comp_unit);
    type_checker.check(ast);

    if (should_pass) {
        if (comp_unit.getErrorHandler().hasErrors()) {
            fprintf(stderr, "TEST FAIL: Expected successful type check for '%s %s %s', but got errors.\n", lhs_type, op, rhs_type);
            return false;
        }
    } else {
        if (!comp_unit.getErrorHandler().hasErrors()) {
            fprintf(stderr, "TEST FAIL: Expected type check to fail for '%s %s %s', but it passed.\n", lhs_type, op, rhs_type);
            return false;
        }
        const DynamicArray<ErrorReport>& errors = comp_unit.getErrorHandler().getErrors();
        if (errors.length() != 1) {
            fprintf(stderr, "TEST FAIL: Expected 1 error for '%s %s %s', but got %zu.\n", lhs_type, op, rhs_type, errors.length());
            return false;
        }
        if (errors[0].code != expected_code) {
            fprintf(stderr, "TEST FAIL: Mismatched error code for '%s %s %s'. Expected %d, got %d.\n", lhs_type, op, rhs_type, expected_code, errors[0].code);
            return false;
        }
    }
    return true;
}

TEST_FUNC(TypeChecker_BinaryOps_Arithmetic) {
    // --- Valid: Same Numeric Types ---
    ASSERT_TRUE(check_binary_op("+", "i32", "i32", true));
    ASSERT_TRUE(check_binary_op("-", "u16", "u16", true));
    ASSERT_TRUE(check_binary_op("*", "f64", "f64", true));
    ASSERT_TRUE(check_binary_op("/", "i8", "i8", true));
    ASSERT_TRUE(check_binary_op("%", "u32", "u32", true));

    // --- Invalid: Different Numeric Types ---
    ASSERT_TRUE(check_binary_op("+", "i16", "i32", false, ERR_TYPE_MISMATCH));
    ASSERT_TRUE(check_binary_op("-", "u8", "i8", false, ERR_TYPE_MISMATCH));
    ASSERT_TRUE(check_binary_op("*", "f32", "f64", false, ERR_TYPE_MISMATCH));
    ASSERT_TRUE(check_binary_op("/", "i32", "f32", false, ERR_TYPE_MISMATCH));

    // --- Invalid: Non-numeric types ---
    ASSERT_TRUE(check_binary_op("+", "bool", "bool", false, ERR_TYPE_MISMATCH));
    ASSERT_TRUE(check_binary_op("*", "*i32", "*i32", false, ERR_TYPE_MISMATCH));

    return true;
}

TEST_FUNC(TypeChecker_BinaryOps_PointerArithmetic) {
    // --- Valid Pointer Arithmetic ---
    ASSERT_TRUE(check_binary_op("+", "*i32", "i32", true));
    ASSERT_TRUE(check_binary_op("+", "u16", "*u8", true));
    ASSERT_TRUE(check_binary_op("-", "*f64", "i16", true));
    ASSERT_TRUE(check_binary_op("-", "*i32", "*i32", true));

    // --- Invalid Pointer Arithmetic ---
    ASSERT_TRUE(check_binary_op("+", "*i32", "*i32", false, ERR_TYPE_MISMATCH)); // pointer + pointer
    ASSERT_TRUE(check_binary_op("-", "i32", "*i32", false, ERR_TYPE_MISMATCH)); // integer - pointer
    ASSERT_TRUE(check_binary_op("*", "*i32", "i32", false, ERR_TYPE_MISMATCH)); // pointer * integer
    ASSERT_TRUE(check_binary_op("-", "*i32", "*u32", false, ERR_TYPE_MISMATCH)); // pointer - pointer (incompatible)

    return true;
}

TEST_FUNC(TypeChecker_BinaryOps_Bitwise) {
    // --- Valid: Same Integer Types ---
    ASSERT_TRUE(check_binary_op("&", "u8", "u8", true));
    ASSERT_TRUE(check_binary_op("|", "i32", "i32", true));
    ASSERT_TRUE(check_binary_op("^", "u64", "u64", true));
    ASSERT_TRUE(check_binary_op("<<", "i16", "i16", true));
    ASSERT_TRUE(check_binary_op(">>", "u32", "u32", true));

    // --- Invalid: Different Integer Types ---
    ASSERT_TRUE(check_binary_op("&", "u8", "i8", false, ERR_TYPE_MISMATCH));
    ASSERT_TRUE(check_binary_op("|", "i16", "i32", false, ERR_TYPE_MISMATCH));

    // --- Invalid: Non-integer types ---
    ASSERT_TRUE(check_binary_op("&", "f32", "f32", false, ERR_TYPE_MISMATCH));
    ASSERT_TRUE(check_binary_op("|", "bool", "bool", false, ERR_TYPE_MISMATCH));
    ASSERT_TRUE(check_binary_op("^", "*i32", "*i32", false, ERR_TYPE_MISMATCH));

    return true;
}

TEST_FUNC(TypeChecker_BinaryOps_Comparison) {
    // --- Valid: Same Numeric Types ---
    ASSERT_TRUE(check_binary_op("==", "i32", "i32", true));
    ASSERT_TRUE(check_binary_op("!=", "f32", "f32", true));
    ASSERT_TRUE(check_binary_op("<", "u16", "u16", true));
    ASSERT_TRUE(check_binary_op("<=", "i8", "i8", true));
    ASSERT_TRUE(check_binary_op(">", "f64", "f64", true));
    ASSERT_TRUE(check_binary_op(">=", "u32", "u32", true));

    // --- Invalid: Different Numeric Types ---
    ASSERT_TRUE(check_binary_op("==", "i16", "u16", false, ERR_TYPE_MISMATCH));
    ASSERT_TRUE(check_binary_op(">", "f32", "i32", false, ERR_TYPE_MISMATCH));

    // --- Valid: Pointer Equality ---
    ASSERT_TRUE(check_binary_op("==", "*i32", "*i32", true));
    ASSERT_TRUE(check_binary_op("!=", "*f64", "*f64", true));
    ASSERT_TRUE(check_binary_op("==", "*i32", "*const i32", true));

    // --- Invalid: Pointer Ordering ---
    ASSERT_TRUE(check_binary_op("<", "*i32", "*i32", false, ERR_TYPE_MISMATCH));
    ASSERT_TRUE(check_binary_op(">=", "*u8", "*u8", false, ERR_TYPE_MISMATCH));

    // --- Valid: Boolean Equality ---
    ASSERT_TRUE(check_binary_op("==", "bool", "bool", true));
    ASSERT_TRUE(check_binary_op("!=", "bool", "bool", true));

    return true;
}

TEST_FUNC(TypeChecker_BinaryOps_Logical) {
    // --- Valid: Boolean Operands ---
    ASSERT_TRUE(check_binary_op("&&", "bool", "bool", true));
    ASSERT_TRUE(check_binary_op("||", "bool", "bool", true));

    // --- Invalid: Non-boolean Operands ---
    ASSERT_TRUE(check_binary_op("&&", "i32", "i32", false, ERR_TYPE_MISMATCH));
    ASSERT_TRUE(check_binary_op("||", "f64", "f64", false, ERR_TYPE_MISMATCH));
    ASSERT_TRUE(check_binary_op("&&", "*i32", "*i32", false, ERR_TYPE_MISMATCH));
    ASSERT_TRUE(check_binary_op("&&", "i32", "bool", false, ERR_TYPE_MISMATCH));

    return true;
}
