#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"

// Helper to create a parser instance.
static Parser create_parser_for_test(const char* source, ArenaAllocator& arena, StringInterner& interner) {
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);

    DynamicArray<Token> tokens(arena);
    while(true) {
        Token token = lexer.nextToken();
        tokens.append(token);
        if (token.type == TOKEN_EOF) {
            break;
        }
    }
    return Parser(tokens.getData(), tokens.length(), &arena);
}

TEST_FUNC(Parser_For_ValidStatement_ItemOnly) {
    const char* source = "for (my_array) |item| {}";
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test(source, arena, interner);

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
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test(source, arena, interner);

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
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test(source, arena, interner);

    ASTNode* stmt = parser.parseStatement();

    ASSERT_TRUE(stmt != NULL);
    ASSERT_TRUE(stmt->type == NODE_FOR_STMT);

    ASTForStmtNode* for_node = stmt->as.for_stmt;
    ASSERT_TRUE(for_node->iterable_expr != NULL);
    ASSERT_TRUE(for_node->iterable_expr->type == NODE_FUNCTION_CALL);

    return true;
}
