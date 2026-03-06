#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "ast_lifter.hpp"
#include "platform.hpp"

TEST_FUNC(ASTLifter_Unified) {
    const char* source =
        "extern fn foo(arg: i32) void;\n"
        "extern fn bar(arg: i32) !i32;\n"
        "fn test_lifter_unified(c: bool, opt: ?i32) void {\n"
        "    foo(if (c) 1 else 2);\n"
        "    foo(switch (c) { true => 1, else => 2 });\n"
        "    _ = bar(10) catch 0;\n"
        "    foo(opt orelse 30);\n"
        "}\n";
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    Module* mod = unit.getModule("test");
    mod->ast_root = ast;

    TypeChecker checker(unit);
    checker.check(ast);
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    ControlFlowLifter lifter(&arena, &interner, &unit.getErrorHandler());
    lifter.lift(&unit);

    mod = unit.getModule("test");
    ast = mod->ast_root;
    ASTNode* fn_node = (*ast->as.block_stmt.statements)[2];
    ASTNode* body = fn_node->as.fn_decl->body;
    DynamicArray<ASTNode*>* stmts = body->as.block_stmt.statements;

    // 4 calls, each with 1 lifted temp = 8 statements
    ASSERT_EQ(stmts->length(), 8);

    // With backward iteration in forEachChild(NODE_BLOCK_STMT), order should be preserved
    // and correctly nested for each statement.

    // Check prefixes (Stmt 0: lift, Stmt 1: call, etc.)
    ASSERT_TRUE(strstr((*stmts)[0]->as.var_decl->name, "__tmp_if_") != NULL);
    ASSERT_TRUE(strstr((*stmts)[2]->as.var_decl->name, "__tmp_switch_") != NULL);
    ASSERT_TRUE(strstr((*stmts)[4]->as.var_decl->name, "__tmp_catch_") != NULL);
    ASSERT_TRUE(strstr((*stmts)[6]->as.var_decl->name, "__tmp_orelse_") != NULL);

    return true;
}

TEST_FUNC(ASTLifter_DeepNested) {
    const char* source =
        "extern fn foo(arg: i32) void;\n"
        "extern fn bar(arg: i32) !i32;\n"
        "fn test_lifter_deep(c: bool) void {\n"
        "    foo((bar(if (c) 1 else 2) catch 0));\n"
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
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    ControlFlowLifter lifter(&arena, &interner, &unit.getErrorHandler());
    lifter.lift(&unit);

    mod = unit.getModule("test");
    ast = mod->ast_root;
    ASTNode* fn_node = (*ast->as.block_stmt.statements)[2];
    ASTNode* body = fn_node->as.fn_decl->body;
    DynamicArray<ASTNode*>* stmts = body->as.block_stmt.statements;

    // Should have:
    // 0: var __tmp_if_1 = if (c) 1 else 2;
    // 1: var __tmp_catch_2 = bar(__tmp_if_1) catch 0;
    // 2: foo(__tmp_catch_2);

    ASSERT_EQ(stmts->length(), 3);
    ASSERT_TRUE(strstr((*stmts)[0]->as.var_decl->name, "__tmp_if_") != NULL);
    ASSERT_TRUE(strstr((*stmts)[1]->as.var_decl->name, "__tmp_catch_") != NULL);
    ASSERT_EQ((*stmts)[2]->type, NODE_EXPRESSION_STMT);

    return true;
}
