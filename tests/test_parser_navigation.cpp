#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"

// Note: These tests will not compile until parser.hpp and parser.cpp are created.

// Test 1: Basic navigation with a simple token stream.
TEST_FUNC(Parser_Navigation_Simple) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("var my_var", arena, interner);
    Parser* p = ctx.getParser();

    ASSERT_TRUE(!p->is_at_end());
    ASSERT_EQ(p->peek().type, TOKEN_VAR);

    Token t1 = p->advance();
    ASSERT_EQ(t1.type, TOKEN_VAR);

    ASSERT_TRUE(!p->is_at_end());
    ASSERT_EQ(p->peek().type, TOKEN_IDENTIFIER);

    Token t2 = p->advance();
    ASSERT_EQ(t2.type, TOKEN_IDENTIFIER);

    ASSERT_TRUE(p->is_at_end());

    return true;
}

// Test 3: Boundary check right at the end of the stream.
TEST_FUNC(Parser_Navigation_BoundaryCheck) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("123", arena, interner);
    Parser* p = ctx.getParser();

    p->advance(); // Consumes the integer literal
    ASSERT_TRUE(p->is_at_end());

    return true;
}
