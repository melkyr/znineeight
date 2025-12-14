#include "ast.hpp"
#include "test_framework.hpp"

TEST_FUNC(ASTNode_Async) {
    // This is a compile-time test to ensure the new AST node structures
    // for async operations are correctly defined and can be instantiated.

    // Test ASTAsyncExprNode
    ASTAsyncExprNode async_node;
    async_node.expression = NULL; // Dummy assignment

    // Test ASTAwaitExprNode
    ASTAwaitExprNode await_node;
    await_node.expression = NULL; // Dummy assignment

    // Create a top-level ASTNode to hold the async node
    ASTNode node1;
    node1.type = NODE_ASYNC_EXPR;
    node1.as.async_expr = async_node;

    // Create a top-level ASTNode to hold the await node
    ASTNode node2;
    node2.type = NODE_AWAIT_EXPR;
    node2.as.await_expr = await_node;

    // Basic assertions to ensure the test runner has something to check
    ASSERT_TRUE(node1.type == NODE_ASYNC_EXPR);
    ASSERT_TRUE(node2.type == NODE_AWAIT_EXPR);
    ASSERT_TRUE(node1.as.async_expr.expression == NULL);
    ASSERT_TRUE(node2.as.await_expr.expression == NULL);

    return true;
}
