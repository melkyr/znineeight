#include "test_framework.hpp"
#include "test_utils.hpp"

// Task 115: Detect slice parameter types
TEST_FUNC(TypeChecker_RejectSliceInFunctionParameter) {
    const char* source = "fn my_func(s: []u8) {}";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

// Task 116: Detect slice return types
TEST_FUNC(TypeChecker_RejectSliceInFunctionReturnType) {
    const char* source = "fn my_func() -> []u8 { return null; }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

// Task 117: Detect slice literal creation (via variable declaration)
TEST_FUNC(TypeChecker_RejectSliceInVariableDeclaration) {
    const char* source = "var my_slice: []const u8 = \"hello\";";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}
