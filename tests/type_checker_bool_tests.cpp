#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "ast.hpp"

TEST_FUNC(TypeChecker_Bool_Literals) {
    ArenaAllocator arena(4096);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    TypeChecker checker(comp_unit);

    // Test 'true' literal
    ASTBoolLiteralNode true_node;
    true_node.value = true;
    Type* true_type = checker.visitBoolLiteral(NULL, &true_node);
    ASSERT_TRUE(true_type != NULL);
    ASSERT_EQ(true_type->kind, TYPE_BOOL);

    // Test 'false' literal
    ASTBoolLiteralNode false_node;
    false_node.value = false;
    Type* false_type = checker.visitBoolLiteral(NULL, &false_node);
    ASSERT_TRUE(false_type != NULL);
    ASSERT_EQ(false_type->kind, TYPE_BOOL);

    return true;
}

TEST_FUNC(TypeChecker_Bool_ComparisonOps) {
    // This test is placeholder, actual implementation will be in binary op tests
    return true;
}

TEST_FUNC(TypeChecker_Bool_LogicalOps) {
    // This test is placeholder, actual implementation will be in binary op tests
    return true;
}
