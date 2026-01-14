#include "test_framework.hpp"
#include "test_utils.hpp"

TEST_FUNC(C89Rejection_Slice) {
    const char* source = "var my_slice: []u8;";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(C89Rejection_TryExpression) {
    const char* source = "fn f() !void {}\n fn main() void { try f(); }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(C89Rejection_CatchExpression) {
    const char* source = "fn f() !void {}\n fn main() void { f() catch {}; }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(C89Rejection_OrelseExpression) {
    const char* source = "fn f() ?*i32 { return null; }\n fn main() void { f() orelse null; }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}
