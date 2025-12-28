#include "test_framework.hpp"
#include "lexer.hpp"
#include "source_manager.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include <cstring> // For strlen

TEST_FUNC(lex_compound_assignment_operators) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* source = "+= -= *= /= %= &= |= ^= <<= >>=";
    u32 file_id = sm.addFile("test.zig", source, strlen(source));

    Lexer lexer(sm, interner, arena, file_id);

    Token t;

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_PLUS_EQUAL);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_MINUS_EQUAL);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_STAR_EQUAL);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_SLASH_EQUAL);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_PERCENT_EQUAL);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_AMPERSAND_EQUAL);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_PIPE_EQUAL);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_CARET_EQUAL);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_LARROW2_EQUAL);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_RARROW2_EQUAL);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_EOF);

    return true;
}
