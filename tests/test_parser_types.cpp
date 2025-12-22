#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"

TEST_FUNC(Parser_ParsePrimitiveType) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("i32", arena, interner);
    Parser parser = ctx.getParser();

    ASTNode* type_node = parser.parseType();

    ASSERT_TRUE(type_node != NULL);
    ASSERT_EQ(type_node->type, NODE_TYPE_NAME);
    ASSERT_STREQ(type_node->as.type_name.name, "i32");

    return true;
}

TEST_FUNC(Parser_ParsePointerType) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("*u8", arena, interner);
    Parser parser = ctx.getParser();

    ASTNode* type_node = parser.parseType();

    ASSERT_TRUE(type_node != NULL);
    ASSERT_EQ(type_node->type, NODE_POINTER_TYPE);

    ASTNode* base_node = type_node->as.pointer_type.base;
    ASSERT_TRUE(base_node != NULL);
    ASSERT_EQ(base_node->type, NODE_TYPE_NAME);
    ASSERT_STREQ(base_node->as.type_name.name, "u8");

    return true;
}

TEST_FUNC(Parser_ParseSliceType) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("[]bool", arena, interner);
    Parser parser = ctx.getParser();

    ASTNode* type_node = parser.parseType();

    ASSERT_TRUE(type_node != NULL);
    ASSERT_EQ(type_node->type, NODE_ARRAY_TYPE);
    ASSERT_TRUE(type_node->as.array_type.size == NULL); // Should be a slice

    ASTNode* elem_node = type_node->as.array_type.element_type;
    ASSERT_TRUE(elem_node != NULL);
    ASSERT_EQ(elem_node->type, NODE_TYPE_NAME);
    ASSERT_STREQ(elem_node->as.type_name.name, "bool");

    return true;
}

TEST_FUNC(Parser_ParseNestedPointerType) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("**i32", arena, interner);
    Parser parser = ctx.getParser();

    ASTNode* type_node = parser.parseType();

    ASSERT_TRUE(type_node != NULL);
    ASSERT_EQ(type_node->type, NODE_POINTER_TYPE);

    ASTNode* base1 = type_node->as.pointer_type.base;
    ASSERT_TRUE(base1 != NULL);
    ASSERT_EQ(base1->type, NODE_POINTER_TYPE);

    ASTNode* base2 = base1->as.pointer_type.base;
    ASSERT_TRUE(base2 != NULL);
    ASSERT_EQ(base2->type, NODE_TYPE_NAME);
    ASSERT_STREQ(base2->as.type_name.name, "i32");

    return true;
}

TEST_FUNC(Parser_ParseSliceOfPointers) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("[]*i32", arena, interner);
    Parser parser = ctx.getParser();

    ASTNode* type_node = parser.parseType();

    ASSERT_TRUE(type_node != NULL);
    ASSERT_EQ(type_node->type, NODE_ARRAY_TYPE);
    ASSERT_TRUE(type_node->as.array_type.size == NULL);

    ASTNode* elem_node = type_node->as.array_type.element_type;
    ASSERT_TRUE(elem_node != NULL);
    ASSERT_EQ(elem_node->type, NODE_POINTER_TYPE);

    ASTNode* base_node = elem_node->as.pointer_type.base;
    ASSERT_TRUE(base_node != NULL);
    ASSERT_EQ(base_node->type, NODE_TYPE_NAME);
    ASSERT_STREQ(base_node->as.type_name.name, "i32");

    return true;
}

TEST_FUNC(Parser_ParseFixedSizeArray) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("[8]u8", arena, interner);
    Parser parser = ctx.getParser();

    ASTNode* type_node = parser.parseType();

    ASSERT_TRUE(type_node != NULL);
    ASSERT_EQ(type_node->type, NODE_ARRAY_TYPE);

    ASTNode* size_node = type_node->as.array_type.size;
    ASSERT_TRUE(size_node != NULL);
    ASSERT_EQ(size_node->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(size_node->as.integer_literal.value, 8);

    ASTNode* elem_node = type_node->as.array_type.element_type;
    ASSERT_TRUE(elem_node != NULL);
    ASSERT_EQ(elem_node->type, NODE_TYPE_NAME);
    ASSERT_STREQ(elem_node->as.type_name.name, "u8");

    return true;
}
