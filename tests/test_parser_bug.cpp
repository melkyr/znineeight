#include "test_utils.hpp"
#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include <new>
#include <cstring>

TEST_FUNC(ParserBug_LogicalOperatorSymbol) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source = "const x: bool = a and b;";
    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseVarDecl();

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

TEST_FUNC(ParserBug_TopLevelStruct) {
    const char* source = "struct {};";
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parse();

    ASSERT_TRUE(node != NULL);
    ASSERT_TRUE(node->type == NODE_BLOCK_STMT);

    ASTBlockStmtNode* block = &node->as.block_stmt;
    ASSERT_TRUE(block->statements->length() == 1);

    ASTNode* struct_node = (*block->statements)[0];
    ASSERT_TRUE(struct_node != NULL);
    ASSERT_TRUE(struct_node->type == NODE_STRUCT_DECL);

    return true;
}

TEST_FUNC(ParserBug_UnionFieldNodeType) {
    const char* source = "union { a: i32, };";
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parse();
    ASTBlockStmtNode* block = &node->as.block_stmt;
    ASTNode* union_node = (*block->statements)[0];
    ASTUnionDeclNode* union_decl = union_node->as.union_decl;

    ASSERT_TRUE(union_decl->fields->length() == 1);
    ASTNode* field_node = (*union_decl->fields)[0];
    ASSERT_TRUE(field_node->type == NODE_STRUCT_FIELD);

    return true;
}

TEST_FUNC(ParserBug_TopLevelUnion) {
    const char* source = "union {};";
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parse();

    ASSERT_TRUE(node != NULL);
    ASSERT_TRUE(node->type == NODE_BLOCK_STMT);

    ASTBlockStmtNode* block = &node->as.block_stmt;
    ASSERT_TRUE(block->statements->length() == 1);

    ASTNode* union_node = (*block->statements)[0];
    ASSERT_TRUE(union_node != NULL);
    ASSERT_TRUE(union_node->type == NODE_UNION_DECL);

    return true;
}
