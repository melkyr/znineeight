#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include <cstring> // For strlen in the helper

TEST_FUNC(Parser_StructDeclaration_Simple) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    ParserTestContext ctx("struct { x: i32 }", arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* node = parser->parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_STRUCT_DECL);

    ASTStructDeclNode* struct_decl = node->as.struct_decl;
    ASSERT_TRUE(struct_decl != NULL);
    ASSERT_EQ(struct_decl->fields->length(), 1);

    ASTNode* field_node = (*struct_decl->fields)[0];
    ASSERT_EQ(field_node->type, NODE_STRUCT_FIELD);

    ASTStructFieldNode* field = field_node->as.struct_field;
    ASSERT_STREQ(field->name, "x");

    ASSERT_TRUE(field->type != NULL);
    ASSERT_EQ(field->type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(field->type->as.type_name.name, "i32");

    return true;
}

TEST_FUNC(Parser_StructDeclaration_Empty) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    ParserTestContext ctx("struct {}", arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* node = parser->parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_STRUCT_DECL);

    ASTStructDeclNode* struct_decl = node->as.struct_decl;
    ASSERT_TRUE(struct_decl != NULL);
    ASSERT_EQ(struct_decl->fields->length(), 0);

    return true;
}

TEST_FUNC(Parser_StructDeclaration_MultipleFields) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    ParserTestContext ctx("struct { a: i32, b: bool, c: *u8 }", arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* node = parser->parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_STRUCT_DECL);

    ASTStructDeclNode* struct_decl = node->as.struct_decl;
    ASSERT_TRUE(struct_decl != NULL);
    ASSERT_EQ(struct_decl->fields->length(), 3);

    // Field 'a'
    ASTNode* field_node_a = (*struct_decl->fields)[0];
    ASSERT_EQ(field_node_a->type, NODE_STRUCT_FIELD);
    ASTStructFieldNode* field_a = field_node_a->as.struct_field;
    ASSERT_STREQ(field_a->name, "a");
    ASSERT_EQ(field_a->type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(field_a->type->as.type_name.name, "i32");

    // Field 'b'
    ASTNode* field_node_b = (*struct_decl->fields)[1];
    ASSERT_EQ(field_node_b->type, NODE_STRUCT_FIELD);
    ASTStructFieldNode* field_b = field_node_b->as.struct_field;
    ASSERT_STREQ(field_b->name, "b");
    ASSERT_EQ(field_b->type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(field_b->type->as.type_name.name, "bool");

    // Field 'c'
    ASTNode* field_node_c = (*struct_decl->fields)[2];
    ASSERT_EQ(field_node_c->type, NODE_STRUCT_FIELD);
    ASTStructFieldNode* field_c = field_node_c->as.struct_field;
    ASSERT_STREQ(field_c->name, "c");
    ASSERT_EQ(field_c->type->type, NODE_POINTER_TYPE);
    ASTNode* base_type = field_c->type->as.pointer_type.base;
    ASSERT_EQ(base_type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(base_type->as.type_name.name, "u8");

    return true;
}

TEST_FUNC(Parser_StructDeclaration_WithTrailingComma) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    ParserTestContext ctx("struct { x: i32, }", arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* node = parser->parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_STRUCT_DECL);
    ASTStructDeclNode* struct_decl = node->as.struct_decl;
    ASSERT_TRUE(struct_decl != NULL);
    ASSERT_EQ(struct_decl->fields->length(), 1);

    return true;
}

TEST_FUNC(Parser_StructDeclaration_ComplexFieldType) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    ParserTestContext ctx("struct { ptr: *[8]u8 }", arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* node = parser->parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_STRUCT_DECL);
    ASTStructDeclNode* struct_decl = node->as.struct_decl;
    ASSERT_EQ(struct_decl->fields->length(), 1);

    ASTNode* field_node = (*struct_decl->fields)[0];
    ASTStructFieldNode* field = field_node->as.struct_field;
    ASSERT_STREQ(field->name, "ptr");

    ASTNode* type = field->type;
    ASSERT_EQ(type->type, NODE_POINTER_TYPE);

    ASTNode* array_type = type->as.pointer_type.base;
    ASSERT_EQ(array_type->type, NODE_ARRAY_TYPE);

    ASSERT_TRUE(array_type->as.array_type.size != NULL);
    ASSERT_EQ(array_type->as.array_type.size->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(array_type->as.array_type.size->as.integer_literal.value, 8);

    ASSERT_EQ(array_type->as.array_type.element_type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(array_type->as.array_type.element_type->as.type_name.name, "u8");

    return true;
}
