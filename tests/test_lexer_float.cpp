#include "test_framework.hpp"
#include "lexer.hpp"
#include "source_manager.hpp"
#include "memory.hpp"
#include "string_interner.hpp"

#include <cmath> // For fabs

// Helper function to initialize lexer and get the first token
static Token lex_string(const char* source, ArenaAllocator& alloc) {
    SourceManager sm(alloc);
    StringInterner interner(alloc);
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, alloc, file_id);
    return lexer.nextToken();
}

// Helper for comparing floats
static bool compare_floats(double a, double b) {
    return fabs(a - b) < 1e-9;
}

TEST_FUNC(Lexer_FloatSimpleDecimal) {
    ArenaAllocator alloc(1024);
    Token token = lex_string("3.14", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 3.14));
    return true;
}

TEST_FUNC(Lexer_FloatWithExponent) {
    ArenaAllocator alloc(1024);
    Token token = lex_string("1.23e+4", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 1.23e+4));

    token = lex_string("5.67E-8", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 5.67E-8));

    token = lex_string("9.0e10", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 9.0e10));

    token = lex_string("1e10", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 1e10));
    return true;
}

TEST_FUNC(Lexer_FloatWithUnderscores) {
    ArenaAllocator alloc(1024);

    // Decimal floats with underscores
    Token token = lex_string("3.141_59", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 3.14159));

    token = lex_string("1_000.0", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 1000.0));

    token = lex_string("1.23e+4_5", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 1.23e+45));

    token = lex_string("1_000e-1_0", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 1000e-10));

    // Hex floats with underscores
    token = lex_string("0x1A_B.C_Dp-2", alloc); // (26*16 + 11 + 12/16 + 13/256) * 2^-2 = (427.80078125) * 0.25 = 106.9501953125
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 106.9501953125));

    token = lex_string("0x1_0p-1", alloc); // 16 * 2^-1 = 8.0
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 8.0));

    return true;
}


TEST_FUNC(Lexer_FloatInvalidSyntax) {
    ArenaAllocator alloc(1024);
    // These should be errors because they are syntactically invalid
    ASSERT_EQ(lex_string("123.", alloc).type, TOKEN_ERROR);
    ASSERT_EQ(lex_string(".123", alloc).type, TOKEN_ERROR);
    ASSERT_EQ(lex_string("1.2e", alloc).type, TOKEN_ERROR);
    ASSERT_EQ(lex_string("3.4e+", alloc).type, TOKEN_ERROR);
    ASSERT_EQ(lex_string("0x1.A", alloc).type, TOKEN_ERROR);
    ASSERT_EQ(lex_string("0x1.Ap", alloc).type, TOKEN_ERROR);
    ASSERT_EQ(lex_string("0x1.Ap-", alloc).type, TOKEN_ERROR);
    return true;
}

#include "test_utils.hpp"
TEST_FUNC(Lexer_FloatInvalidUnderscore_AdjacentToDecimal1) {
    ArenaAllocator alloc(1024);
    StringInterner interner(alloc);
    SourceManager sm(alloc);
    u32 file_id = sm.addFile("test.zig", "1_.0", 4);
    Lexer lexer(sm, interner, alloc, file_id);
    Token t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_INTEGER_LITERAL);
    ASSERT_EQ(t.value.integer, 1);
    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_IDENTIFIER);
    ASSERT_STREQ(t.value.identifier, "_.0");
    return true;
}

TEST_FUNC(Lexer_FloatInvalidUnderscore_AdjacentToDecimal2) {
    ArenaAllocator alloc(1024);
    StringInterner interner(alloc);
    SourceManager sm(alloc);
    u32 file_id = sm.addFile("test.zig", "1._0", 4);
    Lexer lexer(sm, interner, alloc, file_id);
    Token t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_INTEGER_LITERAL);
    ASSERT_EQ(t.value.integer, 1);
    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_DOT);
    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_IDENTIFIER);
    ASSERT_STREQ(t.value.identifier, "_0");
    return true;
}

TEST_FUNC(Lexer_FloatInvalidUnderscore_AdjacentToExponent) {
    ArenaAllocator alloc(1024);
    StringInterner interner(alloc);
    SourceManager sm(alloc);
    u32 file_id = sm.addFile("test.zig", "1.0e_5", 6);
    Lexer lexer(sm, interner, alloc, file_id);
    Token t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(t.value.floating_point, 1.0));
    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_IDENTIFIER);
    ASSERT_STREQ(t.value.identifier, "e_5");
    return true;
}

TEST_FUNC(Lexer_FloatInvalidUnderscore_Consecutive) {
    ArenaAllocator alloc(1024);
    StringInterner interner(alloc);
    SourceManager sm(alloc);
    u32 file_id = sm.addFile("test.zig", "1.0__5", 6);
    Lexer lexer(sm, interner, alloc, file_id);
    Token t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(t.value.floating_point, 1.0));
    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_IDENTIFIER);
    ASSERT_STREQ(t.value.identifier, "__5");
    return true;
}

TEST_FUNC(Lexer_FloatInvalidUnderscore_Trailing) {
    ArenaAllocator alloc(1024);
    StringInterner interner(alloc);
    SourceManager sm(alloc);
    u32 file_id = sm.addFile("test.zig", "3.14_", 5);
    Lexer lexer(sm, interner, alloc, file_id);
    Token t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(t.value.floating_point, 3.14));
    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_IDENTIFIER);
    ASSERT_STREQ(t.value.identifier, "_");
    return true;
}


TEST_FUNC(Lexer_FloatHexSimple) {
    ArenaAllocator alloc(1024);
    Token token = lex_string("0x1.Ap2", alloc); // 1.625 * 2^2 = 6.5
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 6.5));

    token = lex_string("0x10p-1", alloc); // 16 * 2^-1 = 8.0
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 8.0));

    token = lex_string("0xAB.CDp-4", alloc);
    ASSERT_EQ(token.type, TOKEN_FLOAT_LITERAL);
    ASSERT_TRUE(compare_floats(token.value.floating_point, 10.737548828125));
    return true;
}
