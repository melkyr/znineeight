#include "test_framework.hpp"
#include "parser.hpp"
#include "memory.hpp"
#include "error.hpp" // Required for ErrorReport

// Test 1: Verify the 'match' method
TEST_FUNC(Parser_Matching_Match) {
    ArenaAllocator arena(1024);
    Token tokens[3];
    tokens[0].type = TOKEN_VAR;
    tokens[1].type = TOKEN_IDENTIFIER;
    tokens[2].type = TOKEN_EOF;

    Parser p(tokens, 3, &arena);

    // First, try to match a token that is not there.
    ASSERT_TRUE(!p.match(TOKEN_CONST));
    // The parser should not have advanced.
    ASSERT_EQ(p.peek().type, TOKEN_VAR);

    // Now, match the correct token.
    ASSERT_TRUE(p.match(TOKEN_VAR));
    // The parser should have advanced.
    ASSERT_EQ(p.peek().type, TOKEN_IDENTIFIER);

    return true;
}

// Test 2: Verify the 'expect' method on success
TEST_FUNC(Parser_Matching_Expect_Success) {
    ArenaAllocator arena(1024);
    Token tokens[2];
    tokens[0].type = TOKEN_FN;
    tokens[1].type = TOKEN_EOF;

    Parser p(tokens, 2, &arena);

    Token fn_token = p.expect(TOKEN_FN);
    ASSERT_EQ(fn_token.type, TOKEN_FN);
    // The parser should have advanced.
    ASSERT_EQ(p.peek().type, TOKEN_EOF);

    return true;
}

// Test 3: Verify the 'expect' method on failure
TEST_FUNC(Parser_Matching_Expect_Failure) {
    ArenaAllocator arena(1024);
    Token tokens[2];
    tokens[0].type = TOKEN_IDENTIFIER;
    tokens[0].location.line = 1;
    tokens[0].location.column = 5;
    tokens[1].type = TOKEN_EOF;

    Parser p(tokens, 2, &arena);

    // This should fail, but not crash.
    Token mismatched_token = p.expect(TOKEN_CONST);

    // 'expect' should return the token it found.
    ASSERT_EQ(mismatched_token.type, TOKEN_IDENTIFIER);

    // The stream should NOT have advanced.
    ASSERT_EQ(p.peek().type, TOKEN_IDENTIFIER);

    // An error should have been recorded.
    const DynamicArray<ErrorReport>* errors = p.getErrors();
    ASSERT_EQ(errors->length(), 1);

    // Check the error content.
    const ErrorReport& report = (*errors)[0];
    ASSERT_EQ(report.token.type, TOKEN_IDENTIFIER);
    ASSERT_EQ(report.token.location.line, 1);

    // A simple check for the message content.
    // We can't do a full strcmp because the exact wording is in the implementation.
    ASSERT_TRUE(report.message != NULL);

    return true;
}
