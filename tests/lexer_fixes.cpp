#include "test_framework.hpp"
#include "lexer.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include <cstring>

TEST_FUNC(Lexer_HandlesLongIdentifier) {
    // Create a long identifier string (e.g., 301 chars to be safe)
    char long_identifier[301];
    for (int i = 0; i < 300; ++i) {
        long_identifier[i] = 'a';
    }
    long_identifier[300] = '\0';

    // Set up the necessary components for the parser
    ArenaAllocator arena(8192);
    StringInterner interner(arena);

    // Use the test context to lex the long identifier
    ParserTestContext ctx(long_identifier, arena, interner);
    Parser parser = ctx.getParser();
    Token token = parser.peek();

    // Assert that the token is an identifier and its value matches
    ASSERT_TRUE(token.type == TOKEN_IDENTIFIER);
    ASSERT_TRUE(strcmp(token.value.identifier, long_identifier) == 0);

    return true;
}

TEST_FUNC(Lexer_HandlesU64Integer) {
    // This value is larger than a signed 64-bit integer can hold,
    // but fits in an unsigned 64-bit integer. strtol should fail.
    const char* large_uint_str = "18446744073709551610";

    ArenaAllocator arena(8192);
    StringInterner interner(arena);

    ParserTestContext ctx(large_uint_str, arena, interner);
    Parser parser = ctx.getParser();
    Token token = parser.peek();

    ASSERT_TRUE(token.type == TOKEN_INTEGER_LITERAL);

    // The token's value field is i64, but we will treat it as u64 for the comparison.
    // The custom parser should handle this correctly.
    // We use a hex literal for the expected value to avoid compiler warnings about large integer constants.
    ASSERT_TRUE((u64)token.value.integer == 0xFFFFFFFFFFFFFFFAULL);

    return true;
}

TEST_FUNC(Lexer_UnterminatedCharHexEscape) {
    // This tests for an out-of-bounds read in lexCharLiteral.
    // The input '\\x' at the end of the file could cause a read past the null terminator.
    const char* source = "'\\x'";

    ArenaAllocator arena(8192);
    StringInterner interner(arena);

    ParserTestContext ctx(source, arena, interner);
    Parser parser = ctx.getParser();
    Token token = parser.peek();

    ASSERT_TRUE(token.type == TOKEN_ERROR);

    return true;
}

TEST_FUNC(Lexer_UnterminatedStringHexEscape) {
    // This tests for an out-of-bounds read in lexStringLiteral.
    // The input '"\\x"' at the end of the file could cause a read past the null terminator.
    const char* source = "\"\\x\"";

    ArenaAllocator arena(8192);
    StringInterner interner(arena);

    ParserTestContext ctx(source, arena, interner);
    Parser parser = ctx.getParser();
    Token token = parser.peek();

    ASSERT_TRUE(token.type == TOKEN_ERROR);

    return true;
}

TEST_FUNC(Lexer_NumericLookaheadSafety) {
    // This tests that the lexer correctly distinguishes between a float and an integer followed by a range operator.
    // The input "1.." should result in an integer token '1', not a float.
    const char* source = "1..";

    ArenaAllocator arena(8192);
    StringInterner interner(arena);

    ParserTestContext ctx(source, arena, interner);
    Parser parser = ctx.getParser();
    Token token = parser.peek();

    // The lexer should identify the first token as an integer literal.
    ASSERT_TRUE(token.type == TOKEN_INTEGER_LITERAL);

    return true;
}

TEST_FUNC(Lexer_UnicodeInStringLiteral) {
    // Test for correct UTF-8 encoding of a Unicode escape sequence in a string.
    // The character '€' (Euro sign) is U+20AC.
    const char* source = "\"\\u{20AC}\"";
    const char* expected_utf8 = "\xE2\x82\xAC";

    ArenaAllocator arena(8192);
    StringInterner interner(arena);

    ParserTestContext ctx(source, arena, interner);
    Parser parser = ctx.getParser();
    Token token = parser.peek();

    ASSERT_TRUE(token.type == TOKEN_STRING_LITERAL);
    ASSERT_TRUE(strcmp(token.value.identifier, expected_utf8) == 0);

    return true;
}
