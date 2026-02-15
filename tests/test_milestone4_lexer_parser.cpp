#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/compilation_unit.hpp"
#include "../src/include/parser.hpp"
#include "../src/include/ast.hpp"

TEST_FUNC(Milestone4_Lexer_Tokens) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* source = "!i32 ?u8 error{A} E1 || E2 @import";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);

    // !
    Token t = parser->advance();
    ASSERT_EQ(TOKEN_BANG, t.type);
    // i32
    t = parser->advance();
    ASSERT_EQ(TOKEN_IDENTIFIER, t.type);

    // ?
    t = parser->advance();
    ASSERT_EQ(TOKEN_QUESTION, t.type);
    // u8
    t = parser->advance();
    ASSERT_EQ(TOKEN_IDENTIFIER, t.type);

    // error
    t = parser->advance();
    ASSERT_EQ(TOKEN_ERROR_SET, t.type);
    // {
    t = parser->advance();
    ASSERT_EQ(TOKEN_LBRACE, t.type);
    // A
    t = parser->advance();
    ASSERT_EQ(TOKEN_IDENTIFIER, t.type);
    // }
    t = parser->advance();
    ASSERT_EQ(TOKEN_RBRACE, t.type);

    // E1
    t = parser->advance();
    ASSERT_EQ(TOKEN_IDENTIFIER, t.type);
    // ||
    t = parser->advance();
    ASSERT_EQ(TOKEN_PIPE_PIPE, t.type);
    // E2
    t = parser->advance();
    ASSERT_EQ(TOKEN_IDENTIFIER, t.type);

    // @import
    t = parser->advance();
    ASSERT_EQ(TOKEN_AT_IMPORT, t.type);

    t = parser->peek();
    ASSERT_EQ(TOKEN_EOF, t.type);

    return true;
}

TEST_FUNC(Milestone4_Parser_AST) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    // Testing Error Union Type
    {
        u32 file_id = unit.addSource("type1.zig", "!i32");
        Parser* parser = unit.createParser(file_id);
        ASTNode* type = parser->parseType();
        ASSERT_EQ(NODE_ERROR_UNION_TYPE, type->type);
        ASSERT_TRUE(type->as.error_union_type->error_set == NULL);
        ASSERT_EQ(NODE_TYPE_NAME, type->as.error_union_type->payload_type->type);
    }

    // Testing Optional Type
    {
        u32 file_id = unit.addSource("type2.zig", "?i32");
        Parser* parser = unit.createParser(file_id);
        ASTNode* type = parser->parseType();
        ASSERT_EQ(NODE_OPTIONAL_TYPE, type->type);
        ASSERT_EQ(NODE_TYPE_NAME, type->as.optional_type->payload_type->type);
    }

    // Testing Error Set Merge
    {
        u32 file_id = unit.addSource("type3.zig", "E1 || E2");
        Parser* parser = unit.createParser(file_id);
        ASTNode* type = parser->parseType();
        ASSERT_EQ(NODE_ERROR_SET_MERGE, type->type);
        ASSERT_EQ(NODE_TYPE_NAME, type->as.error_set_merge->left->type);
        ASSERT_EQ(NODE_TYPE_NAME, type->as.error_set_merge->right->type);
    }

    return true;
}
