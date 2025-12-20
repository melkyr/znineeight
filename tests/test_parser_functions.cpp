#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"

#include "symbol_table.hpp"

// Helper function to set up a parser for a given source string
static Parser create_parser_for_test(const char* source, ArenaAllocator& arena, StringInterner& interner, SourceManager& sm) {
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);
    SymbolTable table(arena);

    DynamicArray<Token> tokens(arena);
    Token token;
    do {
        token = lexer.nextToken();
        tokens.append(token);
    } while (token.type != TOKEN_EOF);

    return ParserBuilder(tokens.getData(), tokens.length(), &arena, &table).build();
}

TEST_FUNC(Parser_NonEmptyFunctionBody) {
    ArenaAllocator arena(1024 * 1024); // 1MB arena
    StringInterner interner(arena);
    SourceManager sm(arena);

    const char* source =
        "fn main() -> i32 {\n"
        "    const x: i32 = 42;\n"
        "    if (x == 42) {\n"
        "        return 0;\n"
        "    }\n"
        "    return 1;\n"
        "}";

    Parser parser = create_parser_for_test(source, arena, interner, sm);
    ASTNode* decl = parser.parseFnDecl();

    // Verify the function declaration itself
    ASSERT_TRUE(decl != NULL);
    ASSERT_EQ(decl->type, NODE_FN_DECL);

    ASTFnDeclNode* fn_decl = decl->as.fn_decl;
    ASSERT_STREQ(fn_decl->name, "main");
    ASSERT_TRUE(fn_decl->return_type != NULL);
    ASSERT_EQ(fn_decl->return_type->type, NODE_TYPE_NAME);

    // Verify the function body
    ASSERT_TRUE(fn_decl->body != NULL);
    ASSERT_EQ(fn_decl->body->type, NODE_BLOCK_STMT);

    ASTBlockStmtNode* body_block = &fn_decl->body->as.block_stmt;
    ASSERT_EQ(body_block->statements->length(), 3);

    // Statement 1: const x: i32 = 42;
    ASTNode* var_decl_stmt = (*body_block->statements)[0];
    ASSERT_EQ(var_decl_stmt->type, NODE_VAR_DECL);
    ASTVarDeclNode* var_decl = var_decl_stmt->as.var_decl;
    ASSERT_TRUE(var_decl->is_const);
    ASSERT_STREQ(var_decl->name, "x");
    ASSERT_EQ(var_decl->initializer->as.integer_literal.value, 42);

    // Statement 2: if (x == 42) { ... }
    ASTNode* if_stmt_node = (*body_block->statements)[1];
    ASSERT_EQ(if_stmt_node->type, NODE_IF_STMT);
    ASTIfStmtNode* if_stmt = if_stmt_node->as.if_stmt;
    ASSERT_EQ(if_stmt->condition->type, NODE_BINARY_OP);
    ASSERT_TRUE(if_stmt->then_block != NULL);
    ASSERT_TRUE(if_stmt->else_block == NULL);

    // Statement 3: return 1;
    ASTNode* return_stmt = (*body_block->statements)[2];
    ASSERT_EQ(return_stmt->type, NODE_RETURN_STMT);
    ASSERT_EQ(return_stmt->as.return_stmt.expression->as.integer_literal.value, 1);

    return true;
}
