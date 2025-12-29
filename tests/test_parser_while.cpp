#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"

// Helper function from test_parser_errors.cpp
bool expect_parser_abort(const char* source);

TEST_FUNC(Parser_While_ValidStatement) {
    const char* source = "while (1) {}";
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx(source, arena, interner);
    Parser parser = ctx.getParser();

    ASTNode* stmt = parser.parseWhileStatement();

    ASSERT_TRUE(stmt != NULL);
    ASSERT_TRUE(stmt->type == NODE_WHILE_STMT);

    ASTWhileStmtNode while_node = stmt->as.while_stmt;
    ASSERT_TRUE(while_node.condition != NULL);
    ASSERT_TRUE(while_node.condition->type == NODE_INTEGER_LITERAL);
    ASSERT_TRUE(while_node.body != NULL);
    ASSERT_TRUE(while_node.body->type == NODE_BLOCK_STMT);

    return true;
}

TEST_FUNC(Parser_While_MissingLParen) {
    ASSERT_TRUE(expect_parser_abort("while 1) {}"));
    return true;
}

TEST_FUNC(Parser_While_MissingRParen) {
    ASSERT_TRUE(expect_parser_abort("while (1 {}"));
    return true;
}

TEST_FUNC(Parser_While_MissingBody) {
    ASSERT_TRUE(expect_parser_abort("while (1)"));
    return true;
}
