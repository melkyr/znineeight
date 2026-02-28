#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>
#include <cstring>

/**
 * @file batch50_tests.cpp
 * @brief Regression tests for Task 9.5.14: Error Reporting Consistency and Stack Analysis.
 */

TEST_FUNC(SentinelPattern_CascadingErrors) {
    const char* source =
        "fn foo() void {\n"
        "    var x: i32 = (1 + \"str\") + (2 + true);\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline should have failed.\n");
        return false;
    }

    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();

    /* We expect exactly 1 error from the first additions.
       The additions should NOT report further errors because they receive 'undefined' sentinels. */
    if (errors.length() != 1) {
        printf("FAIL: Expected exactly 1 error, got %d.\n", (int)errors.length());
        unit.getErrorHandler().printErrors();
        return false;
    }

    bool found_str_error = false;

    for (size_t i = 0; i < errors.length(); ++i) {
        const char* msg = errors[i].hint ? errors[i].hint : errors[i].message;
        if (msg && strstr(msg, "arithmetic operation '+' requires operands of the same type. Got 'i32' and '*const u8'")) {
            found_str_error = true;
        }
    }

    if (!found_str_error) {
        printf("FAIL: Could not find specific error message.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(SentinelPattern_RecursionLimit) {
    /* Create a deeply nested expression to trigger the recursion limit.
       MAX_VISIT_DEPTH is 200.
       We use many BinaryOps instead of Parens to stay under Parser limit (255)
       while exceeding TypeChecker limit (200). */
    char source[8192];
    char* p = source;
    p += sprintf(p, "fn foo() void {\n    var x = 1");
    for (int i = 0; i < 205; ++i) {
        p += sprintf(p, " + 1");
    }
    p += sprintf(p, ";\n}\n");

    ArenaAllocator arena(2 * 1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline should have failed due to recursion limit.\n");
        return false;
    }

    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();

    bool found_limit_error = false;
    for (size_t i = 0; i < errors.length(); ++i) {
        const char* msg = errors[i].hint ? errors[i].hint : errors[i].message;
        if (errors[i].code == ERR_INTERNAL_ERROR && msg && strstr(msg, "Exceeded maximum recursion depth")) {
            found_limit_error = true;
            break;
        }
    }

    if (!found_limit_error) {
        printf("FAIL: Did not find recursion depth error.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}
