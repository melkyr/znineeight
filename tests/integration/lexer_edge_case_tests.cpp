#include <cstring>
#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"

TEST_FUNC(Integration_InvalidLeadingDotFloat) {
    // Floating-point literals MUST have a leading digit (e.g., 0.123, not .123).
    // A leading dot is lexed as TOKEN_DOT.
    // In Z98 0.12.1+, .123 is lexed as TOKEN_DOT + TOKEN_INTEGER_LITERAL(123).
    const char* source = ".123";
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    sm.addFile("test.zig", source, strlen(source));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_DOT, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_INTEGER_LITERAL, token.type);
    ASSERT_EQ(123, token.value.integer_literal.value);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(Integration_IdentifierAsFloatLeadingDot) {
    // Regression test for assigning a naked tag to a float variable.
    // .123 is now lexed as TOKEN_DOT + TOKEN_INTEGER_LITERAL.
    // This test ensures the lexer returns the correct tokens.
    const char* source = ".123";
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    sm.addFile("test.zig", source, strlen(source));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_DOT, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_INTEGER_LITERAL, token.type);

    return true;
}

TEST_FUNC(Integration_InferenceLeadingDot) {
    // .123 is lexed as TOKEN_DOT + TOKEN_INTEGER_LITERAL.
    const char* source = ".123";
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    sm.addFile("test.zig", source, strlen(source));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_DOT, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_INTEGER_LITERAL, token.type);

    return true;
}
