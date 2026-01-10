#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include <cstring> // For strlen

// Helper function from test_parser_errors.cpp
bool expect_parser_abort(const char* source);

TEST_FUNC(Parser_Enum_Empty) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("enum {}", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ENUM_DECL);
    ASTEnumDeclNode* enum_decl = node->as.enum_decl;
    ASSERT_TRUE(enum_decl != NULL);
    ASSERT_TRUE(enum_decl->backing_type == NULL);
    ASSERT_EQ(enum_decl->fields->length(), 0);

    return true;
}

TEST_FUNC(Parser_Enum_SimpleMembers) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("enum { Red, Green, Blue }", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ENUM_DECL);
    ASTEnumDeclNode* enum_decl = node->as.enum_decl;
    ASSERT_TRUE(enum_decl != NULL);
    ASSERT_TRUE(enum_decl->backing_type == NULL);
    ASSERT_EQ(enum_decl->fields->length(), 3);

    // Check Red
    ASTNode* member1_node = (*enum_decl->fields)[0];
    ASSERT_EQ(member1_node->type, NODE_VAR_DECL);
    ASTVarDeclNode* member1 = member1_node->as.var_decl;
    ASSERT_STREQ(member1->name, "Red");
    ASSERT_TRUE(member1->type == NULL);
    ASSERT_TRUE(member1->initializer == NULL);

    // Check Blue
    ASTNode* member3_node = (*enum_decl->fields)[2];
    ASSERT_EQ(member3_node->type, NODE_VAR_DECL);
    ASTVarDeclNode* member3 = member3_node->as.var_decl;
    ASSERT_STREQ(member3->name, "Blue");
    ASSERT_TRUE(member3->initializer == NULL);

    return true;
}

TEST_FUNC(Parser_Enum_TrailingComma) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("enum { A, B, }", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parsePrimaryExpr();
    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ENUM_DECL);
    ASTEnumDeclNode* enum_decl = node->as.enum_decl;
    ASSERT_EQ(enum_decl->fields->length(), 2);
    ASTVarDeclNode* member2 = (*enum_decl->fields)[1]->as.var_decl;
    ASSERT_STREQ(member2->name, "B");

    return true;
}

TEST_FUNC(Parser_Enum_WithValues) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("enum { A = 1, B = 20 }", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ENUM_DECL);
    ASTEnumDeclNode* enum_decl = node->as.enum_decl;
    ASSERT_EQ(enum_decl->fields->length(), 2);

    // Check A
    ASTVarDeclNode* member1 = (*enum_decl->fields)[0]->as.var_decl;
    ASSERT_STREQ(member1->name, "A");
    ASSERT_TRUE(member1->initializer != NULL);
    ASSERT_EQ(member1->initializer->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(member1->initializer->as.integer_literal.value, 1);

    // Check B
    ASTVarDeclNode* member2 = (*enum_decl->fields)[1]->as.var_decl;
    ASSERT_STREQ(member2->name, "B");
    ASSERT_TRUE(member2->initializer != NULL);
    ASSERT_EQ(member2->initializer->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(member2->initializer->as.integer_literal.value, 20);

    return true;
}

TEST_FUNC(Parser_Enum_MixedMembers) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("enum { A, B = 10, C }", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ENUM_DECL);
    ASTEnumDeclNode* enum_decl = node->as.enum_decl;
    ASSERT_EQ(enum_decl->fields->length(), 3);

    // Check A (no initializer)
    ASTVarDeclNode* member1 = (*enum_decl->fields)[0]->as.var_decl;
    ASSERT_STREQ(member1->name, "A");
    ASSERT_TRUE(member1->initializer == NULL);

    // Check B (with initializer)
    ASTVarDeclNode* member2 = (*enum_decl->fields)[1]->as.var_decl;
    ASSERT_STREQ(member2->name, "B");
    ASSERT_TRUE(member2->initializer != NULL);

    // Check C (no initializer)
    ASTVarDeclNode* member3 = (*enum_decl->fields)[2]->as.var_decl;
    ASSERT_STREQ(member3->name, "C");
    ASSERT_TRUE(member3->initializer == NULL);

    return true;
}

TEST_FUNC(Parser_Enum_WithBackingType) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("enum(u8) { A, B }", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ENUM_DECL);
    ASTEnumDeclNode* enum_decl = node->as.enum_decl;
    ASSERT_TRUE(enum_decl->backing_type != NULL);
    ASSERT_EQ(enum_decl->backing_type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(enum_decl->backing_type->as.type_name.name, "u8");
    ASSERT_EQ(enum_decl->fields->length(), 2);

    return true;
}

// --- Error Handling Tests ---

TEST_FUNC(Parser_Enum_SyntaxError_MissingOpeningBrace) {
    return expect_parser_abort("enum");
}

TEST_FUNC(Parser_Enum_SyntaxError_MissingClosingBrace) {
    return expect_parser_abort("enum { A, B");
}

TEST_FUNC(Parser_Enum_SyntaxError_NoComma) {
    return expect_parser_abort("enum { A B }");
}

TEST_FUNC(Parser_Enum_SyntaxError_InvalidMember) {
    return expect_parser_abort("enum { 123 }");
}

TEST_FUNC(Parser_Enum_SyntaxError_MissingInitializer) {
    return expect_parser_abort("enum { A = }");
}

TEST_FUNC(Parser_Enum_SyntaxError_BackingTypeNoParens) {
    return expect_parser_abort("enum u8 { A }");
}

TEST_FUNC(Parser_Enum_ComplexInitializer) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("enum { A = 1 + 2 }", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_ENUM_DECL);
    ASTEnumDeclNode* enum_decl = node->as.enum_decl;
    ASSERT_EQ(enum_decl->fields->length(), 1);

    // Check A's initializer
    ASTVarDeclNode* member1 = (*enum_decl->fields)[0]->as.var_decl;
    ASSERT_STREQ(member1->name, "A");
    ASSERT_TRUE(member1->initializer != NULL);
    ASSERT_EQ(member1->initializer->type, NODE_BINARY_OP);

    ASTBinaryOpNode* bin_op = member1->initializer->as.binary_op;
    ASSERT_EQ(bin_op->op, TOKEN_PLUS);
    ASSERT_EQ(bin_op->left->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(bin_op->left->as.integer_literal.value, 1);
    ASSERT_EQ(bin_op->right->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(bin_op->right->as.integer_literal.value, 2);

    return true;
}
