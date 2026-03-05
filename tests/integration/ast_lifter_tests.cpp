#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "ast_lifter.hpp"
#include "platform.hpp"

TEST_FUNC(ASTLifter_BasicIf) {
    const char* source =
        "extern fn foo(arg: i32) void;\n"
        "fn test_lifter_1() void {\n"
        "    foo(if (true) 1 else 2);\n"
        "}\n";
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    // Set root AST to module
    Module* mod = unit.getModule("test");
    mod->ast_root = ast;

    // Run type checker (required for lifting to know types)
    TypeChecker checker(unit);
    checker.check(ast);
    if (unit.getErrorHandler().hasErrors()) {
        unit.getErrorHandler().printErrors();
    }
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    // Run lifter
    ControlFlowLifter lifter(&arena, &interner, &unit.getErrorHandler());
    lifter.lift(&unit);

    // Verify transformation
    // Original: foo(if (true) 1 else 2);
    // Lifted:
    // {
    //    const __tmp_if_1 = if (true) 1 else 2;
    //    foo(__tmp_if_1);
    // }

    // Find the module "test"
    mod = unit.getModule("test");
    ASSERT_TRUE(mod != NULL);
    ast = mod->ast_root;
    ASSERT_TRUE(ast != NULL);

    ASTNode* fn_node = (*ast->as.block_stmt.statements)[1]; // 0 is foo decl, 1 is test_lifter_1
    ASSERT_EQ(fn_node->type, NODE_FN_DECL);
    ASTNode* body = fn_node->as.fn_decl->body;
    DynamicArray<ASTNode*>* stmts = body->as.block_stmt.statements;

    // Should now have 2 statements
    ASSERT_EQ(stmts->length(), 2);

    ASTNode* stmt1 = (*stmts)[0];
    ASSERT_EQ(stmt1->type, NODE_VAR_DECL);
    ASSERT_TRUE(strstr(stmt1->as.var_decl->name, "__tmp_if_") != NULL);
    ASSERT_EQ(stmt1->as.var_decl->initializer->type, NODE_IF_EXPR);

    ASTNode* stmt2 = (*stmts)[1];
    ASSERT_EQ(stmt2->type, NODE_EXPRESSION_STMT);
    ASTNode* call = stmt2->as.expression_stmt.expression;
    ASSERT_EQ(call->type, NODE_FUNCTION_CALL);
    ASTNode* arg = (*call->as.function_call->args)[0];
    ASSERT_EQ(arg->type, NODE_IDENTIFIER);
    ASSERT_EQ(arg->as.identifier.name, stmt1->as.var_decl->name);

    return true;
}

TEST_FUNC(ASTLifter_Nested) {
    const char* source =
        "extern fn foo(arg: i32) void;\n"
        "extern fn bar(arg: i32) !i32;\n"
        "fn test_lifter_2() !void {\n"
        "    foo(try bar(if (true) 1 else 2));\n"
        "}\n";
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    Module* mod = unit.getModule("test");
    mod->ast_root = ast;

    TypeChecker checker(unit);
    checker.check(ast);
    if (unit.getErrorHandler().hasErrors()) {
        unit.getErrorHandler().printErrors();
    }
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    ControlFlowLifter lifter(&arena, &interner, &unit.getErrorHandler());
    lifter.lift(&unit);

    // foo(try bar(if (true) 1 else 2));
    // Should lift 'if' first (post-order), then 'try'.
    // 1. __tmp_if_1 = if (true) 1 else 2;
    // 2. __tmp_try_2 = try bar(__tmp_if_1);
    // 3. foo(__tmp_try_2);

    mod = unit.getModule("test");
    ast = mod->ast_root;
    ASTNode* fn_node = (*ast->as.block_stmt.statements)[2]; // 0 is foo, 1 is bar, 2 is test_lifter_2
    ASSERT_EQ(fn_node->type, NODE_FN_DECL);
    ASTNode* body = fn_node->as.fn_decl->body;
    DynamicArray<ASTNode*>* stmts = body->as.block_stmt.statements;

    ASSERT_EQ(stmts->length(), 3);

    ASSERT_EQ((*stmts)[0]->type, NODE_VAR_DECL);
    ASSERT_TRUE(strstr((*stmts)[0]->as.var_decl->name, "__tmp_if_") != NULL);

    ASSERT_EQ((*stmts)[1]->type, NODE_VAR_DECL);
    ASSERT_TRUE(strstr((*stmts)[1]->as.var_decl->name, "__tmp_try_") != NULL);

    ASSERT_EQ((*stmts)[2]->type, NODE_EXPRESSION_STMT);

    return true;
}
