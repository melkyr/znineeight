#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include <cstdlib>
#include <cstring>

// Helper function from test_parser_errors.cpp
bool expect_parser_abort(const char* source);

// Test parsing a valid comptime block
TEST_FUNC(Parser_ComptimeBlock_Valid) {
    ArenaAllocator arena(4096);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    const char* source = "comptime { 123 }";
    ParserTestContext ctx(source, arena, interner);
    Parser parser = ctx.getParser();

    ASTNode* stmt = parser.parseStatement();
    ASSERT_TRUE(stmt != NULL);
    ASSERT_EQ(stmt->type, NODE_COMPTIME_BLOCK);

    ASTComptimeBlockNode* comptime_block = &stmt->as.comptime_block;
    ASSERT_TRUE(comptime_block->expression != NULL);
    ASSERT_EQ(comptime_block->expression->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(comptime_block->expression->as.integer_literal.value, 123);

    return true;
}

// Test that a comptime block must have an expression
TEST_FUNC(Parser_ComptimeBlock_Error_MissingExpression) {
    ASSERT_TRUE(expect_parser_abort("comptime { }"));
    return true;
}

// Test that a comptime block must have an opening brace
TEST_FUNC(Parser_ComptimeBlock_Error_MissingOpeningBrace) {
    ASSERT_TRUE(expect_parser_abort("comptime 123 }"));
    return true;
}

// Test that a comptime block must have a closing brace
TEST_FUNC(Parser_ComptimeBlock_Error_MissingClosingBrace) {
    ASSERT_TRUE(expect_parser_abort("comptime { 123"));
    return true;
}
