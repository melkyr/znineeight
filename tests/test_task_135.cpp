#include "test_framework.hpp"
#include "test_utils.hpp"

TEST_FUNC(C89Rejection_ErrorUnionType_FnReturn) {
    const char* source = "fn foo() !i32 { return 42; }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(C89Rejection_OptionalType_VarDecl) {
    const char* source = "var x: ?i32 = null;";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(C89Rejection_ErrorUnionType_Param) {
    const char* source = "fn foo(x: !i32) void {}";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(C89Rejection_ErrorUnionType_StructField) {
    const char* source = "const S = struct { field: !i32 };";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(C89Rejection_NestedErrorUnionType) {
    const char* source = "var x: *!u8 = null;";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}
