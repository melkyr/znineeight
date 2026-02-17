#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"

TEST_FUNC(Parser_ParseEmptyBlock) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("{}", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 0);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithIfStatement) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("{if (1) {}}", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 1);

    ASTNode* if_stmt = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(if_stmt->type, NODE_IF_STMT);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithWhileStatement) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("{while (1) {}}", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 1);

    ASTNode* while_stmt = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(while_stmt->type, NODE_WHILE_STMT);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithMixedStatements) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("{if (1) {} while (1) {}}", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 2);

    ASTNode* if_stmt = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(if_stmt->type, NODE_IF_STMT);

    ASTNode* while_stmt = (*node->as.block_stmt.statements)[1];
    ASSERT_EQ(while_stmt->type, NODE_WHILE_STMT);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithEmptyStatement) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("{;}", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 1);

    ASTNode* stmt = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(stmt->type, NODE_EMPTY_STMT);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithMultipleEmptyStatements) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("{;;}", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 2);

    ASTNode* stmt1 = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(stmt1->type, NODE_EMPTY_STMT);

    ASTNode* stmt2 = (*node->as.block_stmt.statements)[1];
    ASSERT_EQ(stmt2->type, NODE_EMPTY_STMT);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithNestedEmptyBlock) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("{{}}", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 1);

    ASTNode* nested_block = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(nested_block->type, NODE_BLOCK_STMT);
    ASSERT_EQ(nested_block->as.block_stmt.statements->length(), 0);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithMultipleNestedEmptyBlocks) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("{{}{}}", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 2);

    ASTNode* nested_block1 = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(nested_block1->type, NODE_BLOCK_STMT);
    ASSERT_EQ(nested_block1->as.block_stmt.statements->length(), 0);

    ASTNode* nested_block2 = (*node->as.block_stmt.statements)[1];
    ASSERT_EQ(nested_block2->type, NODE_BLOCK_STMT);
    ASSERT_EQ(nested_block2->as.block_stmt.statements->length(), 0);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithNestedBlockAndEmptyStatement) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("{{};}", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 2);

    ASTNode* nested_block = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(nested_block->type, NODE_BLOCK_STMT);
    ASSERT_EQ(nested_block->as.block_stmt.statements->length(), 0);

    ASTNode* empty_stmt = (*node->as.block_stmt.statements)[1];
    ASSERT_EQ(empty_stmt->type, NODE_EMPTY_STMT);

    return true;
}
