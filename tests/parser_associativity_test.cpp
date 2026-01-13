#include "../src/include/test_framework.hpp"
#include "../src/include/parser.hpp"
#include "test_utils.hpp"

static bool is_orelse_expr(ASTNode* node) {
    return node != NULL && node->type == NODE_ORELSE_EXPR;
}

static bool is_catch_expr(ASTNode* node) {
    return node != NULL && node->type == NODE_CATCH_EXPR;
}

static bool is_identifier(ASTNode* node, const char* name) {
    return node != NULL && node->type == NODE_IDENTIFIER && strcmp(node->as.identifier.name, name) == 0;
}

// This test checks for (a orelse b) orelse c
TEST_FUNC(Parser_Orelse_IsLeftAssociative) {
    const char* source = "a orelse b orelse c";
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();

    ASTNode* root = parser->parseExpression();

    // Expected structure for left-associativity: ((a orelse b) orelse c)
    //              orelse
    //             /      \
    //        orelse       c
    //       /      \
    //      a        b

    ASSERT_TRUE(is_orelse_expr(root));
    ASSERT_TRUE(is_identifier(root->as.orelse_expr->else_expr, "c"));

    ASTNode* left_node = root->as.orelse_expr->payload;
    ASSERT_TRUE(is_orelse_expr(left_node));
    ASSERT_TRUE(is_identifier(left_node->as.orelse_expr->payload, "a"));
    ASSERT_TRUE(is_identifier(left_node->as.orelse_expr->else_expr, "b"));

    return true;
}

// This test checks for (a catch b) catch c
TEST_FUNC(Parser_Catch_IsLeftAssociative) {
    const char* source = "a catch b catch c";
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();

    ASTNode* root = parser->parseExpression();

    // Expected structure for left-associativity: ((a catch b) catch c)
    //                catch
    //               /     \
    //           catch      c
    //          /     \
    //         a       b

    ASSERT_TRUE(is_catch_expr(root));
    ASSERT_TRUE(is_identifier(root->as.catch_expr->else_expr, "c"));

    ASTNode* left_node = root->as.catch_expr->payload;
    ASSERT_TRUE(is_catch_expr(left_node));
    ASSERT_TRUE(is_identifier(left_node->as.catch_expr->payload, "a"));
    ASSERT_TRUE(is_identifier(left_node->as.catch_expr->else_expr, "b"));

    return true;
}
