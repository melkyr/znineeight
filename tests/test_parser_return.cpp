#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"
#include "ast.hpp"

#include "symbol_table.hpp"

// Helper function to create a parser instance for a given source string.
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

TEST_FUNC(Parser_ReturnStatement_NoValue) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager source_manager(arena);
    Parser parser = create_parser_for_test("return;", arena, interner, source_manager);

    ASTNode* stmt = parser.parseStatement();
    ASSERT_TRUE(stmt != NULL);
    ASSERT_EQ(stmt->type, NODE_RETURN_STMT);

    ASTReturnStmtNode return_stmt = stmt->as.return_stmt;
    ASSERT_TRUE(return_stmt.expression == NULL);

    return true;
}

TEST_FUNC(Parser_ReturnStatement_WithValue) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager source_manager(arena);
    Parser parser = create_parser_for_test("return 42;", arena, interner, source_manager);

    ASTNode* stmt = parser.parseStatement();
    ASSERT_TRUE(stmt != NULL);
    ASSERT_EQ(stmt->type, NODE_RETURN_STMT);

    ASTReturnStmtNode return_stmt = stmt->as.return_stmt;
    ASSERT_TRUE(return_stmt.expression != NULL);
    ASSERT_EQ(return_stmt.expression->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(return_stmt.expression->as.integer_literal.value, 42);

    return true;
}
