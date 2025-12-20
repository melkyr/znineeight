#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"

#include <new>
#include <cstring>

#include "symbol_table.hpp"

// Helper function to set up the parser for a given source string
static Parser create_parser_for_test(const char* source, ArenaAllocator& arena, StringInterner& interner, SourceManager& sm, DynamicArray<Token>& tokens) {
    u32 file_id = sm.addFile("test_bug.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);
    SymbolTable table(arena);

    while (true) {
        Token token = lexer.nextToken();
        tokens.append(token);
        if (token.type == TOKEN_EOF) {
            break;
        }
    }

    return Parser(tokens.getData(), tokens.length(), &arena, &table);
}

TEST_FUNC(ParserBug_LogicalOperatorSymbol) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    DynamicArray<Token> tokens(arena);

    const char* source = "const x: bool = a && b;";
    Parser parser = create_parser_for_test(source, arena, interner, sm, tokens);

    ASTNode* node = parser.parseVarDecl();

    // The parser should crash before this point, but if it doesn't, these assertions will fail.
    ASSERT_TRUE(node != NULL);
    ASTVarDeclNode* var_decl = node->as.var_decl;
    ASTNode* initializer = var_decl->initializer;
    ASSERT_TRUE(initializer != NULL);

    // The core of the bug: The parser will likely create a bitwise AND, not a logical AND.
    // Or it might fail to parse the expression altogether.
    ASSERT_TRUE(initializer->type == NODE_BINARY_OP);

    ASTBinaryOpNode* bin_op = initializer->as.binary_op;
    ASSERT_TRUE(bin_op->op == TOKEN_AND);

    return true;
}
