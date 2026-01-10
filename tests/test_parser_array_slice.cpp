#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include <cstring> // For strcmp

TEST_FUNC(Parser_ArraySlice_FullRange) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("my_slice[0..4]", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseExpression();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ARRAY_SLICE);
    ASTArraySliceNode* slice = node->as.array_slice;

    ASSERT_EQ(slice->array->type, NODE_IDENTIFIER);
    ASSERT_STREQ(slice->array->as.identifier.name, "my_slice");

    ASSERT_TRUE(slice->start != NULL);
    ASSERT_EQ(slice->start->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(slice->start->as.integer_literal.value, 0);

    ASSERT_TRUE(slice->end != NULL);
    ASSERT_EQ(slice->end->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(slice->end->as.integer_literal.value, 4);

    return true;
}

TEST_FUNC(Parser_ArraySlice_EndRangeOnly) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("my_slice[..4]", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseExpression();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ARRAY_SLICE);
    ASTArraySliceNode* slice = node->as.array_slice;

    ASSERT_EQ(slice->array->type, NODE_IDENTIFIER);
    ASSERT_STREQ(slice->array->as.identifier.name, "my_slice");

    ASSERT_TRUE(slice->start == NULL);

    ASSERT_TRUE(slice->end != NULL);
    ASSERT_EQ(slice->end->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(slice->end->as.integer_literal.value, 4);

    return true;
}

TEST_FUNC(Parser_ArraySlice_StartRangeOnly) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("my_slice[0..]", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseExpression();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ARRAY_SLICE);
    ASTArraySliceNode* slice = node->as.array_slice;

    ASSERT_EQ(slice->array->type, NODE_IDENTIFIER);
    ASSERT_STREQ(slice->array->as.identifier.name, "my_slice");

    ASSERT_TRUE(slice->start != NULL);
    ASSERT_EQ(slice->start->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(slice->start->as.integer_literal.value, 0);

    ASSERT_TRUE(slice->end == NULL);

    return true;
}

TEST_FUNC(Parser_ArraySlice_NoRange) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("my_slice[..]", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseExpression();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ARRAY_SLICE);
    ASTArraySliceNode* slice = node->as.array_slice;

    ASSERT_EQ(slice->array->type, NODE_IDENTIFIER);
    ASSERT_STREQ(slice->array->as.identifier.name, "my_slice");

    ASSERT_TRUE(slice->start == NULL);
    ASSERT_TRUE(slice->end == NULL);

    return true;
}
