#include "test_framework.hpp"
#include "ast.hpp"
#include "memory.hpp"

// Test to verify the structure of a For Statement AST node.
TEST_FUNC(ASTNode_ForStmt)
{
    ArenaAllocator arena(16384);
    ASTNode* node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    ASTNode* iterable = (ASTNode*)arena.alloc(sizeof(ASTNode));
    ASTNode* body = (ASTNode*)arena.alloc(sizeof(ASTNode));

    iterable->type = NODE_IDENTIFIER;
    iterable->as.identifier.name = "my_array";

    body->type = NODE_BLOCK_STMT;
    body->as.block_stmt.statements = NULL;

    node->type = NODE_FOR_STMT;
    node->loc.line = 1;
    node->as.for_stmt = (ASTForStmtNode*)arena.alloc(sizeof(ASTForStmtNode));
    node->as.for_stmt->iterable_expr = iterable;
    node->as.for_stmt->item_name = "item";
    node->as.for_stmt->index_name = "i";
    node->as.for_stmt->body = body;

    ASSERT_EQ(node->type, NODE_FOR_STMT);
    ASSERT_TRUE(node->as.for_stmt->iterable_expr != NULL);
    ASSERT_STREQ(node->as.for_stmt->item_name, "item");
    ASSERT_STREQ(node->as.for_stmt->index_name, "i");
    ASSERT_TRUE(node->as.for_stmt->body != NULL);

    return true;
}

// Test to verify the structure of a Switch Expression AST node.
TEST_FUNC(ASTNode_SwitchExpr)
{
    ArenaAllocator arena(16384);
    ASTNode* node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    ASTNode* switch_expr = (ASTNode*)arena.alloc(sizeof(ASTNode));

    switch_expr->type = NODE_IDENTIFIER;
    switch_expr->as.identifier.name = "my_var";

    node->type = NODE_SWITCH_EXPR;
    node->loc.line = 2;
    node->as.switch_expr = (ASTSwitchExprNode*)arena.alloc(sizeof(ASTSwitchExprNode));
    node->as.switch_expr->expression = switch_expr;
    node->as.switch_expr->prongs = NULL;

    ASSERT_EQ(node->type, NODE_SWITCH_EXPR);
    ASSERT_TRUE(node->as.switch_expr->expression != NULL);
    ASSERT_TRUE(node->as.switch_expr->prongs == NULL);

    return true;
}
