#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <cstring>
#include <string>

/**
 * @file while_loop_tests.cpp
 * @brief Integration tests for Zig while loops in the RetroZig compiler.
 */

static bool run_while_test(const char* zig_code, const char* fn_name, const char* expected_c89) {
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

// --- Condition Types ---

TEST_FUNC(WhileLoopIntegration_BoolCondition) {
    const char* source =
        "fn foo(b: bool) void {\n"
        "    while (b) { }\n"
        "}";
    return run_while_test(source, "foo", "void foo(int b) { while (b) { } }");
}

// --- Labeled Loops ---

TEST_FUNC(WhileLoopIntegration_LabeledWhile) {
    const char* source =
        "fn foo() void {\n"
        "    outer: while (true) {\n"
        "        break :outer;\n"
        "    }\n"
        "}";
    return run_while_test(source, "foo", "void foo(void) { __zig_label_outer_0_start: ; if (!(1)) goto __zig_label_outer_0_end; { goto __zig_label_outer_0_end; }  goto __zig_label_outer_0_start; __zig_label_outer_0_end: ; }");
}

TEST_FUNC(WhileLoopIntegration_LabeledContinue) {
    const char* source =
        "fn foo() void {\n"
        "    outer: while (true) {\n"
        "        continue :outer;\n"
        "    }\n"
        "}";
    return run_while_test(source, "foo", "void foo(void) { __zig_label_outer_0_start: ; if (!(1)) goto __zig_label_outer_0_end; { goto __zig_label_outer_0_start; }  goto __zig_label_outer_0_start; __zig_label_outer_0_end: ; }");
}

TEST_FUNC(WhileLoopIntegration_NestedLabeledWhile) {
    const char* source =
        "fn foo() void {\n"
        "    outer: while (true) {\n"
        "        inner: while (true) {\n"
        "            break :outer;\n"
        "        }\n"
        "    }\n"
        "}";
    // outer: id 0, inner: id 1
    return run_while_test(source, "foo",
        "void foo(void) { __zig_label_outer_0_start: ; if (!(1)) goto __zig_label_outer_0_end; "
        "{ __zig_label_inner_1_start: ; if (!(1)) goto __zig_label_inner_1_end; { goto __zig_label_outer_0_end; }  goto __zig_label_inner_1_start; __zig_label_inner_1_end: ; } "
        " goto __zig_label_outer_0_start; __zig_label_outer_0_end: ; }");
}

TEST_FUNC(WhileLoopIntegration_IntCondition) {
    const char* source =
        "fn foo(x: i32) void {\n"
        "    while (x) { }\n"
        "}";
    return run_while_test(source, "foo", "void foo(int x) { while (x) { } }");
}

TEST_FUNC(WhileLoopIntegration_PointerCondition) {
    const char* source =
        "fn foo(ptr: *i32) void {\n"
        "    while (ptr) { }\n"
        "}";
    return run_while_test(source, "foo", "void foo(int* ptr) { while (ptr) { } }");
}

// --- Break and Continue ---

TEST_FUNC(WhileLoopIntegration_WithBreak) {
    const char* source =
        "fn foo() void {\n"
        "    while (true) {\n"
        "        break;\n"
        "    }\n"
        "}";
    return run_while_test(source, "foo", "void foo(void) { while (1) { break; } }");
}

TEST_FUNC(WhileLoopIntegration_WithContinue) {
    const char* source =
        "fn foo() void {\n"
        "    var i: i32 = 0;\n"
        "    while (i < 10) {\n"
        "        i = i + 1;\n"
        "        continue;\n"
        "    }\n"
        "}";
    return run_while_test(source, "foo", "void foo(void) { int i = 0; while (i < 10) { i = i + 1; continue; } }");
}

// --- Nesting and Scoping ---

TEST_FUNC(WhileLoopIntegration_NestedWhile) {
    const char* source =
        "fn foo() void {\n"
        "    var i: i32 = 0;\n"
        "    while (i < 5) {\n"
        "        var j: i32 = 0;\n"
        "        while (j < 5) {\n"
        "            j = j + 1;\n"
        "        }\n"
        "        i = i + 1;\n"
        "    }\n"
        "}";
    return run_while_test(source, "foo",
        "void foo(void) { int i = 0; while (i < 5) { int j = 0; while (j < 5) { j = j + 1; } i = i + 1; } }");
}

TEST_FUNC(WhileLoopIntegration_Scoping) {
    const char* source =
        "fn foo() i32 {\n"
        "    while (true) {\n"
        "        var x: i32 = 42;\n"
        "        return x;\n"
        "    }\n"
        "    return 0;\n"
        "}";
    // x should be fine inside the loop
    return run_while_test(source, "foo", "int foo(void) { while (1) { int x = 42; return x; } return 0; }");
}

// --- Complex Conditions ---

TEST_FUNC(WhileLoopIntegration_ComplexCondition) {
    const char* source =
        "fn foo(a: i32, b: i32) void {\n"
        "    while (a > 0 and b < 10) {\n"
        "        break;\n"
        "    }\n"
        "}";
    return run_while_test(source, "foo", "void foo(int a, int b) { while (a > 0 && b < 10) { break; } }");
}

// --- Negative Tests ---

TEST_FUNC(WhileLoopIntegration_RejectFloatCondition) {
    const char* source =
        "fn foo() void {\n"
        "    var f: f64 = 3.14;\n"
        "    while (f) { }\n"
        "}";
    return expect_type_checker_abort(source);
}

TEST_FUNC(WhileLoopIntegration_RejectBracelessWhile) {
    const char* source =
        "fn foo(b: bool) void {\n"
        "    while (b) break;\n"
        "}";
    return expect_parser_abort(source);
}

TEST_FUNC(WhileLoopIntegration_EmptyWhileBlock) {
    const char* source =
        "fn foo(b: bool) void {\n"
        "    while (b) { }\n"
        "}";
    return run_while_test(source, "foo", "void foo(int b) { while (b) { } }");
}
