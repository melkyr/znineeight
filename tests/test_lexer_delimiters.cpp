#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/source_manager.hpp"

TEST_FUNC(delimiters_lexing) {
    ArenaAllocator arena(1024);
    SourceManager sm(arena);
    const char* test_content = ": -> => ... .. . ..a";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, 0);

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
    ASSERT_EQ(TOKEN_ELLIPSIS, token.type);
    ASSERT_EQ(9, token.location.column);

    // Malformed .. should be two dots
    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_DOT, token.type);
    ASSERT_EQ(13, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_DOT, token.type);
    ASSERT_EQ(14, token.location.column);

    // Malformed .
    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_DOT, token.type);
    ASSERT_EQ(16, token.location.column);

    // Malformed ..a should be two dots and an identifier
    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_DOT, token.type);
    ASSERT_EQ(18, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_DOT, token.type);
    ASSERT_EQ(19, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_IDENTIFIER, token.type);
    ASSERT_EQ(20, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}
