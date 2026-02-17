#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include <cstdio>
#include <cstring>

TEST_FUNC(Parser_CatchExpression_Simple) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("a catch b", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* root = parser->parseExpression();

    ASSERT_EQ(root->type, NODE_CATCH_EXPR);
    ASTCatchExprNode* catch_node = root->as.catch_expr;

    ASSERT_TRUE(catch_node->payload != NULL);
    ASSERT_EQ(catch_node->payload->type, NODE_IDENTIFIER);
    ASSERT_STREQ(catch_node->payload->as.identifier.name, "a");

    ASSERT_TRUE(catch_node->error_name == NULL);

    ASSERT_TRUE(catch_node->else_expr != NULL);
    ASSERT_EQ(catch_node->else_expr->type, NODE_IDENTIFIER);
    ASSERT_STREQ(catch_node->else_expr->as.identifier.name, "b");

    return true;
}

TEST_FUNC(Parser_CatchExpression_WithPayload) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("a catch |err| b", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* root = parser->parseExpression();

    ASSERT_EQ(root->type, NODE_CATCH_EXPR);
    ASTCatchExprNode* catch_node = root->as.catch_expr;

    ASSERT_TRUE(catch_node->payload != NULL);
    ASSERT_EQ(catch_node->payload->type, NODE_IDENTIFIER);
    ASSERT_STREQ(catch_node->payload->as.identifier.name, "a");

    ASSERT_TRUE(catch_node->error_name != NULL);
    ASSERT_STREQ(catch_node->error_name, "err");

    ASSERT_TRUE(catch_node->else_expr != NULL);
    ASSERT_EQ(catch_node->else_expr->type, NODE_IDENTIFIER);
    ASSERT_STREQ(catch_node->else_expr->as.identifier.name, "b");

    return true;
}

TEST_FUNC(Parser_CatchExpression_MixedAssociativity) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    // This expression should parse as `(a catch b) orelse c`
    // because `catch` and `orelse` have the same precedence and are left-associative.
    ParserTestContext ctx("a catch b orelse c", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* root = parser->parseExpression();

    // Expected structure for left-associativity: ((a catch b) orelse c)
    //                orelse
    //               /      \
    //           catch       c
    //          /     \
    //         a       b

    ASSERT_EQ(root->type, NODE_ORELSE_EXPR);
    ASTOrelseExprNode* orelse_node = root->as.orelse_expr;

    // Right side should be the identifier 'c'
    ASSERT_TRUE(orelse_node->else_expr != NULL);
    ASSERT_EQ(orelse_node->else_expr->type, NODE_IDENTIFIER);
    ASSERT_STREQ(orelse_node->else_expr->as.identifier.name, "c");

    // Left side should be the 'catch' expression
    ASTNode* left = orelse_node->payload;
    ASSERT_TRUE(left != NULL);
    ASSERT_EQ(left->type, NODE_CATCH_EXPR);
    ASTCatchExprNode* catch_node = left->as.catch_expr;

    ASSERT_EQ(catch_node->payload->type, NODE_IDENTIFIER);
    ASSERT_STREQ(catch_node->payload->as.identifier.name, "a");

    ASSERT_EQ(catch_node->else_expr->type, NODE_IDENTIFIER);
    ASSERT_STREQ(catch_node->else_expr->as.identifier.name, "b");

    return true;
}


TEST_FUNC(Parser_CatchExpression_Error_MissingElseExpr) {
    expect_parser_abort("a catch");
    return true;
}

TEST_FUNC(Parser_CatchExpression_Error_IncompletePayload) {
    expect_parser_abort("a catch |err");
    return true;
}

TEST_FUNC(Parser_CatchExpression_Error_MissingPipe) {
    expect_parser_abort("a catch |err| ");
    return true;
}
