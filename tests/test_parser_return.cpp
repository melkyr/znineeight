#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include "ast.hpp"

TEST_FUNC(Parser_ReturnStatement_NoValue) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("return;", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* stmt = parser->parseStatement();
    ASSERT_TRUE(stmt != NULL);
    ASSERT_EQ(stmt->type, NODE_RETURN_STMT);

    ASTReturnStmtNode return_stmt = stmt->as.return_stmt;
    ASSERT_TRUE(return_stmt.expression == NULL);

    return true;
}

TEST_FUNC(Parser_ReturnStatement_WithValue) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("return 42;", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* stmt = parser->parseStatement();
    ASSERT_TRUE(stmt != NULL);
    ASSERT_EQ(stmt->type, NODE_RETURN_STMT);

    ASTReturnStmtNode return_stmt = stmt->as.return_stmt;
    ASSERT_TRUE(return_stmt.expression != NULL);
    ASSERT_EQ(return_stmt.expression->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(return_stmt.expression->as.integer_literal.value, 42);

    return true;
}
