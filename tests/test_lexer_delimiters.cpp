#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/source_manager.hpp"
#include "../src/include/string_interner.hpp"

TEST_FUNC(Lexer_Delimiters) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = ": -> =>";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_COLON, token.type);
    ASSERT_EQ(1, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_ARROW, token.type);
    ASSERT_EQ(3, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_FAT_ARROW, token.type);
    ASSERT_EQ(6, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(Lexer_DotOperators) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = ". .. ... .ident";
    sm.addFile("test_dots.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_DOT, token.type);
    ASSERT_EQ(1, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_RANGE, token.type);
    ASSERT_EQ(3, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_ELLIPSIS, token.type);
    ASSERT_EQ(6, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_DOT, token.type);
    ASSERT_EQ(10, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_IDENTIFIER, token.type);
    ASSERT_EQ(11, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}
