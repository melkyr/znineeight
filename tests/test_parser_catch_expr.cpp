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
    // This expression should parse as `a catch (b orelse c)`
    // because `catch` and `orelse` have the same precedence and are right-associative.
    ParserTestContext ctx("a catch b orelse c", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* root = parser->parseExpression();

    // Expected structure for right-associativity: (a catch (b orelse c))
    //                catch
    //               /     \
    //              a      orelse
    //                    /      \
    //                   b        c

    ASSERT_EQ(root->type, NODE_CATCH_EXPR);
    ASTCatchExprNode* catch_node = root->as.catch_expr;

    // Left side should be identifier 'a'
    ASSERT_EQ(catch_node->payload->type, NODE_IDENTIFIER);
    ASSERT_STREQ(catch_node->payload->as.identifier.name, "a");

    // Right side should be the 'orelse' expression
    ASTNode* right = catch_node->else_expr;
    ASSERT_TRUE(right != NULL);
    ASSERT_EQ(right->type, NODE_ORELSE_EXPR);
    ASTOrelseExprNode* orelse_node = right->as.orelse_expr;

    ASSERT_EQ(orelse_node->payload->type, NODE_IDENTIFIER);
    ASSERT_STREQ(orelse_node->payload->as.identifier.name, "b");

    ASSERT_EQ(orelse_node->else_expr->type, NODE_IDENTIFIER);
    ASSERT_STREQ(orelse_node->else_expr->as.identifier.name, "c");

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
