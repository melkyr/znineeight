#include "test_framework.hpp"
#include "test_utils.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"

#include <cmath> // For fabs

// Helper function to initialize lexer and get the first token
static Token lex_string(const char* source, ArenaAllocator& alloc) {
    StringInterner interner(alloc);
    ParserTestContext ctx(source, alloc, interner);
    return ctx.getParser()->peek();
}

// Helper for comparing floats
static bool compare_floats(double a, double b) {
    return fabs(a - b) < 1e-9;
}

TEST_FUNC(Lexer_FloatSimpleDecimal) {
    ArenaAllocator alloc(8192);
    Token token = lex_string("3.14", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 3.14));
    return true;
}

TEST_FUNC(Lexer_FloatNoFractionalPart) {
    ArenaAllocator alloc(8192);
    Token token = lex_string("123.", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 123.0));
    return true;
}

TEST_FUNC(Lexer_FloatNoIntegerPart) {
    ArenaAllocator alloc(8192);
    Token token = lex_string(".123", alloc); // Invalid: must have digits before '.'
    ASSERT_EQ(token.type, TOKEN_ERROR);
    return true;
}

TEST_FUNC(Lexer_FloatWithExponent) {
    ArenaAllocator alloc(8192);
    Token token = lex_string("1.23e+4", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 1.23e+4));
    return true;
}

TEST_FUNC(Lexer_FloatWithNegativeExponent) {
    ArenaAllocator alloc(8192);
    Token token = lex_string("5.67E-8", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 5.67E-8));
    return true;
}

TEST_FUNC(Lexer_FloatExponentNoSign) {
    ArenaAllocator alloc(8192);
    Token token = lex_string("9.0e10", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 9.0e10));
    return true;
}

TEST_FUNC(Lexer_FloatIntegerWithExponent) {
    ArenaAllocator alloc(8192);
    Token token = lex_string("1e10", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 1e10));
    return true;
}

TEST_FUNC(Lexer_FloatExponentNoDigits) {
    ArenaAllocator alloc(8192);
    StringInterner interner(alloc);
    ParserTestContext ctx("1.2e", alloc, interner);
    Parser* parser = ctx.getParser();

    Token t1 = parser->advance();
    ASSERT_EQ(t1.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(t1.value.floating_point, 1.2));

    Token t2 = parser->advance();
    ASSERT_EQ(t2.type, TOKEN_IDENTIFIER);
    ASSERT_STREQ(t2.value.identifier, "e");
    return true;
}


TEST_FUNC(Lexer_FloatHexSimple) {
    ArenaAllocator alloc(8192);
    Token token = lex_string("0x1.Ap2", alloc); // 1.625 * 2^2 = 6.5
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 6.5));
    return true;
}

TEST_FUNC(Lexer_FloatHexNoFractionalPart) {
    ArenaAllocator alloc(8192);
    Token token = lex_string("0x10p-1", alloc); // 16 * 2^-1 = 8.0
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 8.0));
    return true;
}

TEST_FUNC(Lexer_FloatHexNegativeExponent) {
    ArenaAllocator alloc(8192);
    Token token = lex_string("0xAB.CDp-4", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 10.737548828125));
    return true;
}

TEST_FUNC(Lexer_FloatHexInvalidFormat) {
    ArenaAllocator alloc(8192);
    // Missing 'p' or 'P'
    Token token1 = lex_string("0x1.A", alloc);
    ASSERT_EQ(token1.type, TOKEN_ERROR);

    // Missing exponent after 'p'
    Token token2 = lex_string("0x1.Ap", alloc);
    ASSERT_EQ(token2.type, TOKEN_ERROR);

    // Missing exponent after sign
    Token token3 = lex_string("0x1.Ap-", alloc);
    ASSERT_EQ(token3.type, TOKEN_ERROR);
    return true;
}
