#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"

TEST_FUNC(Parser_FunctionType_Basic) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source = "const fp: fn(i32) void = undefined;";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* decl = parser->parseVarDecl();

    ASSERT_TRUE(decl != NULL);
    ASSERT_EQ(decl->type, NODE_VAR_DECL);

    ASTVarDeclNode* var_decl = decl->as.var_decl;
    ASSERT_STREQ(var_decl->name, "fp");
    ASSERT_TRUE(var_decl->type != NULL);
    ASSERT_EQ(var_decl->type->type, NODE_FUNCTION_TYPE);

    ASTFunctionTypeNode* fn_type = var_decl->type->as.function_type;
    ASSERT_TRUE(fn_type != NULL);
    ASSERT_TRUE(fn_type->params != NULL);
    ASSERT_EQ(fn_type->params->length(), 1);
    ASSERT_EQ((*fn_type->params)[0]->type, NODE_TYPE_NAME);
    ASSERT_STREQ((*fn_type->params)[0]->as.type_name.name, "i32");

    ASSERT_TRUE(fn_type->return_type != NULL);
    ASSERT_EQ(fn_type->return_type->type, NODE_TYPE_NAME);
    ASSERT_STREQ(fn_type->return_type->as.type_name.name, "void");

    return true;
}

TEST_FUNC(Parser_FunctionType_MultipleParams) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source = "const fp: fn(i32, bool, *u8) f64 = undefined;";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* decl = parser->parseVarDecl();

    ASSERT_TRUE(decl != NULL);
    ASTVarDeclNode* var_decl = decl->as.var_decl;
    ASTFunctionTypeNode* fn_type = var_decl->type->as.function_type;

    ASSERT_EQ(fn_type->params->length(), 3);
    ASSERT_STREQ((*fn_type->params)[0]->as.type_name.name, "i32");
    ASSERT_STREQ((*fn_type->params)[1]->as.type_name.name, "bool");
    ASSERT_EQ((*fn_type->params)[2]->type, NODE_POINTER_TYPE);

    ASSERT_STREQ(fn_type->return_type->as.type_name.name, "f64");

    return true;
}

TEST_FUNC(Parser_FunctionType_Nested) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    // Function returning a function pointer
    const char* source = "const fp: fn(i32) fn() void = undefined;";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* decl = parser->parseVarDecl();

    ASSERT_TRUE(decl != NULL);
    ASTVarDeclNode* var_decl = decl->as.var_decl;
    ASTFunctionTypeNode* fn_type = var_decl->type->as.function_type;

    ASSERT_EQ(fn_type->params->length(), 1);
    ASSERT_EQ(fn_type->return_type->type, NODE_FUNCTION_TYPE);

    ASTFunctionTypeNode* inner_fn_type = fn_type->return_type->as.function_type;
    ASSERT_EQ(inner_fn_type->params->length(), 0);
    ASSERT_STREQ(inner_fn_type->return_type->as.type_name.name, "void");

    return true;
}

TEST_FUNC(Parser_FunctionType_TrailingComma) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source = "const fp: fn(i32, ) void = undefined;";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* decl = parser->parseVarDecl();

    ASSERT_TRUE(decl != NULL);
    ASTVarDeclNode* var_decl = decl->as.var_decl;
    ASTFunctionTypeNode* fn_type = var_decl->type->as.function_type;

    ASSERT_EQ(fn_type->params->length(), 1);
    ASSERT_STREQ((*fn_type->params)[0]->as.type_name.name, "i32");

    return true;
}

TEST_FUNC(Parser_FunctionType_Error_MissingReturnType) {
    const char* source = "const fp: fn(i32);";
    ASSERT_TRUE(expect_parser_abort(source));
    return true;
}

TEST_FUNC(Parser_FunctionType_Error_MissingParen) {
    const char* source = "const fp: fn(i32 void;";
    ASSERT_TRUE(expect_parser_abort(source));
    return true;
}
