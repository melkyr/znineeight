#include "test_framework.hpp"
#include "lexer.hpp"
#include "parser.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include <cstring> // For strcmp

#include "symbol_table.hpp"

// Helper function to set up a parser for a given source string
static Parser create_parser_for_test(const char* source, ArenaAllocator& arena, StringInterner& interner) {
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);
    SymbolTable table(arena);

    DynamicArray<Token> tokens(arena);
    Token token;
    do {
        token = lexer.nextToken();
        tokens.append(token);
    } while (token.type != TOKEN_EOF);

    return Parser(tokens.getData(), tokens.length(), &arena, &table);
}

TEST_FUNC(Parser_ArraySlice_FullRange) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("my_slice[0..4]", arena, interner);

    ASTNode* node = parser.parseExpression();

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
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("my_slice[..4]", arena, interner);

    ASTNode* node = parser.parseExpression();

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
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("my_slice[0..]", arena, interner);

    ASTNode* node = parser.parseExpression();

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
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("my_slice[..]", arena, interner);

    ASTNode* node = parser.parseExpression();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ARRAY_SLICE);
    ASTArraySliceNode* slice = node->as.array_slice;

    ASSERT_EQ(slice->array->type, NODE_IDENTIFIER);
    ASSERT_STREQ(slice->array->as.identifier.name, "my_slice");

    ASSERT_TRUE(slice->start == NULL);
    ASSERT_TRUE(slice->end == NULL);

    return true;
}
