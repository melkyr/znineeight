#include "test_framework.hpp"
#include "test_utils.hpp"
#include "ast.hpp"
#include "parser.hpp"
#include "type_checker.hpp"
#include "compilation_unit.hpp"

// --- Positive Tests: Allowed Types ---

TEST_FUNC(BootstrapTypes_Allowed_Primitives) {
    const char* primitives[] = {
        "var a: i8 = 0;", "var b: i16 = 0;", "var c: i32 = 0;", "var d: i64 = 0;",
        "var e: u8 = 0;", "var f: u16 = 0;", "var g: u32 = 0;", "var h: u64 = 0;",
        "var i: f32 = 0;", "var j: f64 = 0.0;", "var k: bool = true;",
        "var l: isize = 0;", "var m: usize = 0;"
    };

    for (size_t i = 0; i < sizeof(primitives) / sizeof(primitives[0]); ++i) {
        ASSERT_TRUE(run_type_checker_test_successfully(primitives[i]));
    }
    return true;
}

TEST_FUNC(BootstrapTypes_Allowed_Pointers) {
    const char* source =
        "var a: *i32 = null;\n"
        "var b: *const u8 = null;\n"
        "var c: *void = null;\n"
        "var d: **i32 = null;\n";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(BootstrapTypes_Allowed_Arrays) {
    const char* source = "var a: [10]i32;";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(BootstrapTypes_Allowed_Structs) {
    const char* source =
        "const S = struct { x: i32, y: f64 };\n"
        "var s: S = S { .x = 1, .y = 2.0 };";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(BootstrapTypes_Allowed_Enums) {
    const char* source =
        "const E = enum { A, B, C };\n"
        "var e: E = E.A;";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

// --- Negative Tests: Rejected Types ---

TEST_FUNC(BootstrapTypes_Rejected_Slice) {
    ASSERT_TRUE(expect_type_checker_abort("var x: []u8 = 0;"));
    return true;
}

TEST_FUNC(BootstrapTypes_Rejected_ErrorUnion) {
    ASSERT_TRUE(expect_type_checker_abort("var x: !i32 = 0;"));
    return true;
}

TEST_FUNC(BootstrapTypes_Rejected_Optional) {
    ASSERT_TRUE(expect_type_checker_abort("var x: ?i32 = null;"));
    return true;
}

TEST_FUNC(BootstrapTypes_Allowed_FunctionPointer) {
    const char* source = "fn f(p: fn(i32) void) void {}";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(BootstrapTypes_Rejected_VoidVariable) {
    const char* source = "var x: void;";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(BootstrapTypes_Rejected_TooManyArgs) {
    /* Zig functions use -> return_type or just return_type */
    const char* source = "fn f(a: i32, b: i32, c: i32, d: i32, e: i32) void {}";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}
