#include "test_framework.hpp"
#include "lexer.hpp"
#include "source_manager.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include <string.h>

TEST_FUNC(LexerSpecialOperators) {
    ArenaAllocator allocator(1024);
    StringInterner interner(allocator);
    SourceManager source_manager(allocator);
    const char* source = ". .* .? ? ** +% -% *%";
    u32 file_id = source_manager.addFile("test.zig", source, strlen(source));
    Lexer lexer(source_manager, interner, allocator, file_id);

    Token t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_DOT);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_DOT_ASTERISK);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_DOT_QUESTION);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_QUESTION);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_STAR2);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_PLUSPERCENT);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_MINUSPERCENT);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_STARPERCENT);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_EOF);

    return true;
}

TEST_FUNC(LexerSpecialOperatorsMixed) {
    ArenaAllocator allocator(1024);
    StringInterner interner(allocator);
    SourceManager source_manager(allocator);
    const char* source = ".+*?**+";
    u32 file_id = source_manager.addFile("test.zig", source, strlen(source));
    Lexer lexer(source_manager, interner, allocator, file_id);

    Token t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_DOT);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_PLUS);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_STAR);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_QUESTION);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_STAR2);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_PLUS);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_EOF);

    return true;
}
