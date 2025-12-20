#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"
#include <cstdlib>

// Forward declaration for the test helper from test_parser_errors.cpp
bool expect_statement_parser_abort(const char* source);

#include "symbol_table.hpp"

// Helper to create a parser for a given source string
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

TEST_FUNC(Parser_ErrDeferStatement_Simple) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);

    const char* source = "errdefer {; }";
    Parser parser = create_parser_for_test(source, arena, interner, sm);

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
