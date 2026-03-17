#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>

/**
 * @file while_switch_control_flow.cpp
 * @brief Integration tests for break/continue inside a switch nested in a while loop.
 */

static bool run_while_switch_control_flow_test(const char* zig_code, const char* fn_name, const char* expected_substring) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateFunctionEmissionSubstring(fn_name, expected_substring)) {
        return false;
    }

    return true;
}

TEST_FUNC(WhileSwitch_BreakExitsLoop) {
    const char* source =
        "fn foo(x: i32) void {\n"
        "    while (true) {\n"
        "        switch (x) {\n"
        "            1 => break,\n"
            "            else => {},\n"
        "        }\n"
        "    }\n"
        "}";
    // We expect 'goto __loop_0_end;' instead of C 'break;' inside the switch case.
    return run_while_switch_control_flow_test(source, "foo", "goto __loop_0_end;");
}

TEST_FUNC(WhileSwitch_ContinueTargetsLoop) {
    const char* source =
        "fn foo(x: i32) void {\n"
        "    while (true) {\n"
        "        switch (x) {\n"
        "            1 => continue,\n"
        "            else => {},\n"
        "        }\n"
        "    }\n"
        "}";
    // We expect 'goto __loop_0_continue;'
    return run_while_switch_control_flow_test(source, "foo", "goto __loop_0_continue;");
}

TEST_FUNC(WhileSwitch_NestedLoops) {
    const char* source =
        "fn foo(x: i32) void {\n"
        "    outer: while (true) {\n"
        "        while (true) {\n"
        "            switch (x) {\n"
        "                1 => break :outer,\n"
        "                2 => break,\n" // should exit inner loop
        "                else => {},\n"
        "            }\n"
        "        }\n"
        "    }\n"
        "}";
    // break :outer -> goto __loop_0_end;
    // break -> goto __loop_1_end;
    bool ok = run_while_switch_control_flow_test(source, "foo", "goto __loop_0_end;");
    if (!ok) return false;
    return run_while_switch_control_flow_test(source, "foo", "goto __loop_1_end;");
}

TEST_FUNC(ForSwitch_BreakExitsLoop) {
    const char* source =
        "fn foo(slice: []i32) void {\n"
        "    for (slice) |item| {\n"
        "        switch (item) {\n"
        "            1 => break,\n"
        "            else => {},\n"
        "        }\n"
        "    }\n"
        "}";
    // For loops already used the labeled pattern.
    return run_while_switch_control_flow_test(source, "foo", "goto __loop_0_end;");
}
