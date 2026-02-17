#include "test_framework.hpp"
#include "test_utils.hpp"
#include <cstring>
#include <cstdio>

TEST_FUNC(Parser_RecursionLimit) {
    // Create a very deeply nested expression string to trigger the recursion limit.
    // Example: "((...((1))...))"
    char source[2048] = {0};
    strcat(source, "var x: i32 = ");
    for (int i = 0; i < 300; ++i) { // 300 is well over the limit of 255
        strcat(source, "(");
    }
    strcat(source, "1");
    for (int i = 0; i < 300; ++i) {
        strcat(source, ")");
    }
    strcat(source, ";");

    // This test is designed to check that the parser aborts.
    // We expect `expect_parser_abort` to return true.
    ASSERT_TRUE(expect_statement_parser_abort(source));

    return true;
}

TEST_FUNC(Parser_RecursionLimit_Binary) {
    // Create a deeply nested binary expression: "a = a = a = ..."
    // Assignment is right-associative and recursive in this parser.
    char source[4096] = {0};
    strcat(source, "fn foo() void { var a: i32 = 0; ");
    for (int i = 0; i < 300; ++i) {
        strcat(source, "a = ");
    }
    strcat(source, "0; }");

    ASSERT_TRUE(expect_statement_parser_abort(source));

    return true;
}

TEST_FUNC(Parser_RecursionLimit_Unary) {
    // Create a deeply nested unary expression using `try`, which is recursive.
    char source[4096] = {0};
    strcat(source, "var x: i32 = ");
    for (int i = 0; i < 300; ++i) {
        strcat(source, "try ");
    }
    strcat(source, "1;");

    ASSERT_TRUE(expect_statement_parser_abort(source));

    return true;
}
