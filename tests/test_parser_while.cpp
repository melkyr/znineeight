#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"

#include "symbol_table.hpp"

// Helper to create a parser instance.
static Parser create_parser_for_test(const char* source, ArenaAllocator& arena, StringInterner& interner) {
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);
    SymbolTable table(arena);

    DynamicArray<Token> tokens(arena);
    while(true) {
        Token token = lexer.nextToken();
        tokens.append(token);
        if (token.type == TOKEN_EOF) {
            break;
        }
    }
    return Parser(tokens.getData(), tokens.length(), &arena, &table);
}

TEST_FUNC(Parser_While_ValidStatement) {
    const char* source = "while (1) {}";
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test(source, arena, interner);

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
