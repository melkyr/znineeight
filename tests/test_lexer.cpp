#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/compilation_unit.hpp"
#include "../src/include/parser.hpp"
#include "../src/include/source_manager.hpp"
#include "../src/include/string_interner.hpp"

TEST_FUNC(single_char_tokens) {
    ArenaAllocator arena(16384);
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
    ASSERT_EQ(5, token.location.column);

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

TEST_FUNC(IntegerRangeAmbiguity) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* test_content = "0..10";
    u32 file_id = unit.addSource("test.zig", test_content);
    Parser* parser = unit.createParser(file_id);

    Token token = parser->advance();
    ASSERT_EQ(TOKEN_INTEGER_LITERAL, token.type);
    ASSERT_EQ(0, token.value.integer_literal.value);

    token = parser->advance();
    ASSERT_EQ(TOKEN_RANGE, token.type);

    token = parser->advance();
    ASSERT_EQ(TOKEN_INTEGER_LITERAL, token.type);
    ASSERT_EQ(10, token.value.integer_literal.value);

    token = parser->peek();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(token_fields_are_initialized) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", "fn");
    Parser* parser = unit.createParser(file_id);
    Token token = parser->peek();
    ASSERT_EQ(token.type, TOKEN_FN);
    ASSERT_TRUE(token.value.integer_literal.value == 0);
    return true;
}

TEST_FUNC(Lexer_ErrorConditions) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* source = "'a "  // 1. Unterminated char literal
                         "123. " // 2. Invalid numeric format
                         "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa " // 3. Identifier too long
                         "@";    // 4. Unrecognized character
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);

    Token t = parser->advance();
    ASSERT_EQ(TOKEN_ERROR, t.type); // Unterminated char literal

    t = parser->advance();
    ASSERT_EQ(TOKEN_FLOAT_LITERAL, t.type);

    t = parser->advance();
    ASSERT_EQ(TOKEN_IDENTIFIER, t.type); // Identifier too long is now valid

    t = parser->advance();
    ASSERT_EQ(TOKEN_ERROR, t.type); // Unrecognized character

    t = parser->peek();
    ASSERT_EQ(TOKEN_EOF, t.type);

    return true;
}

TEST_FUNC(Lexer_IdentifiersAndStrings) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* source = "my_var \"hello world\" _another_var \"\"";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);

    // Test my_var
    Token t = parser->advance();
    ASSERT_EQ(TOKEN_IDENTIFIER, t.type);
    ASSERT_STREQ("my_var", t.value.identifier);

    // Test "hello world"
    t = parser->advance();
    ASSERT_EQ(TOKEN_STRING_LITERAL, t.type);
    ASSERT_STREQ("hello world", t.value.identifier);

    // Test _another_var
    t = parser->advance();
    ASSERT_EQ(TOKEN_IDENTIFIER, t.type);
    ASSERT_STREQ("_another_var", t.value.identifier);

    // Test ""
    t = parser->advance();
    ASSERT_EQ(TOKEN_STRING_LITERAL, t.type);
    ASSERT_STREQ("", t.value.identifier);

    t = parser->peek();
    ASSERT_EQ(TOKEN_EOF, t.type);

    return true;
}

TEST_FUNC(Lexer_ComprehensiveCrossGroup) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* source = "if (x > 10) {\n"
                         "  return 0xFF;\n"
                         "} else {\n"
                         "  while (i < 100) {\n"
                         "    i += 1;\n"
                         "  }\n"
                         "}\n"
                         "const pi = 3.14;\n";

    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);

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

    for (int i = 0; i < static_cast<int>(sizeof(expected_tokens) / sizeof(TokenType)); ++i) {
        if (expected_tokens[i] == TOKEN_EOF) {
            Token t = parser->peek();
            ASSERT_EQ(expected_tokens[i], t.type);
        } else {
            Token t = parser->advance();
            ASSERT_EQ(expected_tokens[i], t.type);
        }
    }

    return true;
}

TEST_FUNC(IntegerLiterals) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    SourceManager sm(arena);
    const char* test_content = "123 0xFF";
    sm.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(sm, interner, arena, 0);

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_INTEGER_LITERAL, token.type);
    ASSERT_EQ(123, token.value.integer_literal.value);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_INTEGER_LITERAL, token.type);
    ASSERT_EQ(255, token.value.integer_literal.value);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(skip_comments) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* test_content = "// this is a line comment\n"
                               "+\n"
                               "/* this is a block comment */\n"
                               "-\n"
                               "// another line comment at EOF";
    u32 file_id = unit.addSource("test.zig", test_content);
    Parser* parser = unit.createParser(file_id);

    Token token = parser->advance();
    ASSERT_EQ(TOKEN_PLUS, token.type);
    ASSERT_EQ(2, token.location.line);
    ASSERT_EQ(1, token.location.column);

    token = parser->advance();
    ASSERT_EQ(TOKEN_MINUS, token.type);
    ASSERT_EQ(4, token.location.line);
    ASSERT_EQ(1, token.location.column);

    token = parser->peek();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(nested_block_comments) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* test_content = "/* start /* nested */ end */+";
    u32 file_id = unit.addSource("test.zig", test_content);
    Parser* parser = unit.createParser(file_id);

    Token token = parser->advance();
    ASSERT_EQ(TOKEN_PLUS, token.type);
    ASSERT_EQ(1, token.location.line);
    ASSERT_EQ(29, token.location.column);

    token = parser->peek();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(unterminated_block_comment) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* test_content = "/* this comment is not closed";
    u32 file_id = unit.addSource("test.zig", test_content);
    Parser* parser = unit.createParser(file_id);

    Token token = parser->peek();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(assignment_vs_equality) {
    ArenaAllocator arena(16384);
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
    ArenaAllocator arena(16384);
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
