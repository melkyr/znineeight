#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"

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

    return Parser(tokens.getData(), tokens.length(), &arena, &table);
}

TEST_FUNC(Parser_FnDecl_ValidEmpty) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);

    const char* source = "fn my_func() -> i32 {}";
    Parser parser = create_parser_for_test(source, arena, interner, sm);

    ASTNode* fn_decl_node = parser.parseFnDecl();

    ASSERT_TRUE(fn_decl_node != NULL);
    ASSERT_EQ(fn_decl_node->type, NODE_FN_DECL);

    ASTFnDeclNode* fn_decl = fn_decl_node->as.fn_decl;
    ASSERT_STREQ(fn_decl->name, "my_func");

    // Check for empty parameter list
    ASSERT_TRUE(fn_decl->params != NULL);
    ASSERT_EQ(fn_decl->params->length(), 0);

    // Check return type
    ASSERT_TRUE(fn_decl->return_type != NULL);
    ASSERT_EQ(fn_decl->return_type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(fn_decl->return_type->as.type_name.name, "i32");

    // Check for empty body
    ASSERT_TRUE(fn_decl->body != NULL);
    ASSERT_EQ(fn_decl->body->type, NODE_BLOCK_STMT);
    ASTBlockStmtNode block = fn_decl->body->as.block_stmt;
    ASSERT_TRUE(block.statements != NULL);
    ASSERT_EQ(block.statements->length(), 0);

    return true;
}

// Since the parser's error handling calls abort(), we need to run error tests
// in a separate process to verify the behavior without crashing the test runner.
// This is handled by the `expect_parser_abort` helper.

TEST_FUNC(Parser_FnDecl_Error_NonEmptyParams) {
    const char* source = "fn my_func(a: i32) -> i32 {}";
    ASSERT_TRUE(expect_parser_abort(source));
    return true;
}

TEST_FUNC(Parser_FnDecl_Error_NonEmptyBody) {
    const char* source = "fn my_func() -> i32 { var x = 1; }";
    ASSERT_TRUE(expect_parser_abort(source));
    return true;
}

TEST_FUNC(Parser_FnDecl_Error_MissingArrow) {
    const char* source = "fn my_func() i32 {}";
    ASSERT_TRUE(expect_parser_abort(source));
    return true;
}

TEST_FUNC(Parser_FnDecl_Error_MissingReturnType) {
    const char* source = "fn my_func() -> {}";
    ASSERT_TRUE(expect_parser_abort(source));
    return true;
}

TEST_FUNC(Parser_FnDecl_Error_MissingParens) {
    const char* source = "fn my_func -> i32 {}";
    ASSERT_TRUE(expect_parser_abort(source));
    return true;
}
