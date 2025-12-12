#include "test_framework.hpp"
#include "ast.hpp"
#include "memory.hpp"
#include <new> // For placement new

TEST_FUNC(AST_Statements)
{
    // This test is primarily a compile-time check to ensure the AST statement
    // node definitions are correct and can be instantiated.

    ArenaAllocator arena(1024);

    // Test ASTIfStmtNode
    ASTNode if_node;
    if_node.type = NODE_IF_STMT;
    if_node.as.if_stmt.condition = NULL;
    if_node.as.if_stmt.then_block = NULL;
    if_node.as.if_stmt.else_block = NULL;
    ASSERT_TRUE(if_node.type == NODE_IF_STMT);

    // Test ASTWhileStmtNode
    ASTNode while_node;
    while_node.type = NODE_WHILE_STMT;
    while_node.as.while_stmt.condition = NULL;
    while_node.as.while_stmt.body = NULL;
    ASSERT_TRUE(while_node.type == NODE_WHILE_STMT);

    // Test ASTReturnStmtNode
    ASTNode return_node;
    return_node.type = NODE_RETURN_STMT;
    return_node.as.return_stmt.expression = NULL;
    ASSERT_TRUE(return_node.type == NODE_RETURN_STMT);

    // Test ASTDeferStmtNode
    ASTNode defer_node;
    defer_node.type = NODE_DEFER_STMT;
    defer_node.as.defer_stmt.statement = NULL;
    ASSERT_TRUE(defer_node.type == NODE_DEFER_STMT);

    // Test ASTBlockStmtNode
    ASTNode block_node;
    block_node.type = NODE_BLOCK_STMT;
    // In a real scenario, the parser would allocate and initialize this.
    DynamicArray<ASTNode*>* statements = (DynamicArray<ASTNode*>*)arena.alloc(sizeof(DynamicArray<ASTNode*>));
    new (statements) DynamicArray<ASTNode*>(arena); // Placement new to call constructor
    block_node.as.block_stmt.statements = statements;
    ASSERT_TRUE(block_node.type == NODE_BLOCK_STMT);

    // Clean up arena
    arena.reset();

    return true;
}
