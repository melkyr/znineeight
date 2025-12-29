#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"

// Helper function from test_parser_errors.cpp
bool expect_parser_abort(const char* source);

TEST_FUNC(Parser_For_ValidStatement_ItemOnly) {
    const char* source = "for (my_array) |item| {}";
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx(source, arena, interner);
    Parser parser = ctx.getParser();

    ASTNode* stmt = parser.parseStatement();

    ASSERT_TRUE(stmt != NULL);
    ASSERT_TRUE(stmt->type == NODE_FOR_STMT);

    ASTForStmtNode* for_node = stmt->as.for_stmt;
    ASSERT_TRUE(for_node->iterable_expr != NULL);
    ASSERT_TRUE(for_node->iterable_expr->type == NODE_IDENTIFIER);
    ASSERT_STREQ(for_node->iterable_expr->as.identifier.name, "my_array");
    ASSERT_STREQ(for_node->item_name, "item");
    ASSERT_TRUE(for_node->index_name == NULL);
    ASSERT_TRUE(for_node->body != NULL);
    ASSERT_TRUE(for_node->body->type == NODE_BLOCK_STMT);

    return true;
}

TEST_FUNC(Parser_For_ValidStatement_ItemAndIndex) {
    const char* source = "for (my_array) |item, index| {}";
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx(source, arena, interner);
    Parser parser = ctx.getParser();

    ASTNode* stmt = parser.parseStatement();

    ASSERT_TRUE(stmt != NULL);
    ASSERT_TRUE(stmt->type == NODE_FOR_STMT);

    ASTForStmtNode* for_node = stmt->as.for_stmt;
    ASSERT_TRUE(for_node->iterable_expr != NULL);
    ASSERT_TRUE(for_node->iterable_expr->type == NODE_IDENTIFIER);
    ASSERT_STREQ(for_node->iterable_expr->as.identifier.name, "my_array");
    ASSERT_STREQ(for_node->item_name, "item");
    ASSERT_STREQ(for_node->index_name, "index");
    ASSERT_TRUE(for_node->body != NULL);
    ASSERT_TRUE(for_node->body->type == NODE_BLOCK_STMT);

    return true;
}

TEST_FUNC(Parser_For_MissingLParen) {
    ASSERT_TRUE(expect_parser_abort("for my_array) |item| {}"));
    return true;
}

TEST_FUNC(Parser_For_MissingRParen) {
    ASSERT_TRUE(expect_parser_abort("for (my_array |item| {}"));
    return true;
}

TEST_FUNC(Parser_For_MissingInitialPipe) {
    ASSERT_TRUE(expect_parser_abort("for (my_array) item| {}"));
    return true;
}

TEST_FUNC(Parser_For_MissingClosingPipe) {
    ASSERT_TRUE(expect_parser_abort("for (my_array) |item {}"));
    return true;
}

TEST_FUNC(Parser_For_MissingItemIdentifier) {
    ASSERT_TRUE(expect_parser_abort("for (my_array) || {}"));
    return true;
}

TEST_FUNC(Parser_For_MissingIndexIdentifier) {
    ASSERT_TRUE(expect_parser_abort("for (my_array) |item, | {}"));
    return true;
}

TEST_FUNC(Parser_For_MissingBody) {
    ASSERT_TRUE(expect_parser_abort("for (my_array) |item, index|"));
    return true;
}

TEST_FUNC(Parser_For_WithComplexIterable) {
    const char* source = "for (get_array(1)) |item| {}";
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx(source, arena, interner);
    Parser parser = ctx.getParser();

    ASTNode* stmt = parser.parseStatement();

    ASSERT_TRUE(stmt != NULL);
    ASSERT_TRUE(stmt->type == NODE_FOR_STMT);

    ASTForStmtNode* for_node = stmt->as.for_stmt;
    ASSERT_TRUE(for_node->iterable_expr != NULL);
    ASSERT_TRUE(for_node->iterable_expr->type == NODE_FUNCTION_CALL);

    return true;
}
