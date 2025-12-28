#include "ast.hpp"
#include "test_framework.hpp"

TEST_FUNC(ASTNode_Comptime) {
    ArenaAllocator arena(4096);
    ASTNode* node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    node->type = NODE_COMPTIME_BLOCK;

    ASTComptimeBlockNode comptime_node;
    comptime_node.expression = NULL;

    node->as.comptime_block = comptime_node;

    ASSERT_EQ(node->type, NODE_COMPTIME_BLOCK);
    ASSERT_TRUE(node->as.comptime_block.expression == NULL);

    return true;
}
