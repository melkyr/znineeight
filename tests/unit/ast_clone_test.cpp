#include "test_framework.hpp"
#include "ast_utils.hpp"
#include "memory.hpp"
#include "platform.hpp"
#include <cstdio>
#include <new>

#ifndef UNIT_TEST_HELPERS
#define UNIT_TEST_HELPERS
// Helper to create a dummy integer literal node
static ASTNode* create_int_lit(ArenaAllocator* arena, i64 value) {
    ASTNode* node = (ASTNode*)arena->alloc(sizeof(ASTNode));
    plat_memset(node, 0, sizeof(ASTNode));
    node->type = NODE_INTEGER_LITERAL;
    node->as.integer_literal.value = (u64)value;
    return node;
}
#endif

TEST_FUNC(clone_basic) {
    ArenaAllocator arena(4096);
    ASTNode* original = create_int_lit(&arena, 42);

    ASTNode* cloned = cloneASTNode(original, &arena);

    ASSERT_TRUE(cloned != NULL);
    ASSERT_TRUE(cloned != original);
    ASSERT_EQ(original->type, cloned->type);
    ASSERT_EQ(original->as.integer_literal.value, cloned->as.integer_literal.value);

    return true;
}

TEST_FUNC(clone_range) {
    ArenaAllocator arena(4096);
    ASTNode* start = create_int_lit(&arena, 1);
    ASTNode* end = create_int_lit(&arena, 10);

    ASTNode* range_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(range_node, 0, sizeof(ASTNode));
    range_node->type = NODE_RANGE;
    range_node->as.range = (ASTRangeNode*)arena.alloc(sizeof(ASTRangeNode));
    range_node->as.range->start = start;
    range_node->as.range->end = end;
    range_node->as.range->is_inclusive = true;

    ASTNode* cloned = cloneASTNode(range_node, &arena);

    ASSERT_TRUE(cloned != NULL);
    ASSERT_TRUE(cloned != range_node);
    ASSERT_EQ(NODE_RANGE, cloned->type);
    ASSERT_TRUE(cloned->as.range != range_node->as.range);
    ASSERT_TRUE(cloned->as.range->start != start);
    ASSERT_TRUE(cloned->as.range->end != end);
    ASSERT_EQ(NODE_INTEGER_LITERAL, cloned->as.range->start->type);
    ASSERT_EQ(1, cloned->as.range->start->as.integer_literal.value);
    ASSERT_EQ(10, cloned->as.range->end->as.integer_literal.value);
    ASSERT_TRUE(cloned->as.range->is_inclusive);

    return true;
}

TEST_FUNC(clone_switch_stmt) {
    ArenaAllocator arena(8192);
    ASTNode* cond = create_int_lit(&arena, 5);

    ASTNode* sw_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(sw_node, 0, sizeof(ASTNode));
    sw_node->type = NODE_SWITCH_STMT;
    sw_node->as.switch_stmt = (ASTSwitchStmtNode*)arena.alloc(sizeof(ASTSwitchStmtNode));
    plat_memset(sw_node->as.switch_stmt, 0, sizeof(ASTSwitchStmtNode));
    sw_node->as.switch_stmt->expression = cond;

    void* prongs_mem = arena.alloc(sizeof(DynamicArray<ASTSwitchStmtProngNode*>));
    sw_node->as.switch_stmt->prongs = new (prongs_mem) DynamicArray<ASTSwitchStmtProngNode*>(arena);

    ASTSwitchStmtProngNode* prong = (ASTSwitchStmtProngNode*)arena.alloc(sizeof(ASTSwitchStmtProngNode));
    plat_memset(prong, 0, sizeof(ASTSwitchStmtProngNode));
    void* items_mem = arena.alloc(sizeof(DynamicArray<ASTNode*>));
    prong->items = new (items_mem) DynamicArray<ASTNode*>(arena);
    prong->items->append(create_int_lit(&arena, 5));
    prong->body = create_int_lit(&arena, 42); // Simple expression as body for testing

    sw_node->as.switch_stmt->prongs->append(prong);

    ASTNode* cloned = cloneASTNode(sw_node, &arena);

    ASSERT_TRUE(cloned != NULL);
    ASSERT_TRUE(cloned != sw_node);
    ASSERT_EQ(NODE_SWITCH_STMT, cloned->type);
    ASSERT_TRUE(cloned->as.switch_stmt != sw_node->as.switch_stmt);
    ASSERT_TRUE(cloned->as.switch_stmt->expression != cond);
    ASSERT_TRUE(cloned->as.switch_stmt->prongs != sw_node->as.switch_stmt->prongs);
    ASSERT_EQ(1, cloned->as.switch_stmt->prongs->length());

    ASTSwitchStmtProngNode* cloned_prong = (*cloned->as.switch_stmt->prongs)[0];
    ASSERT_TRUE(cloned_prong != prong);
    ASSERT_EQ(1, cloned_prong->items->length());
    ASSERT_EQ(5, (*cloned_prong->items)[0]->as.integer_literal.value);
    ASSERT_EQ(42, cloned_prong->body->as.integer_literal.value);

    return true;
}

TEST_FUNC(clone_binary_op) {
    ArenaAllocator arena(4096);
    ASTNode* left = create_int_lit(&arena, 10);
    ASTNode* right = create_int_lit(&arena, 20);

    ASTNode* bin_op = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(bin_op, 0, sizeof(ASTNode));
    bin_op->type = NODE_BINARY_OP;
    bin_op->as.binary_op = (ASTBinaryOpNode*)arena.alloc(sizeof(ASTBinaryOpNode));
    bin_op->as.binary_op->left = left;
    bin_op->as.binary_op->right = right;
    bin_op->as.binary_op->op = TOKEN_PLUS;

    ASTNode* cloned = cloneASTNode(bin_op, &arena);

    ASSERT_TRUE(cloned != NULL);
    ASSERT_TRUE(cloned != bin_op);
    ASSERT_EQ(NODE_BINARY_OP, cloned->type);
    ASSERT_TRUE(cloned->as.binary_op != bin_op->as.binary_op);
    ASSERT_TRUE(cloned->as.binary_op->left != left);
    ASSERT_TRUE(cloned->as.binary_op->right != right);
    ASSERT_EQ(NODE_INTEGER_LITERAL, cloned->as.binary_op->left->type);
    ASSERT_EQ(10, cloned->as.binary_op->left->as.integer_literal.value);
    ASSERT_EQ(20, cloned->as.binary_op->right->as.integer_literal.value);

    return true;
}

#ifndef RETROZIG_TEST
int main() {
    int passed = 0;
    int total = 0;

    total++; if (test_clone_basic()) passed++;
    total++; if (test_clone_binary_op()) passed++;
    total++; if (test_clone_range()) passed++;
    total++; if (test_clone_switch_stmt()) passed++;

    printf("AST Clone Tests: %d/%d passed\n", passed, total);
    return (passed == total) ? 0 : 1;
}
#endif
