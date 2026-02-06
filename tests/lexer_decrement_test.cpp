#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/source_manager.hpp"
#include "../src/include/memory.hpp"
#include "../src/include/string_interner.hpp"
#include <cstring>

TEST_FUNC(lex_decrement_operator) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* source = "--";
    u32 file_id = sm.addFile("test.zig", source, strlen(source));

    Lexer lexer(sm, interner, arena, file_id);

    Token t = lexer.nextToken();
    ASSERT_EQ(TOKEN_MINUS2, t.type);

    t = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, t.type);

    return true;
}

TEST_FUNC(lex_pipe_pipe_operator) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* source = "||";
    u32 file_id = sm.addFile("test.zig", source, strlen(source));

    Lexer lexer(sm, interner, arena, file_id);

    Token t = lexer.nextToken();
    ASSERT_EQ(TOKEN_PIPE_PIPE, t.type);

    t = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, t.type);

    return true;
}

TEST_FUNC(lex_decrement_mixed) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* source = "x--y";
    u32 file_id = sm.addFile("test.zig", source, strlen(source));

    Lexer lexer(sm, interner, arena, file_id);

    Token t = lexer.nextToken();
    ASSERT_EQ(TOKEN_IDENTIFIER, t.type);

    t = lexer.nextToken();
    ASSERT_EQ(TOKEN_MINUS2, t.type);

    t = lexer.nextToken();
    ASSERT_EQ(TOKEN_IDENTIFIER, t.type);

    t = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, t.type);

    return true;
}
