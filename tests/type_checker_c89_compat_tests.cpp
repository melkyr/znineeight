#include "test_framework.hpp"
#include "test_utils.hpp"
#include "ast.hpp"
#include "parser.hpp"
#include "type_checker.hpp"

// Forward declarations for test functions
// Forward declarations for test functions
TEST_FUNC(TypeCheckerC89Compat_RejectFunctionWithTooManyArgs);
// TEST_FUNC(TypeCheckerC89Compat_RejectFunctionPointerCall);
TEST_FUNC(TypeChecker_Call_WrongArgumentCount);
TEST_FUNC(TypeChecker_Call_IncompatibleArgumentType);

TEST_FUNC(TypeCheckerC89Compat_RejectFunctionWithTooManyArgs) {
    const char* source =
        "fn five_args(a: i32, b: i32, c: i32, d: i32, e: i32) -> void {}\n"
        "fn main() -> void {\n"
        "    five_args(1, 2, 3, 4, 5);\n"
        "}\n";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

// TODO: Re-enable this test once the parser supports type inference for variable
// declarations. Currently, the test `var func_ptr = my_func;` causes the parser
// to abort, making this test pass for the wrong reason.
TEST_FUNC(TypeCheckerC89Compat_RejectFunctionPointerCall) {
    // const char* source =
    //     "fn my_func() -> void {}\n"
    //     "fn main() -> void {\n"
    //     "    var func_ptr: fn() -> void = my_func;\n" // This syntax is also not yet supported
    //     "    func_ptr();\n"
    //     "}\n";
    // ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeChecker_Call_WrongArgumentCount) {
    const char* source =
        "fn two_args(a: i32, b: i32) -> void {}\n"
        "fn main() -> void {\n"
        "    two_args(1);\n"
        "}\n";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeChecker_Call_IncompatibleArgumentType) {
    const char* source =
        "fn needs_i32(a: i32) -> void {}\n"
        "fn main() -> void {\n"
        "    needs_i32(\"hello\");\n"
        "}\n";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}
