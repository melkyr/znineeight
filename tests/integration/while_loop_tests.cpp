#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <cstring>
#include <string>

/**
 * @file while_loop_tests.cpp
 * @brief Integration tests for Zig while loops in the Z98 compiler.
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
    return run_while_test(source, "foo", "void zF_0_foo(int b) { __loop_0_start: ; if (!(b)) goto __loop_0_end; { } __loop_0_continue: ; goto __loop_0_start; __loop_0_end: ; }");
}

// --- Labeled Loops ---

TEST_FUNC(WhileLoopIntegration_LabeledWhile) {
    const char* source =
        "fn foo() void {\n"
        "    outer: while (true) {\n"
        "        break :outer;\n"
        "    }\n"
        "}";
    return run_while_test(source, "foo", "void zF_0_foo(void) { __loop_0_start: ; if (!(1)) goto __loop_0_end; { goto __loop_0_end; }  __loop_0_continue: ; goto __loop_0_start; __loop_0_end: ; }");
}

TEST_FUNC(WhileLoopIntegration_LabeledContinue) {
    const char* source =
        "fn foo() void {\n"
        "    outer: while (true) {\n"
        "        continue :outer;\n"
        "    }\n"
        "}";
    return run_while_test(source, "foo", "void zF_0_foo(void) { __loop_0_start: ; if (!(1)) goto __loop_0_end; { goto __loop_0_continue; }  __loop_0_continue: ;  goto __loop_0_start; __loop_0_end: ; }");
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
        "void zF_0_foo(void) { __loop_0_start: ; if (!(1)) goto __loop_0_end; "
        "{ __loop_1_start: ; if (!(1)) goto __loop_1_end; { goto __loop_0_end; }  __loop_1_continue: ; goto __loop_1_start; __loop_1_end: ; } "
        " __loop_0_continue: ; goto __loop_0_start; __loop_0_end: ; }");
}

TEST_FUNC(WhileLoopIntegration_IntCondition) {
    const char* source =
        "fn foo(x: i32) void {\n"
        "    while (x) { }\n"
        "}";
    return run_while_test(source, "foo", "void zF_0_foo(int x) { __loop_0_start: ; if (!(x)) goto __loop_0_end; { } __loop_0_continue: ; goto __loop_0_start; __loop_0_end: ; }");
}

TEST_FUNC(WhileLoopIntegration_PointerCondition) {
    const char* source =
        "fn foo(ptr: *i32) void {\n"
        "    while (ptr) { }\n"
        "}";
    return run_while_test(source, "foo", "void zF_0_foo(int* ptr) { __loop_0_start: ; if (!(ptr)) goto __loop_0_end; { } __loop_0_continue: ; goto __loop_0_start; __loop_0_end: ; }");
}

// --- Break and Continue ---

TEST_FUNC(WhileLoopIntegration_WithBreak) {
    const char* source =
        "fn foo() void {\n"
        "    while (true) {\n"
        "        break;\n"
        "    }\n"
        "}";
    return run_while_test(source, "foo", "void zF_0_foo(void) { __loop_0_start: ; if (!(1)) goto __loop_0_end; { /* defers for break */ goto __loop_0_end; } __loop_0_continue: ; goto __loop_0_start; __loop_0_end: ; }");
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
    return run_while_test(source, "foo", "void zF_#_foo(void) { int i = 0; __loop_0_start: ; if (!(i < 10)) goto __loop_0_end; { i = i + 1; /* defers for continue */ goto __loop_0_continue; } __loop_0_continue: ; goto __loop_0_start; __loop_0_end: ; }");
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
        "void zF_#_foo(void) { int i = 0; __loop_0_start: ; if (!(i < 5)) goto __loop_0_end; { int j = 0; __loop_1_start: ; if (!(j < 5)) goto __loop_1_end; { j = j + 1; } __loop_1_continue: ; goto __loop_1_start; __loop_1_end: ; i = i + 1; } __loop_0_continue: ; goto __loop_0_start; __loop_0_end: ; }");
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
    return run_while_test(source, "foo", "int zF_0_foo(void) { __loop_0_start: ; if (!(1)) goto __loop_0_end; { int x = 42; return x; } __loop_0_continue: ; goto __loop_0_start; __loop_0_end: ; return 0; }");
}

// --- Complex Conditions ---

TEST_FUNC(WhileLoopIntegration_ComplexCondition) {
    const char* source =
        "fn foo(a: i32, b: i32) void {\n"
        "    while (a > 0 and b < 10) {\n"
        "        break;\n"
        "    }\n"
        "}";
    return run_while_test(source, "foo", "void zF_0_foo(int a, int b) { __loop_0_start: ; if (!(a > 0 && b < 10)) goto __loop_0_end; { /* defers for break */ goto __loop_0_end; } __loop_0_continue: ; goto __loop_0_start; __loop_0_end: ; }");
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

TEST_FUNC(WhileLoopIntegration_AllowBracelessWhile) {
    const char* source =
        "fn foo(b: bool) void {\n"
        "    while (b) break;\n"
        "}";
    return run_while_test(source, "foo", "void zF_0_foo(int b) { __loop_0_start: ; if (!(b)) goto __loop_0_end; { /* defers for break */ goto __loop_0_end; } __loop_0_continue: ; goto __loop_0_start; __loop_0_end: ; }");
}

TEST_FUNC(WhileLoopIntegration_EmptyWhileBlock) {
    const char* source =
        "fn foo(b: bool) void {\n"
        "    while (b) { }\n"
        "}";
    return run_while_test(source, "foo", "void zF_0_foo(int b) { __loop_0_start: ; if (!(b)) goto __loop_0_end; { } __loop_0_continue: ; goto __loop_0_start; __loop_0_end: ; }");
}
