#include "test_framework.hpp"
#include "parser.hpp"
#include "string_interner.hpp"
#include "test_utils.hpp"

TEST_FUNC(Parser_ParseConstDecl_Simple) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("const x: i32 = 123;", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parseVarDecl();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_VAR_DECL);

    ASTVarDeclNode* var_decl = node->as.var_decl;
    ASSERT_TRUE(var_decl != NULL);
    ASSERT_TRUE(var_decl->is_const);
    ASSERT_TRUE(!var_decl->is_mut);
    ASSERT_STREQ(var_decl->name, "x");

    ASSERT_TRUE(var_decl->type != NULL);
    ASSERT_EQ(var_decl->type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(var_decl->type->as.type_name.name, "i32");

    ASSERT_TRUE(var_decl->initializer != NULL);
    ASSERT_EQ(var_decl->initializer->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(var_decl->initializer->as.integer_literal.value, 123);

    return true;
}

TEST_FUNC(Parser_ParseVarDecl_Simple) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("var y: u8 = 42;", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parseVarDecl();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_VAR_DECL);

    ASTVarDeclNode* var_decl = node->as.var_decl;
    ASSERT_TRUE(var_decl != NULL);
    ASSERT_TRUE(!var_decl->is_const);
    ASSERT_TRUE(var_decl->is_mut);
    ASSERT_STREQ(var_decl->name, "y");

    ASSERT_TRUE(var_decl->type != NULL);
    ASSERT_EQ(var_decl->type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(var_decl->type->as.type_name.name, "u8");

    ASSERT_TRUE(var_decl->initializer != NULL);
    ASSERT_EQ(var_decl->initializer->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(var_decl->initializer->as.integer_literal.value, 42);

    return true;
}

TEST_FUNC(Parser_ParseVarDecl_PointerType) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("var p: *i32 = 0;", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parseVarDecl();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_VAR_DECL);

    ASTVarDeclNode* var_decl = node->as.var_decl;
    ASSERT_TRUE(var_decl != NULL);
    ASSERT_STREQ(var_decl->name, "p");

    ASSERT_TRUE(var_decl->type != NULL);
    ASSERT_EQ(var_decl->type->type, NODE_POINTER_TYPE);

    ASTNode* base_type = var_decl->type->as.pointer_type.base;
    ASSERT_TRUE(base_type != NULL);
    ASSERT_EQ(base_type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(base_type->as.type_name.name, "i32");

    return true;
}

TEST_FUNC(Parser_ParseVarDecl_SliceType) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("const s: []u8 = 1;", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parseVarDecl();
    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_VAR_DECL);

    ASTVarDeclNode* var_decl = node->as.var_decl;
    ASSERT_TRUE(var_decl != NULL);
    ASSERT_STREQ(var_decl->name, "s");

    ASSERT_TRUE(var_decl->type != NULL);
    ASSERT_EQ(var_decl->type->type, NODE_ARRAY_TYPE);
    ASSERT_TRUE(var_decl->type->as.array_type.size == NULL);

    ASTNode* elem_type = var_decl->type->as.array_type.element_type;
    ASSERT_TRUE(elem_type != NULL);
    ASSERT_EQ(elem_type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(elem_type->as.type_name.name, "u8");

    return true;
}

TEST_FUNC(Parser_ParseVarDecl_FixedArrayType) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("var buf: [1024]u8 = 0;", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parseVarDecl();
    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_VAR_DECL);

    ASTVarDeclNode* var_decl = node->as.var_decl;
    ASSERT_TRUE(var_decl != NULL);
    ASSERT_STREQ(var_decl->name, "buf");

    ASSERT_TRUE(var_decl->type != NULL);
    ASSERT_EQ(var_decl->type->type, NODE_ARRAY_TYPE);

    ASTNode* size_node = var_decl->type->as.array_type.size;
    ASSERT_TRUE(size_node != NULL);
    ASSERT_EQ(size_node->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(size_node->as.integer_literal.value, 1024);

    return true;
}
