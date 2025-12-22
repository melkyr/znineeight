#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"

TEST_FUNC(Parser_ParseDeferStatement) {
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    const char* source = "defer {;}";
    ParserTestContext ctx(source, arena, interner);
    Parser& parser = ctx.getParser();
    ASTNode* stmt = parser.parseStatement();

    ASSERT_TRUE(stmt != NULL);
    ASSERT_EQ(stmt->type, NODE_DEFER_STMT);
    ASSERT_TRUE(stmt->as.defer_stmt.statement != NULL);
    ASSERT_EQ(stmt->as.defer_stmt.statement->type, NODE_BLOCK_STMT);

    return true;
}
