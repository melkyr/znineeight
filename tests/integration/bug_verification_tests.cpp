#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>

/**
 * @file bug_verification_tests.cpp
 * @brief Integration tests to verify reported bugs.
 */

// Bug 1a: Implicit unwrapping of error unions in comparison
TEST_FUNC(BugVerify_ImplicitUnwrapErrorUnion) {
    const char* source =
        "fn testFn(err: !i32, x: i32) bool {\n"
        "    return err == x;\n"
        "}\n";

    if (run_type_checker_test_successfully(source)) {
        printf("Regression test FAILED: Implicit unwrapping of error union in comparison was ALLOWED.\n");
        return false;
    } else {
        printf("Regression test PASSED: Implicit unwrapping of error union in comparison was REJECTED.\n");
        return true;
    }
}

// Bug 1b: Implicit unwrapping of optionals in comparison
TEST_FUNC(BugVerify_ImplicitUnwrapOptional) {
    const char* source =
        "fn testFn(opt: ?i32, x: i32) bool {\n"
        "    return opt == x;\n"
        "}\n";

    if (run_type_checker_test_successfully(source)) {
        printf("Regression test FAILED: Implicit unwrapping of optional in comparison was ALLOWED.\n");
        return false;
    } else {
        printf("Regression test PASSED: Implicit unwrapping of optional in comparison was REJECTED.\n");
        return true;
    }
}

// Bug 2: Missing comma after block prong in switch
TEST_FUNC(BugVerify_SwitchMissingCommaBlock) {
    const char* source =
        "fn testFn(x: i32) void {\n"
        "    switch (x) {\n"
        "        1 => { }\n"  // MISSING COMMA HERE (not last prong)
        "        2 => { },\n"
        "        else => { },\n"
        "    }\n"
        "}\n";

    if (expect_parser_abort(source)) {
        printf("Regression test PASSED: Switch block prong missing comma was REJECTED.\n");
        return true;
    } else {
        printf("Regression test FAILED: Switch block prong missing comma was ALLOWED.\n");
        return false;
    }
}

// Bug: Switch expression missing else
TEST_FUNC(BugVerify_SwitchExprMissingElse) {
    const char* source =
        "fn testFn(x: i32) void {\n"
        "    var y = switch (x) {\n"
        "        0 => 1,\n"
        "        1 => 2,\n"
        "    };\n"
        "}\n";

    if (run_type_checker_test_successfully(source)) {
        printf("Regression test FAILED: Switch expression missing 'else' was ALLOWED.\n");
        return false;
    } else {
        printf("Regression test PASSED: Switch expression missing 'else' was REJECTED.\n");
        return true;
    }
}
