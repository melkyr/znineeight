#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "source_manager.hpp"
#include "string_interner.hpp"
#include "memory.hpp"

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

    return Parser(tokens.getData(), tokens.length(), &arena, &table);
}

TEST_FUNC(Parser_ParseEmptyBlock) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    Parser parser = create_parser_for_test("{}", arena, interner, sm);

    ASTNode* node = parser.parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 0);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithIfStatement) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    Parser parser = create_parser_for_test("{if (1) {}}", arena, interner, sm);

    ASTNode* node = parser.parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 1);

    ASTNode* if_stmt = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(if_stmt->type, NODE_IF_STMT);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithWhileStatement) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    Parser parser = create_parser_for_test("{while (1) {}}", arena, interner, sm);

    ASTNode* node = parser.parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 1);

    ASTNode* while_stmt = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(while_stmt->type, NODE_WHILE_STMT);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithMixedStatements) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    Parser parser = create_parser_for_test("{if (1) {} while (1) {}}", arena, interner, sm);

    ASTNode* node = parser.parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 2);

    ASTNode* if_stmt = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(if_stmt->type, NODE_IF_STMT);

    ASTNode* while_stmt = (*node->as.block_stmt.statements)[1];
    ASSERT_EQ(while_stmt->type, NODE_WHILE_STMT);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithEmptyStatement) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    Parser parser = create_parser_for_test("{;}", arena, interner, sm);

    ASTNode* node = parser.parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 1);

    ASTNode* stmt = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(stmt->type, NODE_EMPTY_STMT);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithMultipleEmptyStatements) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    Parser parser = create_parser_for_test("{;;}", arena, interner, sm);

    ASTNode* node = parser.parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 2);

    ASTNode* stmt1 = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(stmt1->type, NODE_EMPTY_STMT);

    ASTNode* stmt2 = (*node->as.block_stmt.statements)[1];
    ASSERT_EQ(stmt2->type, NODE_EMPTY_STMT);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithNestedEmptyBlock) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    Parser parser = create_parser_for_test("{{}}", arena, interner, sm);

    ASTNode* node = parser.parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 1);

    ASTNode* nested_block = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(nested_block->type, NODE_BLOCK_STMT);
    ASSERT_EQ(nested_block->as.block_stmt.statements->length(), 0);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithMultipleNestedEmptyBlocks) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    Parser parser = create_parser_for_test("{{}{}}", arena, interner, sm);

    ASTNode* node = parser.parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 2);

    ASTNode* nested_block1 = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(nested_block1->type, NODE_BLOCK_STMT);
    ASSERT_EQ(nested_block1->as.block_stmt.statements->length(), 0);

    ASTNode* nested_block2 = (*node->as.block_stmt.statements)[1];
    ASSERT_EQ(nested_block2->type, NODE_BLOCK_STMT);
    ASSERT_EQ(nested_block2->as.block_stmt.statements->length(), 0);

    return true;
}

TEST_FUNC(Parser_ParseBlockWithNestedBlockAndEmptyStatement) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    Parser parser = create_parser_for_test("{{};}", arena, interner, sm);

    ASTNode* node = parser.parseBlockStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_BLOCK_STMT);
    ASSERT_EQ(node->as.block_stmt.statements->length(), 2);

    ASTNode* nested_block = (*node->as.block_stmt.statements)[0];
    ASSERT_EQ(nested_block->type, NODE_BLOCK_STMT);
    ASSERT_EQ(nested_block->as.block_stmt.statements->length(), 0);

    ASTNode* empty_stmt = (*node->as.block_stmt.statements)[1];
    ASSERT_EQ(empty_stmt->type, NODE_EMPTY_STMT);

    return true;
}
