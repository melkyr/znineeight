#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/source_manager.hpp"
#include "../src/include/string_interner.hpp"

TEST_FUNC(empty_block_comment) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "/**/+";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_PLUS, token.type);
    ASSERT_EQ(1, token.location.line);
    ASSERT_EQ(5, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(multiline_commented_out_code) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "/*\n"
                               "    var x: i32 = 10;\n"
                               "    if (x > 5) {\n"
                               "        return x;\n"
                               "    }\n"
                               "*/\n"
                               "const y = 20;";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_CONST, token.type);
    ASSERT_EQ(7, token.location.line);
    ASSERT_EQ(1, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_IDENTIFIER, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EQUAL, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_INTEGER_LITERAL, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_SEMICOLON, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(line_comment_in_block) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "/* // this is ignored */+";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_PLUS, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(block_comment_in_line) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "// /* this is ignored */\n+";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_PLUS, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(1, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(comment_with_keywords) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "/* if for while var const */ -";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_MINUS, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(comment_with_operators) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "/* + - * / () {} [] */=";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EQUAL, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(block_comment_at_eof) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "+/* comment */";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_PLUS, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(complex_nesting) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "/* level 1 /* level 2 /* nested */ */ */*";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_STAR, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}
