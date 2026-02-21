#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>
#include <string>

/**
 * @file for_loop_tests.cpp
 * @brief Integration tests for Zig for loops in the RetroZig compiler.
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
        "void foo(void) {\n"
        "    int arr[3];\n"
        "    arr[0] = 1;\n"
        "    arr[1] = 2;\n"
        "    arr[2] = 3;\n"
        "    {\n"
        "        int* __for_iter_1 = arr;\n"
        "        size_t __for_idx_1 = 0;\n"
        "        size_t __for_len_1 = 3;\n"
        "        while (__for_idx_1 < __for_len_1) {\n"
        "            int item = __for_iter_1[__for_idx_1];\n"
        "{\n"
        "                (void)(item);\n"
        "            }\n"
        "            __for_idx_1++;\n"
        "        }\n"
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
        "void foo(Slice_i32 s) {\n"
        "    {\n"
        "        Slice_i32 __for_iter_1 = s;\n"
        "        size_t __for_idx_1 = 0;\n"
        "        size_t __for_len_1 = __for_iter_1.len;\n"
        "        while (__for_idx_1 < __for_len_1) {\n"
        "            int item = __for_iter_1.ptr[__for_idx_1];\n"
        "{\n"
        "                (void)(item);\n"
        "            }\n"
        "            __for_idx_1++;\n"
        "        }\n"
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
        "void foo(void) {\n"
        "    {\n"
        "        size_t __for_idx_1 = 0;\n"
        "        size_t __for_len_1 = 10;\n"
        "        while (__for_idx_1 < __for_len_1) {\n"
        "            unsigned int i = __for_idx_1;\n"
        "{\n"
        "                (void)(i);\n"
        "            }\n"
        "            __for_idx_1++;\n"
        "        }\n"
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
        "void foo(Slice_i32 s) {\n"
        "    {\n"
        "        Slice_i32 __for_iter_1 = s;\n"
        "        size_t __for_idx_1 = 0;\n"
        "        size_t __for_len_1 = __for_iter_1.len;\n"
        "        while (__for_idx_1 < __for_len_1) {\n"
        "            int item = __for_iter_1.ptr[__for_idx_1];\n"
        "            size_t i = __for_idx_1;\n"
        "{\n"
        "                (void)(item);\n"
        "                (void)(i);\n"
        "            }\n"
        "            __for_idx_1++;\n"
        "        }\n"
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
        "void foo(void) {\n"
        "    {\n"
        "        size_t __for_idx_1 = 0;\n"
        "        size_t __for_len_1 = 10;\n"
        "        __zig_label_outer_0_start: ;\n"
        "        while (__for_idx_1 < __for_len_1) {\n"
        "            unsigned int item = __for_idx_1;\n"
        "{\n"
        "                /* defers for break */\n"
        "                goto __zig_label_outer_0_end;\n"
        "            }\n"
        "            __for_idx_1++;\n"
        "            goto __zig_label_outer_0_start;\n"
        "        }\n"
        "        __zig_label_outer_0_end: ;\n"
        "    }\n"
        "}";
    return run_for_test(source, "foo", expected);
}
