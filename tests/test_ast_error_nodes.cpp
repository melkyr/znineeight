#include "test_framework.hpp"
#include "ast.hpp"

// This test primarily serves as a compile-time check to ensure that the AST node
// structures for error handling are defined correctly and can be instantiated.

TEST_FUNC(ASTNode_ErrorHandlingNodes) {
    // Dummy pointers and values for testing struct members
    ASTNode dummy_node;
    dummy_node.type = NODE_IDENTIFIER;

    // Test ASTTryExprNode
    ASTTryExprNode try_node;
    try_node.expression = &dummy_node;
    ASSERT_TRUE(try_node.expression != NULL);

    // Test ASTCatchExprNode
    ASTCatchExprNode catch_node;
    catch_node.payload = &dummy_node;
    catch_node.error_name = "e";
    catch_node.else_expr = &dummy_node;
    ASSERT_TRUE(catch_node.payload != NULL);
    ASSERT_TRUE(catch_node.error_name != NULL);
    ASSERT_TRUE(catch_node.else_expr != NULL);

    // Test ASTErrDeferStmtNode
    ASTErrDeferStmtNode errdefer_node;
    errdefer_node.statement = &dummy_node;
    ASSERT_TRUE(errdefer_node.statement != NULL);

    // Test their inclusion in the main ASTNode union
    ASTNode main_node;
    main_node.type = NODE_TRY_EXPR;
    main_node.as.try_expr = try_node;
    ASSERT_TRUE(main_node.as.try_expr.expression != NULL);

    main_node.type = NODE_CATCH_EXPR;
    main_node.as.catch_expr = &catch_node;
    ASSERT_TRUE(main_node.as.catch_expr->payload != NULL);

    main_node.type = NODE_ERRDEFER_STMT;
    main_node.as.errdefer_stmt = errdefer_node;
    ASSERT_TRUE(main_node.as.errdefer_stmt.statement != NULL);

    return true;
}
