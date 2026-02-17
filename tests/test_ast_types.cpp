#include "test_framework.hpp"
#include "ast.hpp"
#include "memory.hpp"

TEST_FUNC(ASTNode_TypeName) {
    ArenaAllocator arena(1024 * 1024);
    ASTNode* node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    node->type = NODE_TYPE_NAME;

    ASTTypeNameNode* typeName = &node->as.type_name;
    typeName->name = "i32";

    ASSERT_EQ(node->type, NODE_TYPE_NAME);
    ASSERT_STREQ(typeName->name, "i32");

    return true;
}

TEST_FUNC(ASTNode_PointerType) {
    ArenaAllocator arena(1024 * 1024);

    // Base type
    ASTNode* base_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    base_node->type = NODE_TYPE_NAME;
    base_node->as.type_name.name = "u8";

    // Pointer type
    ASTNode* ptr_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    ptr_node->type = NODE_POINTER_TYPE;

    ASTPointerTypeNode* ptrType = &ptr_node->as.pointer_type;
    ptrType->base = base_node;

    ASSERT_EQ(ptr_node->type, NODE_POINTER_TYPE);
    ASSERT_EQ(ptrType->base->type, NODE_TYPE_NAME);
    ASSERT_STREQ(ptrType->base->as.type_name.name, "u8");

    return true;
}

TEST_FUNC(ASTNode_ArrayType) {
    ArenaAllocator arena(1024 * 1024);

    // Element type
    ASTNode* element_type_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    element_type_node->type = NODE_TYPE_NAME;
    element_type_node->as.type_name.name = "bool";

    // Size expression (integer literal)
    ASTNode* size_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    size_node->type = NODE_INTEGER_LITERAL;
    size_node->as.integer_literal.value = 8;

    // Array type node
    ASTNode* array_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    array_node->type = NODE_ARRAY_TYPE;

    ASTArrayTypeNode* arrayType = &array_node->as.array_type;
    arrayType->element_type = element_type_node;
    arrayType->size = size_node;

    ASSERT_EQ(array_node->type, NODE_ARRAY_TYPE);
    ASSERT_EQ(arrayType->element_type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(arrayType->element_type->as.type_name.name, "bool");
    ASSERT_EQ(arrayType->size->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(arrayType->size->as.integer_literal.value, 8);

    return true;
}

TEST_FUNC(ASTNode_SliceType) {
    ArenaAllocator arena(1024 * 1024);

    // Element type
    ASTNode* element_type_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    element_type_node->type = NODE_TYPE_NAME;
    element_type_node->as.type_name.name = "f32";

    // Slice type node (size is NULL)
    ASTNode* slice_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    slice_node->type = NODE_ARRAY_TYPE;

    ASTArrayTypeNode* sliceType = &slice_node->as.array_type;
    sliceType->element_type = element_type_node;
    sliceType->size = NULL;

    ASSERT_EQ(slice_node->type, NODE_ARRAY_TYPE);
    ASSERT_EQ(sliceType->element_type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(sliceType->element_type->as.type_name.name, "f32");
    ASSERT_TRUE(sliceType->size == NULL);

    return true;
}
