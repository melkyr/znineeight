#include "test_framework.hpp"
#include "ast.hpp"
#include "memory.hpp"

TEST_FUNC(ASTNode_ContainerDeclarations)
{
    ArenaAllocator arena(8192);

    // Test Struct Declaration Node
    ASTStructDeclNode struct_node;
    struct_node.fields = NULL;
    ASSERT_TRUE(struct_node.fields == NULL);

    // Test Union Declaration Node
    ASTUnionDeclNode union_node;
    union_node.fields = NULL;
    ASSERT_TRUE(union_node.fields == NULL);

    // Test Enum Declaration Node
    ASTEnumDeclNode enum_node;
    enum_node.fields = NULL;
    ASSERT_TRUE(enum_node.fields == NULL);

    return true;
}
