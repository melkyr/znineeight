#include "test_framework.hpp"
#include "lexer.hpp"
#include "source_manager.hpp"
#include "memory.hpp"
#include "string_interner.hpp"

TEST_FUNC(Lexer_CharLiteralHappyPath) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* source = "'a' 'Z' '\\n' '\\''";
    u32 file_id = sm.addFile("test.zig", source, strlen(source));

    Lexer lexer(sm, interner, arena, file_id);

    Token t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_CHAR_LITERAL);
    ASSERT_EQ(t.value.character, 'a');

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_CHAR_LITERAL);
    ASSERT_EQ(t.value.character, 'Z');

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_CHAR_LITERAL);
    ASSERT_EQ(t.value.character, '\n');

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_CHAR_LITERAL);
    ASSERT_EQ(t.value.character, '\'');

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_EOF);

    return 0;
}

TEST_FUNC(Lexer_CharLiteralHex) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* source = "'\\x41' '\\x6F'";
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);

    Token t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_CHAR_LITERAL);
    ASSERT_EQ(t.value.character, 0x41);

    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_CHAR_LITERAL);
    ASSERT_EQ(t.value.character, 0x6F);

    return 0;
}

TEST_FUNC(Lexer_CharLiteralUnicode) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* source = "'\\u{1f4a9}'";
    u32 file_id = sm.addFile("test.zig", source, strlen(source));

    Lexer lexer(sm, interner, arena, file_id);
    Token t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_CHAR_LITERAL);
    ASSERT_EQ(t.value.character, 0x1f4a9);

    return 0;
}


TEST_FUNC(Lexer_CharLiteralErrors) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* source = "'' 'a 'ab' '\\z'";
    u32 file_id = sm.addFile("test.zig", source, strlen(source));

    Lexer lexer(sm, interner, arena, file_id);

    // Empty literal
    Token t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_ERROR);

    // Unterminated
    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_ERROR);

    // Multi-character
    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_ERROR);

    // Invalid escape
    t = lexer.nextToken();
    ASSERT_EQ(t.type, TOKEN_ERROR);

    return 0;
}
