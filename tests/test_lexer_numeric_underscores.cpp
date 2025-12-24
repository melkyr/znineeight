#include "test_framework.hpp"
#include "lexer.hpp"
#include "source_manager.hpp"
#include "string_interner.hpp"
#include "memory.hpp"

TEST_FUNC(Lexer_ValidNumericUnderscore) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", "1_000", 5);
    Lexer lexer(sm, interner, arena, file_id);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_INTEGER_LITERAL, token.type);
    ASSERT_EQ(1000, token.value.integer);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(Lexer_InvalidTrailingUnderscore) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", "123_", 4);
    Lexer lexer(sm, interner, arena, file_id);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_ERROR, token.type);
    ASSERT_EQ(1, token.location.line);
    ASSERT_EQ(4, token.location.column);

    return true;
}

TEST_FUNC(Lexer_InvalidTrailingUnderscoreHex) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", "0xFF_", 5);
    Lexer lexer(sm, interner, arena, file_id);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_ERROR, token.type);
    ASSERT_EQ(1, token.location.line);
    ASSERT_EQ(5, token.location.column);

    return true;
}

TEST_FUNC(Lexer_ValidFloatWithUnderscore) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", "1_234.5", 7);
    Lexer lexer(sm, interner, arena, file_id);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_FLOAT_LITERAL, token.type);
    ASSERT_EQ(1234.5, token.value.floating_point);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(Lexer_InvalidFloatTrailingUnderscore) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", "1.23_", 5);
    Lexer lexer(sm, interner, arena, file_id);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_ERROR, token.type);
    ASSERT_EQ(1, token.location.line);
    ASSERT_EQ(5, token.location.column);

    return true;
}
