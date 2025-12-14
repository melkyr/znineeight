#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"

TEST_FUNC(ParserRefactor_KeepsExistingFunctionality) {
    // This test acts as a safeguard to ensure that the refactoring of
    // parser.cpp (removing duplicate functions, etc.) does not break
    // the existing, tested functionality of parseVarDecl.

    const char* source = "var test_var: i32 = 123;";
    const char* filename = "test_parser_refactor.zig";

    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);

    u32 file_id = sm.addFile(filename, source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);

    // Collect all tokens from the lexer.
    DynamicArray<Token> tokens(arena);
    for (;;) {
        Token token = lexer.nextToken();
        tokens.append(token);
        if (token.type == TOKEN_EOF) {
            break;
        }
    }

    Parser parser(tokens.getData(), tokens.length(), &arena);
    ASTNode* var_decl_node = parser.parseVarDecl();

    ASSERT_TRUE(var_decl_node != NULL);
    ASSERT_EQ(NODE_VAR_DECL, var_decl_node->type);

    return true;
}
