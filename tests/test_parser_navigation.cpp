#include "test_framework.hpp"
#include "lexer.hpp"
#include "parser.hpp"
#include "memory.hpp"

// Note: These tests will not compile until parser.hpp and parser.cpp are created.

// Test 1: Basic navigation with a simple token stream.
TEST_FUNC(Parser_Navigation_Simple) {
    ArenaAllocator arena(1024);
    Token tokens[3];
    tokens[0].type = TOKEN_VAR;
    tokens[1].type = TOKEN_IDENTIFIER;
    tokens[2].type = TOKEN_EOF;

    Parser p(tokens, 3, &arena);

    ASSERT_TRUE(!p.is_at_end());
    ASSERT_EQ(p.peek().type, TOKEN_VAR);

    Token t1 = p.advance();
    ASSERT_EQ(t1.type, TOKEN_VAR);

    ASSERT_TRUE(!p.is_at_end());
    ASSERT_EQ(p.peek().type, TOKEN_IDENTIFIER);

    Token t2 = p.advance();
    ASSERT_EQ(t2.type, TOKEN_IDENTIFIER);

    ASSERT_TRUE(!p.is_at_end());
    ASSERT_EQ(p.peek().type, TOKEN_EOF);

    p.advance();
    ASSERT_TRUE(p.is_at_end());

    return true;
}

// Test 2: Handling of an empty token stream.
TEST_FUNC(Parser_Navigation_EmptyStream) {
    ArenaAllocator arena(1024);

    // Test case 1: Valid pointer, zero count.
    Token tokens[1];
    tokens[0].type = TOKEN_EOF;
    Parser p1(tokens, 0, &arena);
    ASSERT_TRUE(p1.is_at_end());

    // Test case 2: NULL pointer, zero count.
    // This should trigger an assertion in the Parser's constructor in a debug build.
    // The test framework cannot catch assertion failures, so this test serves
    // as documentation for the expected behavior. If the program crashes here
    // in a debug build, it is the correct behavior.
    // Parser p2(NULL, 0, &arena);

    return true;
}

// Test 3: Boundary check right at the end of the stream.
TEST_FUNC(Parser_Navigation_BoundaryCheck) {
    ArenaAllocator arena(1024);
    Token tokens[2];
    tokens[0].type = TOKEN_INTEGER_LITERAL;
    tokens[0].value.integer = 123;
    tokens[1].type = TOKEN_EOF;

    Parser p(tokens, 2, &arena);

    p.advance(); // Consumes the integer literal
    ASSERT_TRUE(!p.is_at_end());
    ASSERT_EQ(p.peek().type, TOKEN_EOF);

    p.advance(); // Consumes EOF
    ASSERT_TRUE(p.is_at_end());

    return true;
}
