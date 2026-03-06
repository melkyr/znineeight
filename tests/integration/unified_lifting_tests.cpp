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

    // Each control flow expr now results in:
    // if: 1 var decl + 1 if stmt
    // switch: 1 var decl + 1 switch stmt
    // catch: 1 var decl + 1 block (containing 1 var decl + 1 if stmt)
    // orelse: 1 var decl + 1 block (containing 1 var decl + 1 if stmt)
    // plus the original expression statements (now identifiers)

    // Total should be roughly 4 (vcl) + 4 (stmts) + 4 (calls) = 12
    ASSERT_EQ(stmts->length(), 12);

    // With backward iteration in forEachChild(NODE_BLOCK_STMT), order should be preserved
    // and correctly nested for each statement.

    // Check prefixes
    ASSERT_TRUE(strstr((*stmts)[0]->as.var_decl->name, "__tmp_if_") != NULL);
    ASSERT_EQ((*stmts)[1]->type, NODE_IF_STMT);
    ASSERT_TRUE(strstr((*stmts)[3]->as.var_decl->name, "__tmp_switch_") != NULL);
    ASSERT_EQ((*stmts)[4]->type, NODE_SWITCH_STMT);

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
    // 0: var __tmp_if_1;
    // 1: if (c) { __tmp_if_1 = 1; } else { __tmp_if_1 = 2; }
    // 2: var __tmp_catch_2;
    // 3: { var __tmp_catch_res_3 = bar(__tmp_if_1); if (__tmp_catch_res_3.is_error) ... }
    // 4: foo(__tmp_catch_2);

    ASSERT_EQ(stmts->length(), 5);
    ASSERT_EQ((*stmts)[0]->type, NODE_VAR_DECL);
    ASSERT_EQ((*stmts)[1]->type, NODE_IF_STMT);
    ASSERT_EQ((*stmts)[2]->type, NODE_VAR_DECL);
    ASSERT_EQ((*stmts)[3]->type, NODE_BLOCK_STMT);
    ASSERT_EQ((*stmts)[4]->type, NODE_EXPRESSION_STMT);

    return true;
}
