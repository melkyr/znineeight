#include "test_framework.hpp"
#include "ast_utils.hpp"
#include "memory.hpp"
#include "platform.hpp"
#include <cstdio>
#include <new>

struct CountingVisitor : ChildVisitor {
    int count;
    CountingVisitor() : count(0) {}
    void visitChild(ASTNode** child_slot) {
        if (*child_slot) {
            count++;
            forEachChild(*child_slot, *this);
        }
    }
};

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

TEST_FUNC(traversal_binary_op) {
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

    CountingVisitor visitor;
    forEachChild(bin_op, visitor);

    ASSERT_EQ(2, visitor.count);

    return true;
}

TEST_FUNC(traversal_range) {
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

    CountingVisitor visitor;
    forEachChild(range_node, visitor);

    ASSERT_EQ(2, visitor.count);

    return true;
}

TEST_FUNC(traversal_switch_stmt) {
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
    prong->body = create_int_lit(&arena, 42);

    sw_node->as.switch_stmt->prongs->append(prong);

    CountingVisitor visitor;
    forEachChild(sw_node, visitor);

    // cond (1) + item (1) + body (1) = 3
    ASSERT_EQ(3, visitor.count);

    return true;
}

TEST_FUNC(traversal_block) {
    ArenaAllocator arena(8192);
    void* array_mem = arena.alloc(sizeof(DynamicArray<ASTNode*>));
    DynamicArray<ASTNode*>* stmts = new (array_mem) DynamicArray<ASTNode*>(arena);

    stmts->append(create_int_lit(&arena, 1));
    stmts->append(create_int_lit(&arena, 2));
    stmts->append(create_int_lit(&arena, 3));

    ASTNode* block = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(block, 0, sizeof(ASTNode));
    block->type = NODE_BLOCK_STMT;
    block->as.block_stmt.statements = stmts;

    CountingVisitor visitor;
    forEachChild(block, visitor);

    ASSERT_EQ(3, visitor.count);

    return true;
}

#ifndef RETROZIG_TEST
int main() {
    int passed = 0;
    int total = 0;

    total++; if (test_traversal_binary_op()) passed++;
    total++; if (test_traversal_block()) passed++;
    total++; if (test_traversal_range()) passed++;
    total++; if (test_traversal_switch_stmt()) passed++;

    printf("AST Traversal Tests: %d/%d passed\n", passed, total);
    return (passed == total) ? 0 : 1;
}
#endif
