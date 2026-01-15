#include "../src/include/test_framework.hpp"
#include "test_utils.hpp"

TEST_FUNC(TypeChecker_AddressOf_RValueLiteral) {
    const char* source = "fn main() -> i32 { var x: *i32 = &10; return 0; }";
    // Expect the type checker to abort because you can't take the address of a literal
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeChecker_AddressOf_RValueExpression) {
    const char* source = "fn main() -> i32 { var x: i32; var y: i32; var z: *i32 = &(x + y); return 0; }";
    // Expect the type checker to abort because you can't take the address of an r-value expression
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}
