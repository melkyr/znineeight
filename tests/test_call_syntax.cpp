#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "parser.hpp"
#include "platform.hpp"
#include "ast_utils.hpp"
#include "test_utils.hpp"

TEST_FUNC(CallSyntax_AtImport) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source = "const std = @import(\"std\");";
    u32 file_id = unit.addSource("test.zig", source);

    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    ASSERT_TRUE(ast != NULL);
    ASSERT_EQ(NODE_BLOCK_STMT, ast->type);
    ASSERT_EQ(1, ast->as.block_stmt.statements->length());

    ASTNode* stmt = (*ast->as.block_stmt.statements)[0];
    ASSERT_EQ(NODE_VAR_DECL, stmt->type);

    ASTNode* init = stmt->as.var_decl->initializer;
    ASSERT_TRUE(init != NULL);

    // Check if it's NODE_FUNCTION_CALL
    ASSERT_EQ(NODE_FUNCTION_CALL, init->type);
    ASSERT_EQ(NODE_IDENTIFIER, init->as.function_call->callee->type);
    ASSERT_STREQ("@import", init->as.function_call->callee->as.identifier.name);
    ASSERT_EQ(1, init->as.function_call->args->length());
    ASSERT_EQ(NODE_STRING_LITERAL, (*init->as.function_call->args)[0]->type);
    ASSERT_STREQ("std", (*init->as.function_call->args)[0]->as.string_literal.value);

    return true;
}

TEST_FUNC(CallSyntax_AtImport_Rejection) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source = "const std = @import(\"std\");";
    u32 file_id = unit.addSource("test.zig", source);

    bool success = unit.performFullPipeline(file_id);
    ASSERT_FALSE(success);

    // Check if error was reported
    ASSERT_TRUE(unit.getErrorHandler().getErrors().length() > 0);

    return true;
}

TEST_FUNC(CallSyntax_ComplexPostfix) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source = "fn foo() void { a().b().c(); }";
    u32 file_id = unit.addSource("test.zig", source);

    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    ASSERT_TRUE(ast != NULL);

    ASTNode* fn_decl = (*ast->as.block_stmt.statements)[0];
    ASSERT_EQ(NODE_FN_DECL, fn_decl->type);

    ASTNode* body = fn_decl->as.fn_decl->body;
    ASSERT_EQ(NODE_BLOCK_STMT, body->type);

    ASTNode* expr_stmt = (*body->as.block_stmt.statements)[0];
    ASSERT_EQ(NODE_EXPRESSION_STMT, expr_stmt->type);

    ASTNode* call_c = expr_stmt->as.expression_stmt.expression;
    ASSERT_EQ(NODE_FUNCTION_CALL, call_c->type);

    ASTNode* member_c = call_c->as.function_call->callee;
    ASSERT_EQ(NODE_MEMBER_ACCESS, member_c->type);
    ASSERT_STREQ("c", member_c->as.member_access->field_name);

    ASTNode* call_b = member_c->as.member_access->base;
    ASSERT_EQ(NODE_FUNCTION_CALL, call_b->type);

    ASTNode* member_b = call_b->as.function_call->callee;
    ASSERT_EQ(NODE_MEMBER_ACCESS, member_b->type);
    ASSERT_STREQ("b", member_b->as.member_access->field_name);

    ASTNode* call_a = member_b->as.member_access->base;
    ASSERT_EQ(NODE_FUNCTION_CALL, call_a->type);
    ASSERT_EQ(NODE_IDENTIFIER, call_a->as.function_call->callee->type);
    ASSERT_STREQ("a", call_a->as.function_call->callee->as.identifier.name);

    return true;
}

TEST_FUNC(CallSyntax_MethodCall) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source = "fn foo() void { s.method(); }";
    u32 file_id = unit.addSource("test.zig", source);

    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    ASSERT_TRUE(ast != NULL);

    ASTNode* fn_decl = (*ast->as.block_stmt.statements)[0];
    ASTNode* body = fn_decl->as.fn_decl->body;
    ASTNode* expr_stmt = (*body->as.block_stmt.statements)[0];
    ASTNode* call = expr_stmt->as.expression_stmt.expression;

    ASSERT_EQ(NODE_FUNCTION_CALL, call->type);
    ASSERT_EQ(NODE_MEMBER_ACCESS, call->as.function_call->callee->type);
    ASSERT_STREQ("method", call->as.function_call->callee->as.member_access->field_name);

    return true;
}
