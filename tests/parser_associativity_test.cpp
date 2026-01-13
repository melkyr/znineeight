#include "test_framework.hpp"
#include "test_utils.hpp"
#include "parser.hpp"

TEST_FUNC(Parser_OrelseAssociativity) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    const char* source = "a orelse b orelse c";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();

    ASTNode* result = parser->parseExpression();

    ASSERT_TRUE(result != NULL);
    ASSERT_TRUE(result->type == NODE_BINARY_OP);

    ASTBinaryOpNode* root = result->as.binary_op;
    ASSERT_TRUE(root->op == TOKEN_ORELSE);

    // Check left operand
    ASSERT_TRUE(root->left->type == NODE_IDENTIFIER);
    ASSERT_TRUE(strcmp(root->left->as.identifier.name, "a") == 0);

    // Check right operand is a nested binary op
    ASSERT_TRUE(root->right->type == NODE_BINARY_OP);
    ASTBinaryOpNode* right_op = root->right->as.binary_op;
    ASSERT_TRUE(right_op->op == TOKEN_ORELSE);

    // Check left of nested op
    ASSERT_TRUE(right_op->left->type == NODE_IDENTIFIER);
    ASSERT_TRUE(strcmp(right_op->left->as.identifier.name, "b") == 0);

    // Check right of nested op
    ASSERT_TRUE(right_op->right->type == NODE_IDENTIFIER);
    ASSERT_TRUE(strcmp(right_op->right->as.identifier.name, "c") == 0);

    return true;
}

TEST_FUNC(Parser_CatchAssociativity) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    const char* source = "a catch b catch c";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();

    ASTNode* result = parser->parseExpression();

    ASSERT_TRUE(result != NULL);
    ASSERT_TRUE(result->type == NODE_CATCH_EXPR);

    ASTCatchExprNode* root = result->as.catch_expr;

    // Check left operand (payload)
    ASSERT_TRUE(root->payload->type == NODE_IDENTIFIER);
    ASSERT_TRUE(strcmp(root->payload->as.identifier.name, "a") == 0);

    // Check right operand (else_expr) is a nested catch expression
    ASSERT_TRUE(root->else_expr->type == NODE_CATCH_EXPR);
    ASTCatchExprNode* right_op = root->else_expr->as.catch_expr;

    // Check payload of nested op
    ASSERT_TRUE(right_op->payload->type == NODE_IDENTIFIER);
    ASSERT_TRUE(strcmp(right_op->payload->as.identifier.name, "b") == 0);

    // Check else_expr of nested op
    ASSERT_TRUE(right_op->else_expr->type == NODE_IDENTIFIER);
    ASSERT_TRUE(strcmp(right_op->else_expr->as.identifier.name, "c") == 0);

    return true;
}
