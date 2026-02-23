#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"

// Forward declaration for helper function
bool expect_parser_abort(const char* source_code);

TEST_FUNC(Parser_Catch_WithBlock) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    ParserTestContext ctx("a catch |err| { return err; }", arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* expr = parser->parseExpression();

    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_CATCH_EXPR);

    ASTCatchExprNode* catch_node = expr->as.catch_expr;
    ASSERT_STREQ(catch_node->error_name, "err");
    ASSERT_EQ(catch_node->else_expr->type, NODE_BLOCK_STMT);

    return true;
}

TEST_FUNC(Parser_ErrorUnion_Return) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source = "fn fail() !i32 { return error.Bad; }";
    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* node = parser->parse();
    ASSERT_TRUE(node != NULL);
    return true;
}

TEST_FUNC(Parser_Try_Nested) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    ParserTestContext ctx("try try foo()", arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* expr = parser->parseExpression();

    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_TRY_EXPR);
    ASSERT_EQ(expr->as.try_expr.expression->type, NODE_TRY_EXPR);

    return true;
}

TEST_FUNC(Parser_Catch_Precedence_Arithmetic) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    // catch should have lower precedence than +
    // 1 + a catch b + 2  => (1 + a) catch (b + 2)
    ParserTestContext ctx("1 + a catch b + 2", arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* expr = parser->parseExpression();

    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_CATCH_EXPR);

    ASTCatchExprNode* catch_node = expr->as.catch_expr;
    ASSERT_EQ(catch_node->payload->type, NODE_BINARY_OP);
    ASSERT_EQ(catch_node->payload->as.binary_op->op, TOKEN_PLUS);

    ASSERT_EQ(catch_node->else_expr->type, NODE_BINARY_OP);
    ASSERT_EQ(catch_node->else_expr->as.binary_op->op, TOKEN_PLUS);

    return true;
}

TEST_FUNC(Parser_Try_Precedence_Arithmetic) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    // try should have higher precedence than + (unary)
    // try a + b => (try a) + b
    ParserTestContext ctx("try a + b", arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* expr = parser->parseExpression();

    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_BINARY_OP);
    ASSERT_EQ(expr->as.binary_op->op, TOKEN_PLUS);
    ASSERT_EQ(expr->as.binary_op->left->type, NODE_TRY_EXPR);

    return true;
}
