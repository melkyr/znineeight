#include "test_framework.hpp"
#include "test_utils.hpp"

TEST_FUNC(Parser_Error_OnMissingColon) {
    // This source code is missing a colon after the identifier 'x'
    const char* source = "var x i32 = 42;";
    ASSERT_TRUE(expect_statement_parser_abort(source));
    return true;
}

TEST_FUNC(Parser_Struct_Error_MissingLBrace) {
    ASSERT_TRUE(expect_statement_parser_abort("struct"));
    return true;
}

TEST_FUNC(Parser_Struct_Error_MissingRBrace) {
    ASSERT_TRUE(expect_statement_parser_abort("struct {"));
    return true;
}

TEST_FUNC(Parser_Struct_Error_MissingColon) {
    ASSERT_TRUE(expect_statement_parser_abort("struct { a i32 }"));
    return true;
}

TEST_FUNC(Parser_Struct_Error_MissingType) {
    ASSERT_TRUE(expect_statement_parser_abort("struct { a : }"));
    return true;
}

TEST_FUNC(Parser_Struct_Error_InvalidField) {
    ASSERT_TRUE(expect_statement_parser_abort("struct { 123 }"));
    return true;
}
