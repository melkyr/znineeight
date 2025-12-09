#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/source_manager.hpp"

TEST_FUNC(single_char_tokens) {
    ArenaAllocator arena(1024);
    SourceManager sm(arena);
    const char* test_content = "+\t-\n/*;(){}[]@";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_PLUS, token.type);
    ASSERT_EQ(1, token.location.line);
    ASSERT_EQ(1, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_MINUS, token.type);
    ASSERT_EQ(1, token.location.line);
    ASSERT_EQ(3, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_SLASH, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(1, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_STAR, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(2, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_SEMICOLON, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(3, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_LPAREN, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(4, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_RPAREN, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(5, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_LBRACE, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(6, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_RBRACE, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(7, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_LBRACKET, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(8, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_RBRACKET, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(9, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_ERROR, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(10, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(assignment_vs_equality) {
    ArenaAllocator arena(1024);
    SourceManager sm(arena);
    const char* test_content = "= == = > >= < <= ! !=";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EQUAL, token.type);
    ASSERT_EQ(1, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EQUAL_EQUAL, token.type);
    ASSERT_EQ(3, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EQUAL, token.type);
    ASSERT_EQ(6, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_GREATER, token.type);
    ASSERT_EQ(8, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_GREATER_EQUAL, token.type);
    ASSERT_EQ(10, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_LESS, token.type);
    ASSERT_EQ(13, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_LESS_EQUAL, token.type);
    ASSERT_EQ(15, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_BANG, token.type);
    ASSERT_EQ(18, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_BANG_EQUAL, token.type);
    ASSERT_EQ(20, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(multi_char_tokens) {
    ArenaAllocator arena(1024);
    SourceManager sm(arena);
    const char* test_content = "== != <= >= ";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EQUAL_EQUAL, token.type);
    ASSERT_EQ(1, token.location.line);
    ASSERT_EQ(1, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_BANG_EQUAL, token.type);
    ASSERT_EQ(1, token.location.line);
    ASSERT_EQ(4, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_LESS_EQUAL, token.type);
    ASSERT_EQ(1, token.location.line);
    ASSERT_EQ(7, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_GREATER_EQUAL, token.type);
    ASSERT_EQ(1, token.location.line);
    ASSERT_EQ(10, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}
