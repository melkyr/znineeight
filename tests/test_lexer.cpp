#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/source_manager.hpp"
#include "../src/include/string_interner.hpp"

TEST_FUNC(single_char_tokens) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "+\t-\n/ *;(){}[]@";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

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
    ASSERT_EQ(3, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_SEMICOLON, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(4, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_LPAREN, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(5, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_RPAREN, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(6, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_LBRACE, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(7, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_RBRACE, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(8, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_LBRACKET, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(9, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_RBRACKET, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(10, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_ERROR, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(11, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(token_fields_are_initialized) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", "fn", 2);
    Lexer lexer(sm, interner, arena, file_id);
    Token token = lexer.nextToken();
    ASSERT_EQ(token.type, TOKEN_FN);
    ASSERT_TRUE(token.value.integer == 0);
    return true;
}

TEST_FUNC(Lexer_ErrorConditions) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* source = "'a "  // 1. Unterminated char literal
                         "123. " // 2. Invalid numeric format
                         "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa " // 3. Identifier too long
                         "@";    // 4. Unrecognized character
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);

    Token t = lexer.nextToken();
    ASSERT_EQ(TOKEN_ERROR, t.type); // Unterminated char literal

    t = lexer.nextToken();
    ASSERT_EQ(TOKEN_ERROR, t.type); // Invalid numeric format

    t = lexer.nextToken();
    ASSERT_EQ(TOKEN_ERROR, t.type); // Identifier too long

    t = lexer.nextToken();
    ASSERT_EQ(TOKEN_ERROR, t.type); // Unrecognized character

    t = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, t.type);

    return true;
}

TEST_FUNC(Lexer_IdentifiersAndStrings) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* source = "my_var \"hello world\" _another_var \"\"";
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);

    // Test my_var
    Token t = lexer.nextToken();
    ASSERT_EQ(TOKEN_IDENTIFIER, t.type);
    ASSERT_STREQ("my_var", t.value.identifier);

    // Test "hello world"
    t = lexer.nextToken();
    ASSERT_EQ(TOKEN_STRING_LITERAL, t.type);
    ASSERT_STREQ("hello world", t.value.identifier);

    // Test _another_var
    t = lexer.nextToken();
    ASSERT_EQ(TOKEN_IDENTIFIER, t.type);
    ASSERT_STREQ("_another_var", t.value.identifier);

    // Test ""
    t = lexer.nextToken();
    ASSERT_EQ(TOKEN_STRING_LITERAL, t.type);
    ASSERT_STREQ("", t.value.identifier);

    t = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, t.type);

    return true;
}

TEST_FUNC(Lexer_ComprehensiveCrossGroup) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* source = "if (x > 10) {\n"
                         "  return 0xFF;\n"
                         "} else {\n"
                         "  while (i < 100) {\n"
                         "    i += 1;\n"
                         "  }\n"
                         "}\n"
                         "const pi = 3.14;\n";

    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);

    TokenType expected_tokens[] = {
        TOKEN_IF, TOKEN_LPAREN, TOKEN_IDENTIFIER, TOKEN_GREATER, TOKEN_INTEGER_LITERAL, TOKEN_RPAREN, TOKEN_LBRACE,
        TOKEN_RETURN, TOKEN_INTEGER_LITERAL, TOKEN_SEMICOLON,
        TOKEN_RBRACE, TOKEN_ELSE, TOKEN_LBRACE,
        TOKEN_WHILE, TOKEN_LPAREN, TOKEN_IDENTIFIER, TOKEN_LESS, TOKEN_INTEGER_LITERAL, TOKEN_RPAREN, TOKEN_LBRACE,
        TOKEN_IDENTIFIER, TOKEN_PLUS_EQUAL, TOKEN_INTEGER_LITERAL, TOKEN_SEMICOLON,
        TOKEN_RBRACE,
        TOKEN_RBRACE,
        TOKEN_CONST, TOKEN_IDENTIFIER, TOKEN_EQUAL, TOKEN_FLOAT_LITERAL, TOKEN_SEMICOLON,
        TOKEN_EOF
    };

    for (int i = 0; i < sizeof(expected_tokens) / sizeof(TokenType); ++i) {
        Token t = lexer.nextToken();
        ASSERT_EQ(expected_tokens[i], t.type);
    }

    return true;
}

TEST_FUNC(IntegerLiterals) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "123 0xFF";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_INTEGER_LITERAL, token.type);
    ASSERT_EQ(123, token.value.integer);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_INTEGER_LITERAL, token.type);
    ASSERT_EQ(255, token.value.integer);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(skip_comments) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "// this is a line comment\n"
                               "+\n"
                               "/* this is a block comment */\n"
                               "-\n"
                               "// another line comment at EOF";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_PLUS, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(1, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_MINUS, token.type);
    ASSERT_EQ(4, token.location.line);
    ASSERT_EQ(1, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(nested_block_comments) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "/* start /* nested */ end */+";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_PLUS, token.type);
    ASSERT_EQ(1, token.location.line);
    ASSERT_EQ(29, token.location.column);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(unterminated_block_comment) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "/* this comment is not closed";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(assignment_vs_equality) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "= == = > >= < <= ! !=";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

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
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "== != <= >= ";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

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
