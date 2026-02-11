#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"

TEST_FUNC(IntegerWidening_Signed_Valid) {
    const char* source =
        "fn take_i64(x: i64) void {}\n"
        "fn foo(x: i32) void {\n"
        "    take_i64(x);\n" // i32 -> i64 (widening)
        "}\n";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(IntegerWidening_Args_Signed) {
    const char* source =
        "fn take_i64(x: i64) void {}\n"
        "fn foo() void {\n"
        "    var x: i32 = 42;\n"
        "    take_i64(x);\n" // i32 -> i64 (widening) - allowed in areTypesCompatible
        "}\n";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(IntegerWidening_Args_ISize) {
    const char* source =
        "fn take_isize(x: isize) void {}\n"
        "fn foo() void {\n"
        "    var x: i32 = 42;\n"
        "    take_isize(x);\n" // i32 -> isize (same size) - allowed
        "}\n";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(IntegerNarrowing_Args_Error) {
    const char* source =
        "fn take_i32(x: i32) void {}\n"
        "fn foo() void {\n"
        "    var x: i64 = 42;\n"
        "    take_i32(x);\n" // i64 -> i32 (narrowing) - rejected
        "}\n";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(IntegerNarrowing_ISize_Error) {
    const char* source =
        "fn take_isize(x: isize) void {}\n"
        "fn foo() void {\n"
        "    var x: i64 = 42;\n"
        "    take_isize(x);\n" // i64 -> isize (narrowing) - rejected
        "}\n";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(IntegerWidening_Args_Unsigned) {
    const char* source =
        "fn take_u64(x: u64) void {}\n"
        "fn foo() void {\n"
        "    var x: u32 = 42;\n"
        "    take_u64(x);\n" // u32 -> u64 (widening) - allowed
        "}\n";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(IntegerWidening_Args_USize) {
    const char* source =
        "fn take_usize(x: usize) void {}\n"
        "fn foo() void {\n"
        "    var x: u32 = 42;\n"
        "    take_usize(x);\n" // u32 -> usize (same size) - allowed
        "}\n";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}
