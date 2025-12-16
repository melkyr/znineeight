#include "test_framework.hpp"
#include "lexer.hpp"
#include "parser.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include <cstring> // For strcmp

// Helper function to set up a parser for a given source string
static Parser create_parser_for_test(const char* source, ArenaAllocator& arena, StringInterner& interner) {
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);

    DynamicArray<Token> tokens(arena);
    Token token;
    do {
        token = lexer.nextToken();
        tokens.append(token);
    } while (token.type != TOKEN_EOF);

    return Parser(tokens.getData(), tokens.length(), &arena);
}

TEST_FUNC(Parser_ParsePrimaryExpr_IntegerLiteral) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("123", arena, interner);

    ASTNode* node = parser.parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(node->as.integer_literal.value, 123);

    return true;
}

TEST_FUNC(Parser_ParsePrimaryExpr_FloatLiteral) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("3.14", arena, interner);

    ASTNode* node = parser.parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_FLOAT_LITERAL);
    ASSERT_EQ(node->as.float_literal.value, 3.14);

    return true;
}

TEST_FUNC(Parser_ParsePrimaryExpr_CharLiteral) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("'a'", arena, interner);

    ASTNode* node = parser.parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_CHAR_LITERAL);
    ASSERT_EQ(node->as.char_literal.value, 'a');

    return true;
}

TEST_FUNC(Parser_ParsePrimaryExpr_StringLiteral) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("\"hello\"", arena, interner);

    ASTNode* node = parser.parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_STRING_LITERAL);
    ASSERT_STREQ(node->as.string_literal.value, "hello");

    return true;
}

TEST_FUNC(Parser_ParsePrimaryExpr_Identifier) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("my_var", arena, interner);

    ASTNode* node = parser.parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_IDENTIFIER);
    ASSERT_STREQ(node->as.identifier.name, "my_var");

    return true;
}

TEST_FUNC(Parser_ParsePrimaryExpr_ParenthesizedExpression) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("(42)", arena, interner);

    ASTNode* node = parser.parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(node->as.integer_literal.value, 42);

    return true;
}

// This test depends on the `expect_parser_abort` helper function,
// which is defined in `test_parser_errors.cpp`. We need to declare it here.
bool expect_parser_abort(const char* source_code);

TEST_FUNC(Parser_Error_OnUnexpectedToken) {
    const char* source = ";"; // Semicolon is not a primary expression
    ASSERT_TRUE(expect_parser_abort(source));
    return true;
}

TEST_FUNC(Parser_FunctionCall_NoArgs) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("my_func()", arena, interner);

    ASTNode* node = parser.parseExpression();

    ASSERT_EQ(node->type, NODE_FUNCTION_CALL);
    ASSERT_EQ(node->as.function_call->callee->type, NODE_IDENTIFIER);
    ASSERT_STREQ(node->as.function_call->callee->as.identifier.name, "my_func");
    ASSERT_EQ(node->as.function_call->args->length(), 0);

    return true;
}

TEST_FUNC(Parser_FunctionCall_WithArgs) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("add(1, 2)", arena, interner);

    ASTNode* node = parser.parseExpression();

    ASSERT_EQ(node->type, NODE_FUNCTION_CALL);
    ASSERT_EQ(node->as.function_call->callee->type, NODE_IDENTIFIER);
    ASSERT_STREQ(node->as.function_call->callee->as.identifier.name, "add");
    ASSERT_EQ(node->as.function_call->args->length(), 2);
    ASSERT_EQ((*node->as.function_call->args)[0]->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ((*node->as.function_call->args)[0]->as.integer_literal.value, 1);
    ASSERT_EQ((*node->as.function_call->args)[1]->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ((*node->as.function_call->args)[1]->as.integer_literal.value, 2);

    return true;
}

TEST_FUNC(Parser_FunctionCall_WithTrailingComma) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("add(1, 2,)", arena, interner);

    ASTNode* node = parser.parseExpression();

    ASSERT_EQ(node->type, NODE_FUNCTION_CALL);
    ASSERT_EQ(node->as.function_call->args->length(), 2);
    ASSERT_EQ((*node->as.function_call->args)[0]->as.integer_literal.value, 1);
    ASSERT_EQ((*node->as.function_call->args)[1]->as.integer_literal.value, 2);

    return true;
}

TEST_FUNC(Parser_ArrayAccess) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("my_array[0]", arena, interner);

    ASTNode* node = parser.parseExpression();

    ASSERT_EQ(node->type, NODE_ARRAY_ACCESS);
    ASSERT_EQ(node->as.array_access->array->type, NODE_IDENTIFIER);
    ASSERT_STREQ(node->as.array_access->array->as.identifier.name, "my_array");
    ASSERT_EQ(node->as.array_access->index->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(node->as.array_access->index->as.integer_literal.value, 0);

    return true;
}

TEST_FUNC(Parser_ChainedPostfixOps) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("get_func()[0]", arena, interner);

    ASTNode* node = parser.parseExpression();

    ASSERT_EQ(node->type, NODE_ARRAY_ACCESS);
    ASTNode* callee = node->as.array_access->array;
    ASSERT_EQ(callee->type, NODE_FUNCTION_CALL);
    ASSERT_EQ(callee->as.function_call->callee->type, NODE_IDENTIFIER);
    ASSERT_STREQ(callee->as.function_call->callee->as.identifier.name, "get_func");

    return true;
}
