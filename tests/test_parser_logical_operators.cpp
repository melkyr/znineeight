#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include <cstdlib> // For abort
#include <new>     // For placement new

// Helper function from test_parser_errors.cpp
bool expect_parser_abort(const char* source);

// --- Test Helper Functions ---

static bool verify_binary_op(ASTNode* node, TokenType op, const char* left_name, const char* right_name) {
    ASSERT_TRUE(node->type == NODE_BINARY_OP);
    ASSERT_TRUE(node->as.binary_op->op == op);
    ASSERT_TRUE(node->as.binary_op->left->type == NODE_IDENTIFIER);
    ASSERT_STREQ(node->as.binary_op->left->as.identifier.name, left_name);
    ASSERT_TRUE(node->as.binary_op->right->type == NODE_IDENTIFIER);
    ASSERT_STREQ(node->as.binary_op->right->as.identifier.name, right_name);
    return true;
}

// --- Test Cases ---

TEST_FUNC(Parser_Logical_AndHasHigherPrecedenceThanOr) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("a and b or c", arena, interner);
    Parser& parser = ctx.getParser();

    ASTNode* expr = parser.parseExpression();

    // Expected: (a and b) or c
    ASSERT_TRUE(expr->type == NODE_BINARY_OP);
    ASSERT_TRUE(expr->as.binary_op->op == TOKEN_OR);

    ASTNode* left_of_or = expr->as.binary_op->left;
    verify_binary_op(left_of_or, TOKEN_AND, "a", "b");

    ASSERT_TRUE(expr->as.binary_op->right->type == NODE_IDENTIFIER);
    ASSERT_STREQ(expr->as.binary_op->right->as.identifier.name, "c");

    return true;
}

TEST_FUNC(Parser_Logical_AndBindsTighterThanOr) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("a or b and c", arena, interner);
    Parser& parser = ctx.getParser();

    ASTNode* expr = parser.parseExpression();

    // Expected: a or (b and c)
    ASSERT_TRUE(expr->type == NODE_BINARY_OP);
    ASSERT_TRUE(expr->as.binary_op->op == TOKEN_OR);

    ASSERT_TRUE(expr->as.binary_op->left->type == NODE_IDENTIFIER);
    ASSERT_STREQ(expr->as.binary_op->left->as.identifier.name, "a");

    ASTNode* right_of_or = expr->as.binary_op->right;
    verify_binary_op(right_of_or, TOKEN_AND, "b", "c");

    return true;
}

TEST_FUNC(Parser_Logical_OrHasHigherPrecedenceThanOrElse) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("x orelse y or z", arena, interner);
    Parser& parser = ctx.getParser();

    ASTNode* expr = parser.parseExpression();

    // Expected: x orelse (y or z)
    ASSERT_TRUE(expr->type == NODE_BINARY_OP);
    ASSERT_TRUE(expr->as.binary_op->op == TOKEN_ORELSE);

    ASSERT_TRUE(expr->as.binary_op->left->type == NODE_IDENTIFIER);
    ASSERT_STREQ(expr->as.binary_op->left->as.identifier.name, "x");

    ASTNode* right_of_orelse = expr->as.binary_op->right;
    verify_binary_op(right_of_orelse, TOKEN_OR, "y", "z");

    return true;
}

TEST_FUNC(Parser_Logical_AndIsLeftAssociative) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("a and b and c", arena, interner);
    Parser& parser = ctx.getParser();

    ASTNode* expr = parser.parseExpression();

    // Expected: ((a and b) and c)
    ASSERT_TRUE(expr->type == NODE_BINARY_OP);
    ASSERT_TRUE(expr->as.binary_op->op == TOKEN_AND);

    ASTNode* left_of_and = expr->as.binary_op->left;
    verify_binary_op(left_of_and, TOKEN_AND, "a", "b");

    ASSERT_TRUE(expr->as.binary_op->right->type == NODE_IDENTIFIER);
    ASSERT_STREQ(expr->as.binary_op->right->as.identifier.name, "c");

    return true;
}

TEST_FUNC(Parser_Logical_OrElseIsRightAssociative) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("a orelse b orelse c", arena, interner);
    Parser& parser = ctx.getParser();

    ASTNode* expr = parser.parseExpression();

    // Expected: (a orelse (b orelse c))
    ASSERT_TRUE(expr->type == NODE_BINARY_OP);
    ASSERT_TRUE(expr->as.binary_op->op == TOKEN_ORELSE);

    ASSERT_TRUE(expr->as.binary_op->left->type == NODE_IDENTIFIER);
    ASSERT_STREQ(expr->as.binary_op->left->as.identifier.name, "a");

    ASTNode* right_of_orelse = expr->as.binary_op->right;
    verify_binary_op(right_of_orelse, TOKEN_ORELSE, "b", "c");

    return true;
}

TEST_FUNC(Parser_Logical_ComplexPrecedence) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("flag and val orelse default", arena, interner);
    Parser& parser = ctx.getParser();

    ASTNode* expr = parser.parseExpression();

    // Expected: (flag and val) orelse default
    ASSERT_TRUE(expr->type == NODE_BINARY_OP);
    ASSERT_TRUE(expr->as.binary_op->op == TOKEN_ORELSE);

    ASTNode* left_of_orelse = expr->as.binary_op->left;
    verify_binary_op(left_of_orelse, TOKEN_AND, "flag", "val");

    ASSERT_TRUE(expr->as.binary_op->right->type == NODE_IDENTIFIER);
    ASSERT_STREQ(expr->as.binary_op->right->as.identifier.name, "default");

    return true;
}

// --- Error Cases ---

TEST_FUNC(Parser_Logical_ErrorOnMissingRHS) {
    ASSERT_TRUE(expect_parser_abort("a orelse"));
    return true;
}

TEST_FUNC(Parser_Logical_ErrorOnMissingLHS) {
    ASSERT_TRUE(expect_parser_abort("and b"));
    return true;
}

TEST_FUNC(Parser_Logical_ErrorOnConsecutiveOperators) {
    ASSERT_TRUE(expect_parser_abort("a or or b"));
    return true;
}
