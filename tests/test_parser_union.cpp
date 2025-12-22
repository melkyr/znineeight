#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include <cstring> // For strlen

// Helper function to create a parser instance for a given source string.
// This is a common setup for parser tests.
static Parser create_parser_for_test(const char* source, ArenaAllocator& arena, StringInterner& interner) {
    SourceManager src_manager(arena);
    u32 file_id = src_manager.addFile("test.zig", source, strlen(source));

    Lexer lexer(src_manager, interner, arena, file_id);
    DynamicArray<Token> tokens(arena);
    while (true) {
        Token token = lexer.nextToken();
        tokens.append(token);
        if (token.type == TOKEN_EOF) {
            break;
        }
    }
    return Parser(tokens.getData(), tokens.length(), &arena);
}

TEST_FUNC(Parser_ParseUnionDeclaration_Empty) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("union {}", arena, interner);

    ASTNode* node = parser.parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_UNION_DECL);

    ASTUnionDeclNode* union_decl = node->as.union_decl;
    ASSERT_TRUE(union_decl != NULL);
    ASSERT_EQ(union_decl->fields->length(), 0);

    return true;
}

TEST_FUNC(Parser_ParseUnionDeclaration_WithFields) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("union { a: i32, b: bool }", arena, interner);

    ASTNode* node = parser.parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_UNION_DECL);

    ASTUnionDeclNode* union_decl = node->as.union_decl;
    ASSERT_TRUE(union_decl != NULL);
    ASSERT_EQ(union_decl->fields->length(), 2);

    // Field 1: a: i32
    ASTNode* field1_node = (*union_decl->fields)[0];
    ASSERT_EQ(field1_node->type, NODE_STRUCT_FIELD);
    ASTStructFieldNode* field1 = field1_node->as.struct_field;
    ASSERT_STREQ(field1->name, "a");
    ASSERT_EQ(field1->type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(field1->type->as.type_name.name, "i32");

    // Field 2: b: bool
    ASTNode* field2_node = (*union_decl->fields)[1];
    ASSERT_EQ(field2_node->type, NODE_STRUCT_FIELD);
    ASTStructFieldNode* field2 = field2_node->as.struct_field;
    ASSERT_STREQ(field2->name, "b");
    ASSERT_EQ(field2->type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(field2->type->as.type_name.name, "bool");

    return true;
}

// The expect_parser_abort function is defined in test_parser_errors.cpp
// and declared in test_framework.hpp. We just need to call it.

TEST_FUNC(Parser_Union_Error_MissingLBrace) {
    ASSERT_TRUE(expect_parser_abort("union"));
    return true;
}

TEST_FUNC(Parser_Union_Error_MissingRBrace) {
    ASSERT_TRUE(expect_parser_abort("union {"));
    return true;
}

TEST_FUNC(Parser_Union_Error_MissingColon) {
    ASSERT_TRUE(expect_parser_abort("union { a i32 }"));
    return true;
}

TEST_FUNC(Parser_Union_Error_MissingType) {
    ASSERT_TRUE(expect_parser_abort("union { a : }"));
    return true;
}

TEST_FUNC(Parser_Union_Error_InvalidField) {
    ASSERT_TRUE(expect_parser_abort("union { 123 }"));
    return true;
}
