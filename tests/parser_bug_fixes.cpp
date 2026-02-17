#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"

TEST_FUNC(Parser_Bugfix_HandlesExpressionStatement) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    // This code uses the simplest possible expression statement.
    // The parser should handle it without crashing.
    ParserTestContext ctx("fn my_func() void { 42; }", arena, interner);
    Parser* parser = ctx.getParser();

    // The bug causes the parser to abort here.
    ASTNode* node = parser->parse();

    // Basic validation to ensure the AST looks correct.
    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);

    // Expecting one top-level statement (the function declaration)
    ASSERT_EQ(node->as.block_stmt.statements->length(), 1);

    ASTNode* fn_decl = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(fn_decl->type, NODE_FN_DECL);

    ASTNode* fn_body = fn_decl->as.fn_decl->body;
    ASSERT_EQ(fn_body->type, NODE_BLOCK_STMT);

    // Expecting one statement inside the function body
    ASSERT_EQ(fn_body->as.block_stmt.statements->length(), 1);

    // That statement should be an EXPRESSION_STMT
    ASTNode* expr_stmt = (*fn_body->as.block_stmt.statements)[0];
    ASSERT_EQ(expr_stmt->type, NODE_EXPRESSION_STMT);

    // And its child should be an INTEGER_LITERAL
    ASTNode* literal = expr_stmt->as.expression_stmt.expression;
    ASSERT_EQ(literal->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(literal->as.integer_literal.value, 42);

    return true;
}
