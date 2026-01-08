#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include <cstdlib>

// Forward declaration for the test helper from test_parser_errors.cpp
bool expect_statement_parser_abort(const char* source);

TEST_FUNC(Parser_ErrDeferStatement_Simple) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source = "errdefer {; }";
    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* stmt_node = parser.parseStatement();
    ASSERT_TRUE(stmt_node != NULL);
    ASSERT_EQ(stmt_node->type, NODE_ERRDEFER_STMT);

    ASTErrDeferStmtNode errdefer_stmt = stmt_node->as.errdefer_stmt;
    ASSERT_TRUE(errdefer_stmt.statement != NULL);
    ASSERT_EQ(errdefer_stmt.statement->type, NODE_BLOCK_STMT);

    // Check the body of the block statement
    ASTBlockStmtNode body = errdefer_stmt.statement->as.block_stmt;
    ASSERT_TRUE(body.statements != NULL);
    ASSERT_EQ(body.statements->length(), 1);
    ASSERT_EQ((*body.statements)[0]->type, NODE_EMPTY_STMT);

    ASSERT_TRUE(parser.is_at_end());

    return true;
}

TEST_FUNC(Parser_ErrDeferStatement_Error_MissingBlock) {
    ASSERT_TRUE(expect_statement_parser_abort("errdefer;"));
    ASSERT_TRUE(expect_statement_parser_abort("errdefer 123;"));
    return true;
}
