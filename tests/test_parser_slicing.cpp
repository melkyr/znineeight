#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"

#include <new>

// Helper function to set up the parser for a given source string
static Parser create_parser_for_test(const char* source, ArenaAllocator& arena, StringInterner& interner, SourceManager& sm, DynamicArray<Token>& tokens) {
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);

    while (true) {
        Token token = lexer.nextToken();
        tokens.append(token);
        if (token.type == TOKEN_EOF) {
            break;
        }
    }

    return Parser(tokens.getData(), tokens.length(), &arena);
}

TEST_FUNC(Parser_ArraySlice_BothBounds) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    DynamicArray<Token> tokens(arena);

    const char* source = "my_slice[0..4]";
    Parser parser = create_parser_for_test(source, arena, interner, sm, tokens);

    ASTNode* node = parser.parseExpression();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ARRAY_SLICE);

    ASTArraySliceNode* slice = node->as.array_slice;
    ASSERT_TRUE(slice != NULL);
    ASSERT_TRUE(slice->array != NULL);
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

TEST_FUNC(Parser_ArraySlice_ImplicitStart) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    DynamicArray<Token> tokens(arena);

    const char* source = "my_slice[..4]";
    Parser parser = create_parser_for_test(source, arena, interner, sm, tokens);

    ASTNode* node = parser.parseExpression();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ARRAY_SLICE);

    ASTArraySliceNode* slice = node->as.array_slice;
    ASSERT_TRUE(slice != NULL);
    ASSERT_TRUE(slice->array != NULL);
    ASSERT_EQ(slice->array->type, NODE_IDENTIFIER);
    ASSERT_STREQ(slice->array->as.identifier.name, "my_slice");

    ASSERT_TRUE(slice->start == NULL);

    ASSERT_TRUE(slice->end != NULL);
    ASSERT_EQ(slice->end->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(slice->end->as.integer_literal.value, 4);

    return true;
}

TEST_FUNC(Parser_ArraySlice_ImplicitEnd) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    DynamicArray<Token> tokens(arena);

    const char* source = "my_slice[0..]";
    Parser parser = create_parser_for_test(source, arena, interner, sm, tokens);

    ASTNode* node = parser.parseExpression();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ARRAY_SLICE);

    ASTArraySliceNode* slice = node->as.array_slice;
    ASSERT_TRUE(slice != NULL);
    ASSERT_TRUE(slice->array != NULL);
    ASSERT_EQ(slice->array->type, NODE_IDENTIFIER);
    ASSERT_STREQ(slice->array->as.identifier.name, "my_slice");

    ASSERT_TRUE(slice->start != NULL);
    ASSERT_EQ(slice->start->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(slice->start->as.integer_literal.value, 0);

    ASSERT_TRUE(slice->end == NULL);

    return true;
}

TEST_FUNC(Parser_ArraySlice_FullSlice) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    DynamicArray<Token> tokens(arena);

    const char* source = "my_slice[..]";
    Parser parser = create_parser_for_test(source, arena, interner, sm, tokens);

    ASTNode* node = parser.parseExpression();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ARRAY_SLICE);

    ASTArraySliceNode* slice = node->as.array_slice;
    ASSERT_TRUE(slice != NULL);
    ASSERT_TRUE(slice->array != NULL);
    ASSERT_EQ(slice->array->type, NODE_IDENTIFIER);
    ASSERT_STREQ(slice->array->as.identifier.name, "my_slice");

    ASSERT_TRUE(slice->start == NULL);
    ASSERT_TRUE(slice->end == NULL);

    return true;
}

TEST_FUNC(Parser_ArrayAccess_Standard) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    DynamicArray<Token> tokens(arena);

    const char* source = "my_array[5]";
    Parser parser = create_parser_for_test(source, arena, interner, sm, tokens);

    ASTNode* node = parser.parseExpression();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ARRAY_ACCESS);

    ASTArrayAccessNode* access = node->as.array_access;
    ASSERT_TRUE(access != NULL);
    ASSERT_TRUE(access->array != NULL);
    ASSERT_EQ(access->array->type, NODE_IDENTIFIER);
    ASSERT_STREQ(access->array->as.identifier.name, "my_array");

    ASSERT_TRUE(access->index != NULL);
    ASSERT_EQ(access->index->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(access->index->as.integer_literal.value, 5);

    return true;
}
