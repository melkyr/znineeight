#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include <cstdio>
#include <cstring>

TEST_FUNC(Parser_CatchExpression_Simple) {
    ArenaAllocator arena(4096);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("a catch b", arena, interner);
    Parser parser = ctx.getParser();

    ASTNode* root = parser.parseExpression();

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
    ArenaAllocator arena(4096);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("a catch |err| b", arena, interner);
    Parser parser = ctx.getParser();

    ASTNode* root = parser.parseExpression();

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

TEST_FUNC(Parser_CatchExpression_RightAssociativity) {
    ArenaAllocator arena(4096);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("a catch b orelse c", arena, interner);
    Parser parser = ctx.getParser();

    ASTNode* root = parser.parseExpression();

    ASSERT_EQ(root->type, NODE_CATCH_EXPR);
    ASTCatchExprNode* catch_node = root->as.catch_expr;

    ASSERT_TRUE(catch_node->payload != NULL);
    ASSERT_EQ(catch_node->payload->type, NODE_IDENTIFIER);
    ASSERT_STREQ(catch_node->payload->as.identifier.name, "a");

    // The right-hand side should be the 'orelse' expression
    ASTNode* right = catch_node->else_expr;
    ASSERT_TRUE(right != NULL);
    ASSERT_EQ(right->type, NODE_BINARY_OP);
    ASTBinaryOpNode* orelse_node = right->as.binary_op;

    ASSERT_EQ(orelse_node->op, TOKEN_ORELSE);

    ASSERT_EQ(orelse_node->left->type, NODE_IDENTIFIER);
    ASSERT_STREQ(orelse_node->left->as.identifier.name, "b");

    ASSERT_EQ(orelse_node->right->type, NODE_IDENTIFIER);
    ASSERT_STREQ(orelse_node->right->as.identifier.name, "c");

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
