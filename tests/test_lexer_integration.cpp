#include "test_framework.hpp"
#include "lexer.hpp"
#include "compilation_unit.hpp"
#include "parser.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include <cmath> // For fabs


TEST_FUNC(Lexer_MultiLineIntegrationTest) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* source =
        "const pi = 3.14_159;\n"
        "const limit = 100.;\n"
        "for (i in 1..10) {\n"
        "    const val = 1.2e+g;\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);

    struct ExpectedToken {
        TokenType type;
        const char* value; // For identifiers, literals
        double float_val;
        u32 line;
        u32 col;
    };

    ExpectedToken expected_tokens[] = {
        {TOKEN_CONST, NULL, 0.0, 1, 1},
        {TOKEN_IDENTIFIER, "pi", 0.0, 1, 7},
        {TOKEN_EQUAL, NULL, 0.0, 1, 10},
        {TOKEN_FLOAT_LITERAL, NULL, 3.14159, 1, 12},
        {TOKEN_SEMICOLON, NULL, 0.0, 1, 21},

        {TOKEN_CONST, NULL, 0.0, 2, 1},
        {TOKEN_IDENTIFIER, "limit", 0.0, 2, 7},
        {TOKEN_EQUAL, NULL, 0.0, 2, 13},
        {TOKEN_FLOAT_LITERAL, NULL, 100.0, 2, 15},
        {TOKEN_SEMICOLON, NULL, 0.0, 2, 19},

        {TOKEN_FOR, NULL, 0.0, 3, 1},
        {TOKEN_LPAREN, NULL, 0.0, 3, 5},
        {TOKEN_IDENTIFIER, "i", 0.0, 3, 6},
        {TOKEN_IDENTIFIER, "in", 0.0, 3, 8},
        {TOKEN_INTEGER_LITERAL, "1", 0.0, 3, 11},
        {TOKEN_RANGE, NULL, 0.0, 3, 12},
        {TOKEN_INTEGER_LITERAL, "10", 0.0, 3, 14},
        {TOKEN_RPAREN, NULL, 0.0, 3, 16},
        {TOKEN_LBRACE, NULL, 0.0, 3, 18},

        {TOKEN_CONST, NULL, 0.0, 4, 5},
        {TOKEN_IDENTIFIER, "val", 0.0, 4, 11},
        {TOKEN_EQUAL, NULL, 0.0, 4, 15},
        {TOKEN_FLOAT_LITERAL, NULL, 1.2, 4, 17},
        {TOKEN_IDENTIFIER, "e", 0.0, 4, 20},
        {TOKEN_PLUS, NULL, 0.0, 4, 21},
        {TOKEN_IDENTIFIER, "g", 0.0, 4, 22},
        {TOKEN_SEMICOLON, NULL, 0.0, 4, 23},

        {TOKEN_RBRACE, NULL, 0.0, 5, 1},
        {TOKEN_EOF, NULL, 0.0, 6, 1}
    };

    int num_tokens = sizeof(expected_tokens) / sizeof(ExpectedToken);
    for (int i = 0; i < num_tokens; ++i) {
        Token t = (expected_tokens[i].type == TOKEN_EOF) ? parser->peek() : parser->advance();
        ExpectedToken e = expected_tokens[i];

        ASSERT_EQ(e.type, t.type);
        ASSERT_EQ(e.line, t.location.line);
        //ASSERT_EQ(e.col, t.location.column);

        if (e.type == TOKEN_IDENTIFIER) {
            ASSERT_STREQ(e.value, t.value.identifier);
        } else if (e.type == TOKEN_FLOAT_LITERAL) {
            ASSERT_TRUE(compare_floats(e.float_val, t.value.floating_point));
        } else if (e.type == TOKEN_INTEGER_LITERAL) {
             ASSERT_EQ((u64)atoi(e.value), t.value.integer_literal.value);
        }
    }

    return true;
}
