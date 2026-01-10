#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"

// Helper function from test_parser_errors.cpp
bool expect_parser_abort(const char* source);

TEST_FUNC(Parser_IfStatement_Simple) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("if (1) {}", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* if_stmt_node = parser->parseIfStatement();

    ASSERT_TRUE(if_stmt_node != NULL);
    ASSERT_EQ(if_stmt_node->type, NODE_IF_STMT);

    ASTIfStmtNode* if_stmt = if_stmt_node->as.if_stmt;
    ASSERT_TRUE(if_stmt->condition != NULL);
    ASSERT_EQ(if_stmt->condition->type, NODE_INTEGER_LITERAL);
    ASSERT_TRUE(if_stmt->then_block != NULL);
    ASSERT_EQ(if_stmt->then_block->type, NODE_BLOCK_STMT);
    ASSERT_TRUE(if_stmt->else_block == NULL);

    return true;
}

TEST_FUNC(Parser_IfStatement_WithElse) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("if (1) {} else {}", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* if_stmt_node = parser->parseIfStatement();

    ASSERT_TRUE(if_stmt_node != NULL);
    ASSERT_EQ(if_stmt_node->type, NODE_IF_STMT);

    ASTIfStmtNode* if_stmt = if_stmt_node->as.if_stmt;
    ASSERT_TRUE(if_stmt->condition != NULL);
    ASSERT_EQ(if_stmt->condition->type, NODE_INTEGER_LITERAL);
    ASSERT_TRUE(if_stmt->then_block != NULL);
    ASSERT_EQ(if_stmt->then_block->type, NODE_BLOCK_STMT);
    ASSERT_TRUE(if_stmt->else_block != NULL);
    ASSERT_EQ(if_stmt->else_block->type, NODE_BLOCK_STMT);

    return true;
}

TEST_FUNC(Parser_IfStatement_Error_MissingLParen) {
    ASSERT_TRUE(expect_parser_abort("if 1) {}"));
    return true;
}

TEST_FUNC(Parser_IfStatement_Error_MissingRParen) {
    ASSERT_TRUE(expect_parser_abort("if (1 {}"));
    return true;
}

TEST_FUNC(Parser_IfStatement_Error_MissingThenBlock) {
    ASSERT_TRUE(expect_parser_abort("if (1)"));
    return true;
}

TEST_FUNC(Parser_IfStatement_Error_MissingElseBlock) {
    ASSERT_TRUE(expect_parser_abort("if (1) {} else"));
    return true;
}
