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

    // With backward iteration in NODE_BLOCK_STMT and insert(idx, ...) in liftNode:
    // foo(try bar(if (true) 1 else 2));
    // Post-order visits: if, bar call, try
    // 1. 'if' is lifted. Stmts: [var __tmp_if_1 = ..., foo(try bar(__tmp_if_1))]
    // 2. 'try' is lifted. Stmts: [var __tmp_if_1 = ..., var __tmp_try_2 = try bar(__tmp_if_1), foo(__tmp_try_2)]

    ASSERT_EQ(stmts->length(), 3);

    ASSERT_EQ((*stmts)[0]->type, NODE_VAR_DECL);
    ASSERT_TRUE(strstr((*stmts)[0]->as.var_decl->name, "__tmp_if_") != NULL);

    ASSERT_EQ((*stmts)[1]->type, NODE_VAR_DECL);
    ASSERT_TRUE(strstr((*stmts)[1]->as.var_decl->name, "__tmp_try_") != NULL);

    ASSERT_EQ((*stmts)[2]->type, NODE_EXPRESSION_STMT);

    return true;
}

TEST_FUNC(ASTLifter_ComplexAssignment) {
    const char* source =
        "extern fn getIndex() usize;\n"
        "fn test_lifter_3(arr: []i32) void {\n"
        "    arr[getIndex()] = if (true) 1 else 2;\n"
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

    // arr[getIndex()] = if (true) 1 else 2;
    // Should lift 'if' because it's the RHS of an assignment to a complex lvalue.
    // 1. __tmp_if_1 = if (true) 1 else 2;
    // 2. arr[getIndex()] = __tmp_if_1;

    mod = unit.getModule("test");
    ast = mod->ast_root;
    ASTNode* fn_node = (*ast->as.block_stmt.statements)[1]; // 0 is getIndex, 1 is test_lifter_3
    ASSERT_TRUE(fn_node != NULL);
    ASSERT_EQ(fn_node->type, NODE_FN_DECL);
    ASTNode* body = fn_node->as.fn_decl->body;
    DynamicArray<ASTNode*>* stmts = body->as.block_stmt.statements;

    ASSERT_EQ(stmts->length(), 2);
    ASSERT_EQ((*stmts)[0]->type, NODE_VAR_DECL);
    ASSERT_TRUE(strstr((*stmts)[0]->as.var_decl->name, "__tmp_if_") != NULL);

    ASSERT_EQ((*stmts)[1]->type, NODE_EXPRESSION_STMT);
    ASTNode* assign = (*stmts)[1]->as.expression_stmt.expression;
    ASSERT_EQ(assign->type, NODE_ASSIGNMENT);
    ASSERT_EQ(assign->as.assignment->rvalue->type, NODE_IDENTIFIER);
    ASSERT_EQ(assign->as.assignment->rvalue->as.identifier.name, (*stmts)[0]->as.var_decl->name);

    return true;
}

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

    // 4 calls, each with 1 lifted temp = 8 statements.
    ASSERT_EQ(stmts->length(), 8);

    // Check prefixes
    ASSERT_TRUE(strstr((*stmts)[0]->as.var_decl->name, "__tmp_if_") != NULL);
    ASSERT_TRUE(strstr((*stmts)[2]->as.var_decl->name, "__tmp_switch_") != NULL);
    ASSERT_TRUE(strstr((*stmts)[4]->as.var_decl->name, "__tmp_catch_") != NULL);
    ASSERT_TRUE(strstr((*stmts)[6]->as.var_decl->name, "__tmp_orelse_") != NULL);

    return true;
}

TEST_FUNC(ASTLifter_CompoundAssignment) {
    const char* source =
        "fn test_lifter_4(x: *i32) void {\n"
        "    x.* += if (true) 1 else 2;\n"
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

    // x.* += if (true) 1 else 2;
    // 1. __tmp_if_1 = if (true) 1 else 2;
    // 2. x.* += __tmp_if_1;

    mod = unit.getModule("test");
    ast = mod->ast_root;
    ASTNode* fn_node = (*ast->as.block_stmt.statements)[0];
    ASSERT_TRUE(fn_node != NULL);
    ASSERT_EQ(fn_node->type, NODE_FN_DECL);
    ASTNode* body = fn_node->as.fn_decl->body;
    DynamicArray<ASTNode*>* stmts = body->as.block_stmt.statements;

    ASSERT_EQ(stmts->length(), 2);
    ASSERT_EQ((*stmts)[0]->type, NODE_VAR_DECL);

    ASSERT_EQ((*stmts)[1]->type, NODE_EXPRESSION_STMT);
    ASTNode* assign = (*stmts)[1]->as.expression_stmt.expression;
    ASSERT_EQ(assign->type, NODE_COMPOUND_ASSIGNMENT);
    ASSERT_EQ(assign->as.compound_assignment->rvalue->type, NODE_IDENTIFIER);

    return true;
}
