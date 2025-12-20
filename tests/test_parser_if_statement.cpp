#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"

#include "symbol_table.hpp"

// Helper function to create a parser for a given source string
static Parser create_parser_for_test(const char* source, ArenaAllocator& arena, StringInterner& interner, SourceManager& sm) {
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);
    SymbolTable table(arena);

    DynamicArray<Token> tokens(arena);
    while (true) {
        Token token = lexer.nextToken();
        tokens.append(token);
        if (token.type == TOKEN_EOF) {
            break;
        }
    }

    return ParserBuilder(tokens.getData(), tokens.length(), &arena, &table).build();
}

TEST_FUNC(Parser_IfStatement_Simple) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    Parser parser = create_parser_for_test("if (1) {}", arena, interner, sm);

    ASTNode* if_stmt_node = parser.parseIfStatement();

    ASSERT_TRUE(if_stmt_node != NULL);
    ASSERT_EQ(if_stmt_node->type, NODE_IF_STMT);

    ASTIfStmtNode* if_stmt = if_stmt_node->as.if_stmt;
    ASSERT_TRUE(if_stmt->condition != NULL);
    ASSERT_EQ(if_stmt->condition->type, NODE_INTEGER_LITERAL);
    ASSERT_TRUE(if_stmt->then_block != NULL);
    ASSERT_EQ(if_stmt->then_block->type, NODE_BLOCK_STMT);
    ASSERT_TRUE(if_stmt->else_block == NULL);

    return true;
}

TEST_FUNC(Parser_IfStatement_WithElse) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    Parser parser = create_parser_for_test("if (1) {} else {}", arena, interner, sm);

    ASTNode* if_stmt_node = parser.parseIfStatement();

    ASSERT_TRUE(if_stmt_node != NULL);
    ASSERT_EQ(if_stmt_node->type, NODE_IF_STMT);

    ASTIfStmtNode* if_stmt = if_stmt_node->as.if_stmt;
    ASSERT_TRUE(if_stmt->condition != NULL);
    ASSERT_EQ(if_stmt->condition->type, NODE_INTEGER_LITERAL);
    ASSERT_TRUE(if_stmt->then_block != NULL);
    ASSERT_EQ(if_stmt->then_block->type, NODE_BLOCK_STMT);
    ASSERT_TRUE(if_stmt->else_block != NULL);
    ASSERT_EQ(if_stmt->else_block->type, NODE_BLOCK_STMT);

    return true;
}

TEST_FUNC(Parser_IfStatement_Error_MissingLParen) {
    ASSERT_TRUE(expect_parser_abort("if 1) {}"));
    return true;
}

TEST_FUNC(Parser_IfStatement_Error_MissingRParen) {
    ASSERT_TRUE(expect_parser_abort("if (1 {}"));
    return true;
}

TEST_FUNC(Parser_IfStatement_Error_MissingThenBlock) {
    ASSERT_TRUE(expect_parser_abort("if (1)"));
    return true;
}

TEST_FUNC(Parser_IfStatement_Error_MissingElseBlock) {
    ASSERT_TRUE(expect_parser_abort("if (1) {} else"));
    return true;
}
