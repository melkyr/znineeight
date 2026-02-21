#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>
#include <string>

/**
 * @file defer_tests.cpp
 * @brief Integration tests for Zig defer statements in the RetroZig compiler.
 */

static bool run_defer_test(const char* zig_code, const char* fn_name, const char* expected_c89) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateFunctionEmission(fn_name, expected_c89)) {
        return false;
    }

    return true;
}

TEST_FUNC(DeferIntegration_Basic) {
    const char* source =
        "fn foo() void {\n"
        "    var x: i32 = 0;\n"
        "    defer x = 1;\n"
        "    x = 2;\n"
        "}";
    // x = 1 should be emitted before the closing brace of foo's body block.
    return run_defer_test(source, "foo", "void foo(void) { int x = 0; x = 2; x = 1; }");
}

TEST_FUNC(DeferIntegration_LIFO) {
    const char* source =
        "fn foo() void {\n"
        "    var x: i32 = 0;\n"
        "    defer x = 1;\n"
        "    defer x = 2;\n"
        "    x = 10;\n"
        "}";
    return run_defer_test(source, "foo", "void foo(void) { int x = 0; x = 10; x = 2; x = 1; }");
}

TEST_FUNC(DeferIntegration_Return) {
    const char* source =
        "fn foo() i32 {\n"
        "    var x: i32 = 10;\n"
        "    defer x = 20;\n"
        "    return x;\n"
        "}";
    return run_defer_test(source, "foo", "int foo(void) { int x = 10; { int __return_val = x; x = 20; return __return_val; } x = 20; }");
}

TEST_FUNC(DeferIntegration_NestedScopes) {
    const char* source =
        "fn foo() void {\n"
        "    defer a();\n"
        "    {\n"
        "        defer b();\n"
        "    }\n"
        "}\n"
        "fn a() void {}\n"
        "fn b() void {}";
    // b() should run at end of its block, a() at end of foo.
    return run_defer_test(source, "foo", "void foo(void) { { b(); } a(); }");
}

TEST_FUNC(DeferIntegration_Break) {
    const char* source =
        "fn foo() void {\n"
        "    while (true) {\n"
        "        defer bar();\n"
        "        break;\n"
        "    }\n"
        "}\n"
        "fn bar() void {}";
    return run_defer_test(source, "foo", "void foo(void) { while (1) { /* defers for break */ bar(); break; bar(); } }");
}

TEST_FUNC(DeferIntegration_LabeledBreak) {
    const char* source =
        "fn foo() void {\n"
        "    outer: while (true) {\n"
        "        defer a();\n"
        "        while (true) {\n"
        "            defer b();\n"
        "            break :outer;\n"
        "        }\n"
        "    }\n"
        "}\n"
        "fn a() void {}\n"
        "fn b() void {}";
    return run_defer_test(source, "foo", "void foo(void) { __zig_label_outer_0_start: ; if (!(1)) goto __zig_label_outer_0_end; { while (1) { /* defers for break */ b(); a(); goto __zig_label_outer_0_end; b(); } a(); } goto __zig_label_outer_0_start; __zig_label_outer_0_end: ; }");
}

TEST_FUNC(DeferIntegration_Continue) {
    const char* source =
        "fn foo() void {\n"
        "    while (true) {\n"
        "        defer bar();\n"
        "        continue;\n"
        "    }\n"
        "}\n"
        "fn bar() void {}";
    return run_defer_test(source, "foo", "void foo(void) { while (1) { /* defers for continue */ bar(); continue; bar(); } }");
}

TEST_FUNC(DeferIntegration_RejectReturn) {
    const char* source =
        "fn foo() void {\n"
        "    defer return;\n"
        "}";
    return expect_type_checker_abort(source);
}

TEST_FUNC(DeferIntegration_RejectBreak) {
    const char* source =
        "fn foo() void {\n"
        "    while (true) {\n"
        "        defer break;\n"
        "    }\n"
        "}";
    return expect_type_checker_abort(source);
}
