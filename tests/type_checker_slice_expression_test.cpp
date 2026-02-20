#include "test_framework.hpp"
#include "test_utils.hpp"

TEST_FUNC(TypeChecker_AllowSliceExpression) {
    const char* source = "var my_array: [16]i32; var x = my_array[0..4];";
    ASSERT_FALSE(expect_type_checker_abort(source));
    return true;
}
