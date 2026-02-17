#include "test_framework.hpp"
#include "lexer.hpp"
#include "source_manager.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include <cstring> // For strlen

TEST_FUNC(lex_arithmetic_and_bitwise_operators) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* source = "% ~ & | ^ << >>";
    u32 file_id = sm.addFile("test.zig", source, strlen(source));

    Lexer lexer(sm, interner, arena, file_id);

    Token t;

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_PERCENT);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_TILDE);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_AMPERSAND);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_PIPE);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_CARET);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_LARROW2);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_RARROW2);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_EOF);

    return true;
}

TEST_FUNC(Lexer_RangeExpression) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* source = "3..7";
    u32 file_id = sm.addFile("test.zig", source, strlen(source));

    Lexer lexer(sm, interner, arena, file_id);

    Token t;

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_INTEGER_LITERAL);
    ASSERT_EQ(t.value.integer_literal.value, 3);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_RANGE);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_INTEGER_LITERAL);
    ASSERT_EQ(t.value.integer_literal.value, 7);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_EOF);

    return true;
}
