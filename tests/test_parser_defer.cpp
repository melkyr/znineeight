#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"

TEST_FUNC(Parser_ParseDeferStatement) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager src_manager(arena);
    const char* source = "defer {;}";
    u32 file_id = src_manager.addFile("test.zig", source, strlen(source));

    Lexer lexer(src_manager, interner, arena, file_id);
    DynamicArray<Token> tokens(arena);
    while(true) {
        Token token = lexer.nextToken();
        tokens.append(token);
        if (token.type == TOKEN_EOF) {
            break;
        }
    }

    Parser parser(tokens.getData(), tokens.length(), &arena);
    ASTNode* stmt = parser.parseStatement();

    ASSERT_TRUE(stmt != NULL);
    ASSERT_EQ(stmt->type, NODE_DEFER_STMT);
    ASSERT_TRUE(stmt->as.defer_stmt.statement != NULL);
    ASSERT_EQ(stmt->as.defer_stmt.statement->type, NODE_BLOCK_STMT);

    return true;
}
