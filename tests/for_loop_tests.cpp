#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>
#include <string>

/**
 * @file for_loop_tests.cpp
 * @brief Integration tests for Zig for loops in the Z98 compiler.
 */

static bool run_for_test(const char* zig_code, const char* fn_name, const char* expected_c89) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateRealFunctionEmission(fn_name, expected_c89)) {
        return false;
    }

    return true;
}

TEST_FUNC(ForIntegration_Array) {
    const char* source =
        "pub fn foo() void {\n"
        "    var arr: [3]i32 = [3]i32 { 1, 2, 3 };\n"
        "    for (arr) |item| {\n"
        "        _ = item;\n"
        "    }\n"
        "}";
    const char* expected =
        "void zF_0_foo(void) {\n"
        "    int arr[3] = {1, 2, 3};\n"
        "    {\n"
        "        int* #;\n"
        "        # = arr;\n"
        "        usize #;\n"
        "        # = 0;\n"
        "        usize #;\n"
        "        # = 3;\n"
        "        __loop_0_start: ;\n"
        "        while (# < #) {\n"
        "            int item = #[#];\n"
        "            {\n"
        "                (void)(item);\n"
        "            }\n"
        "            __loop_0_continue: ;\n"
        "            #++;\n"
        "            goto __loop_0_start;\n"
        "        }\n"
        "        __loop_0_end: ;\n"
        "    }\n"
        "}";
    return run_for_test(source, "foo", expected);
}

TEST_FUNC(ForIntegration_Slice) {
    const char* source =
        "pub fn foo(s: []i32) void {\n"
        "    for (s) |item| {\n"
        "        _ = item;\n"
        "    }\n"
        "}";
    const char* expected =
        "void zF_0_foo(Slice_i32 s) {\n"
        "    {\n"
        "        Slice_i32 #;\n"
        "        # = s;\n"
        "        usize #;\n"
        "        # = 0;\n"
        "        usize #;\n"
        "        # = #.len;\n"
        "        __loop_0_start: ;\n"
        "        while (# < #) {\n"
        "            int item = #.ptr[#];\n"
        "            {\n"
        "                (void)(item);\n"
        "            }\n"
        "            __loop_0_continue: ;\n"
        "            #++;\n"
        "            goto __loop_0_start;\n"
        "        }\n"
        "        __loop_0_end: ;\n"
        "    }\n"
        "}";
    return run_for_test(source, "foo", expected);
}

TEST_FUNC(ForIntegration_Range) {
    const char* source =
        "pub fn foo() void {\n"
        "    for (0..10) |i| {\n"
        "        _ = i;\n"
        "    }\n"
        "}";
    const char* expected =
        "void zF_0_foo(void) {\n"
        "    {\n"
        "        usize #;\n"
        "        # = 0;\n"
        "        usize #;\n"
        "        # = 10;\n"
        "        __loop_0_start: ;\n"
        "        while (# < #) {\n"
        "            usize i = #;\n"
        "            {\n"
        "                (void)(i);\n"
        "            }\n"
        "            __loop_0_continue: ;\n"
        "            #++;\n"
        "            goto __loop_0_start;\n"
        "        }\n"
        "        __loop_0_end: ;\n"
        "    }\n"
        "}";
    return run_for_test(source, "foo", expected);
}

TEST_FUNC(ForIntegration_IndexCapture) {
    const char* source =
        "pub fn foo(s: []i32) void {\n"
        "    for (s) |item, i| {\n"
        "        _ = item;\n"
        "        _ = i;\n"
        "    }\n"
        "}";
    const char* expected =
        "void zF_0_foo(Slice_i32 s) {\n"
        "    {\n"
        "        Slice_i32 #;\n"
        "        # = s;\n"
        "        usize #;\n"
        "        # = 0;\n"
        "        usize #;\n"
        "        # = #.len;\n"
        "        __loop_0_start: ;\n"
        "        while (# < #) {\n"
        "            int item = #.ptr[#];\n"
        "            size_t i = #;\n"
        "            {\n"
        "                (void)(item);\n"
        "                (void)(i);\n"
        "            }\n"
        "            __loop_0_continue: ;\n"
        "            #++;\n"
        "            goto __loop_0_start;\n"
        "        }\n"
        "        __loop_0_end: ;\n"
        "    }\n"
        "}";
    return run_for_test(source, "foo", expected);
}

TEST_FUNC(ForIntegration_Labeled) {
    const char* source =
        "pub fn foo() void {\n"
        "    outer: for (0..10) |item| {\n"
        "        break :outer;\n"
        "    }\n"
        "}";
    const char* expected =
        "void zF_0_foo(void) {\n"
        "    {\n"
        "        usize #;\n"
        "        # = 0;\n"
        "        usize #;\n"
        "        # = 10;\n"
        "        __loop_0_start: ;\n"
        "        while (# < #) {\n"
        "            usize item = #;\n"
        "            {\n"
        "                /* defers for break */\n"
        "                goto __loop_0_end;\n"
        "            }\n"
        "            __loop_0_continue: ;\n"
        "            #++;\n"
        "            goto __loop_0_start;\n"
            "        }\n"
        "        __loop_0_end: ;\n"
        "    }\n"
        "}";
    return run_for_test(source, "foo", expected);
}
