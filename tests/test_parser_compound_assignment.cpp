#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include <cstring>

TEST_FUNC(Parser_CompoundAssignment_Simple) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("a += 5", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* expr = parser->parseExpression();

    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_COMPOUND_ASSIGNMENT);
    ASSERT_EQ(expr->as.compound_assignment->op, TOKEN_PLUS_EQUAL);

    ASTNode* left = expr->as.compound_assignment->lvalue;
    ASSERT_EQ(left->type, NODE_IDENTIFIER);
    ASSERT_STREQ(left->as.identifier.name, "a");

    ASTNode* right = expr->as.compound_assignment->rvalue;
    ASSERT_EQ(right->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(right->as.integer_literal.value, 5);

    return true;
}

TEST_FUNC(Parser_CompoundAssignment_AllOperators) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* sources[] = {
        "a += 1", "a -= 1", "a *= 1", "a /= 1", "a %= 1",
        "a &= 1", "a |= 1", "a ^= 1", "a <<= 1", "a >>= 1"
    };

    TokenType expectedOps[] = {
        TOKEN_PLUS_EQUAL, TOKEN_MINUS_EQUAL, TOKEN_STAR_EQUAL,
        TOKEN_SLASH_EQUAL, TOKEN_PERCENT_EQUAL, TOKEN_AMPERSAND_EQUAL,
        TOKEN_PIPE_EQUAL, TOKEN_CARET_EQUAL, TOKEN_LARROW2_EQUAL,
        TOKEN_RARROW2_EQUAL
    };

    for (int i = 0; i < 10; ++i) {
        ParserTestContext ctx(sources[i], arena, interner);
        Parser* parser = ctx.getParser();
        ASTNode* expr = parser->parseExpression();
        ASSERT_TRUE(expr != NULL);
        ASSERT_EQ(expr->type, NODE_COMPOUND_ASSIGNMENT);
        ASSERT_EQ(expr->as.compound_assignment->op, expectedOps[i]);
    }

    return true;
}

TEST_FUNC(Parser_CompoundAssignment_RightAssociativity) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("a += b *= c", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* expr = parser->parseExpression();

    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_COMPOUND_ASSIGNMENT);
    ASSERT_EQ(expr->as.compound_assignment->op, TOKEN_PLUS_EQUAL);

    ASTNode* left = expr->as.compound_assignment->lvalue;
    ASSERT_EQ(left->type, NODE_IDENTIFIER);
    ASSERT_STREQ(left->as.identifier.name, "a");

    ASTNode* right = expr->as.compound_assignment->rvalue;
    ASSERT_EQ(right->type, NODE_COMPOUND_ASSIGNMENT);
    ASSERT_EQ(right->as.compound_assignment->op, TOKEN_STAR_EQUAL);
    ASSERT_STREQ(right->as.compound_assignment->lvalue->as.identifier.name, "b");
    ASSERT_STREQ(right->as.compound_assignment->rvalue->as.identifier.name, "c");

    return true;
}

TEST_FUNC(Parser_CompoundAssignment_ComplexRHS) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("x *= y + z * 2", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* expr = parser->parseExpression();

    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_COMPOUND_ASSIGNMENT);
    ASSERT_EQ(expr->as.compound_assignment->op, TOKEN_STAR_EQUAL);

    ASTNode* right = expr->as.compound_assignment->rvalue;
    ASSERT_EQ(right->type, NODE_BINARY_OP);
    ASSERT_EQ(right->as.binary_op->op, TOKEN_PLUS);

    return true;
}
