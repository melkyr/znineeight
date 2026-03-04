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

// This test checks for a orelse (b orelse c)
TEST_FUNC(Parser_Orelse_IsRightAssociative) {
    const char* source = "a orelse b orelse c";
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();

    ASTNode* root = parser->parseExpression();

    // Expected structure for right-associativity: (a orelse (b orelse c))
    //              orelse
    //             /      \
    //            a      orelse
    //                  /      \
    //                 b        c

    ASSERT_TRUE(is_orelse_expr(root));
    ASSERT_TRUE(is_identifier(root->as.orelse_expr->payload, "a"));

    ASTNode* right_node = root->as.orelse_expr->else_expr;
    ASSERT_TRUE(is_orelse_expr(right_node));
    ASSERT_TRUE(is_identifier(right_node->as.orelse_expr->payload, "b"));
    ASSERT_TRUE(is_identifier(right_node->as.orelse_expr->else_expr, "c"));

    return true;
}

// This test checks for a catch (b catch c)
TEST_FUNC(Parser_Catch_IsRightAssociative) {
    const char* source = "a catch b catch c";
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();

    ASTNode* root = parser->parseExpression();

    // Expected structure for right-associativity: (a catch (b catch c))
    //                catch
    //               /     \
    //              a      catch
    //                    /     \
    //                   b       c

    ASSERT_TRUE(is_catch_expr(root));
    ASSERT_TRUE(is_identifier(root->as.catch_expr->payload, "a"));

    ASTNode* right_node = root->as.catch_expr->else_expr;
    ASSERT_TRUE(is_catch_expr(right_node));
    ASSERT_TRUE(is_identifier(right_node->as.catch_expr->payload, "b"));
    ASSERT_TRUE(is_identifier(right_node->as.catch_expr->else_expr, "c"));

    return true;
}

// Mixed catch and orelse: a catch b orelse c -> a catch (b orelse c)
TEST_FUNC(Parser_CatchOrelse_IsRightAssociative) {
    const char* source = "a catch b orelse c";
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();

    ASTNode* root = parser->parseExpression();

    // Expected: (a catch (b orelse c))
    ASSERT_TRUE(is_catch_expr(root));
    ASSERT_TRUE(is_identifier(root->as.catch_expr->payload, "a"));

    ASTNode* right_node = root->as.catch_expr->else_expr;
    ASSERT_TRUE(is_orelse_expr(right_node));
    ASSERT_TRUE(is_identifier(right_node->as.orelse_expr->payload, "b"));
    ASSERT_TRUE(is_identifier(right_node->as.orelse_expr->else_expr, "c"));

    return true;
}
