#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "ast.hpp"
#include "type_system.hpp" // For get_g_type_bool()

TEST_FUNC(TypeChecker_Bool_Literals) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    // Create a dummy CompilationUnit for the TypeChecker
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    // Test 'true' literal
    ASTBoolLiteralNode true_node;
    true_node.value = true;
    Type* true_type = checker.visitBoolLiteral(&true_node);
    ASSERT_TRUE(true_type != NULL);
    ASSERT_EQ(true_type->kind, TYPE_BOOL);

    // Test 'false' literal
    ASTBoolLiteralNode false_node;
    false_node.value = false;
    Type* false_type = checker.visitBoolLiteral(&false_node);
    ASSERT_TRUE(false_type != NULL);
    ASSERT_EQ(false_type->kind, TYPE_BOOL);

    // Verify the size and alignment of the global bool type
    Type* global_bool_type = get_g_type_bool();
    ASSERT_EQ(global_bool_type->size, 4);
    ASSERT_EQ(global_bool_type->alignment, 4);

    return true;
}

TEST_FUNC(TypeChecker_Bool_ComparisonOps) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    // Create mock integer literal nodes for the operands
    ASTNode left_operand;
    left_operand.type = NODE_INTEGER_LITERAL;
    left_operand.resolved_type = get_g_type_i32();

    ASTNode right_operand;
    right_operand.type = NODE_INTEGER_LITERAL;
    right_operand.resolved_type = get_g_type_i32();

    TokenType comparison_ops[] = {
        TOKEN_EQUAL_EQUAL, TOKEN_BANG_EQUAL, TOKEN_LESS,
        TOKEN_GREATER, TOKEN_LESS_EQUAL, TOKEN_GREATER_EQUAL
    };
    size_t num_ops = sizeof(comparison_ops) / sizeof(comparison_ops[0]);

    for (size_t i = 0; i < num_ops; ++i) {
        ASTBinaryOpNode op_node_data;
        op_node_data.left = &left_operand;
        op_node_data.right = &right_operand;
        op_node_data.op = comparison_ops[i];

        ASTNode root_node;
        root_node.type = NODE_BINARY_OP;
        root_node.as.binary_op = &op_node_data;

        Type* result_type = checker.visit(&root_node);
        ASSERT_TRUE(result_type != NULL);
        ASSERT_EQ(result_type->kind, TYPE_BOOL);
    }

    return true;
}

TEST_FUNC(TypeChecker_Bool_LogicalOps) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    // Create a mock boolean literal node for the operand
    ASTNode operand;
    operand.type = NODE_BOOL_LITERAL;
    operand.resolved_type = get_g_type_bool();

    // Test the logical NOT operator
    ASTUnaryOpNode not_op_node_data;
    not_op_node_data.operand = &operand;
    not_op_node_data.op = TOKEN_BANG;

    ASTNode root_node;
    root_node.type = NODE_UNARY_OP;
    root_node.as.unary_op = not_op_node_data;

    Type* result_type = checker.visit(&root_node);
    ASSERT_TRUE(result_type != NULL);
    ASSERT_EQ(result_type->kind, TYPE_BOOL);

    return true;
}
