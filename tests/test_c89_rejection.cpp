#include "test_framework.hpp"
#include "test_utils.hpp"

TEST_FUNC(C89Rejection_Slice) {
    const char* source = "var my_slice: []u8 = undefined;";
    ASSERT_FALSE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(Task147_ErrDeferRejection) {
    const char* source = "fn f() void { errdefer {}; }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(Task147_AnyErrorRejection) {
    const char* source = "var x: anyerror = 0;";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(C89Rejection_NestedTryInMemberAccess) {
    const char* source =
        "const S = struct { f: i32 };\n"
        "fn getS() !S { return S { .f = 42 }; }\n"
        "fn main() !void { var x = (try getS()).f; return; }";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(C89Rejection_NestedTryInStructInitializer) {
    const char* source =
        "const S = struct { f: i32 };\n"
        "fn f() !i32 { return 42; }\n"
        "fn main() !void { var s = S { .f = try f() }; return; }";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(C89Rejection_NestedTryInArrayAccess) {
    const char* source =
        "fn getArr() ![5]i32 { return undefined; }\n"
        "fn main() !void { var x = (try getArr())[0]; return; }";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(C89Rejection_TryExpression) {
    const char* source = "fn f() !void { return; }\n fn main() !void { try f(); return; }";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(C89Rejection_CatchExpression) {
    const char* source = "fn f() !void { return; }\n fn main() void { f() catch {}; }";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(C89Rejection_OrelseExpression) {
    const char* source = "fn f() ?*i32 { return null; }\n fn main() void { f() orelse null; }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}
