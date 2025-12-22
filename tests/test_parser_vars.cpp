#include "test_framework.hpp"
#include "lexer.hpp"
#include "parser.hpp"
#include "memory.hpp"
#include "string_interner.hpp"

// Helper function to set up a parser for a given source string
static Parser create_parser_for_test(const char* source, ArenaAllocator& arena, StringInterner& interner) {
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);

    DynamicArray<Token> tokens(arena);
    Token token;
    do {
        token = lexer.nextToken();
        tokens.append(token);
    } while (token.type != TOKEN_EOF);

    return Parser(tokens.getData(), tokens.length(), &arena);
}

TEST_FUNC(Parser_ParseConstDecl_Simple) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("const x: i32 = 123;", arena, interner);

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
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("var y: u8 = 42;", arena, interner);

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
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("var p: *i32 = 0;", arena, interner);

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
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("const s: []u8 = 1;", arena, interner);

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
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("var buf: [1024]u8 = 0;", arena, interner);

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
