#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "ast_lifter.hpp"
#include "platform.hpp"

TEST_FUNC(ASTLifter_ComplexLvalue_Member) {
    const char* source =
        "const S = struct { x: i32 };\n"
        "extern fn foo() !i32;\n"
        "fn test_fn(s: *S) !void {\n"
        "    s.x = try foo();\n"
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

    // s.x = try foo();
    // Expected:
    // var __tmp_try_1 = try foo();
    // s.x = __tmp_try_1;

    mod = unit.getModule("test");
    ast = mod->ast_root;
    // Find test_fn. 0: S, 1: foo, 2: test_fn
    ASTNode* fn_node = NULL;
    for (size_t i = 0; i < ast->as.block_stmt.statements->length(); ++i) {
        ASTNode* s = (*ast->as.block_stmt.statements)[i];
        if (s->type == NODE_FN_DECL && strcmp(s->as.fn_decl->name, "test_fn") == 0) {
            fn_node = s;
            break;
        }
    }
    ASSERT_TRUE(fn_node != NULL);
    ASTNode* body = fn_node->as.fn_decl->body;
    DynamicArray<ASTNode*>* stmts = body->as.block_stmt.statements;

    ASSERT_EQ(stmts->length(), 2);
    ASSERT_EQ((*stmts)[0]->type, NODE_VAR_DECL);
    ASSERT_TRUE(strstr((*stmts)[0]->as.var_decl->name, "__tmp_try_") != NULL);
    ASSERT_EQ((*stmts)[1]->type, NODE_EXPRESSION_STMT);
    ASTNode* assign = (*stmts)[1]->as.expression_stmt.expression;
    ASSERT_EQ(assign->type, NODE_ASSIGNMENT);
    ASSERT_EQ(assign->as.assignment->rvalue->type, NODE_IDENTIFIER);

    return true;
}

TEST_FUNC(ASTLifter_ComplexLvalue_Array) {
    const char* source =
        "extern fn getIndex() usize;\n"
        "fn test_fn(arr: []i32) void {\n"
        "    arr[getIndex()] = if (true) 1 else 2;\n"
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
    ASTNode* fn_node = NULL;
    for (size_t i = 0; i < ast->as.block_stmt.statements->length(); ++i) {
        ASTNode* s = (*ast->as.block_stmt.statements)[i];
        if (s->type == NODE_FN_DECL && strcmp(s->as.fn_decl->name, "test_fn") == 0) {
            fn_node = s;
            break;
        }
    }
    ASSERT_TRUE(fn_node != NULL);
    ASTNode* body = fn_node->as.fn_decl->body;
    DynamicArray<ASTNode*>* stmts = body->as.block_stmt.statements;

    ASSERT_EQ(stmts->length(), 2);
    ASSERT_EQ((*stmts)[0]->type, NODE_VAR_DECL);
    ASSERT_TRUE(strstr((*stmts)[0]->as.var_decl->name, "__tmp_if_") != NULL);

    return true;
}

TEST_FUNC(ASTLifter_EvaluationOrder) {
    const char* source =
        "extern fn getIndex() !usize;\n"
        "extern fn getValue() !i32;\n"
        "fn test_fn(arr: []i32) !void {\n"
        "    arr[try getIndex()] = try getValue();\n"
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

    // arr[try getIndex()] = try getValue();
    // Zig: RHS then LHS.
    // Expected:
    // 1. var __tmp_try_val = try getValue();
    // 2. var __tmp_try_idx = try getIndex();
    // 3. arr[__tmp_try_idx] = __tmp_try_val;

    mod = unit.getModule("test");
    ast = mod->ast_root;
    ASTNode* fn_node = NULL;
    for (size_t i = 0; i < ast->as.block_stmt.statements->length(); ++i) {
        ASTNode* s = (*ast->as.block_stmt.statements)[i];
        if (s->type == NODE_FN_DECL && strcmp(s->as.fn_decl->name, "test_fn") == 0) {
            fn_node = s;
            break;
        }
    }
    ASSERT_TRUE(fn_node != NULL);
    ASTNode* body = fn_node->as.fn_decl->body;
    DynamicArray<ASTNode*>* stmts = body->as.block_stmt.statements;

    // Based on forward forEachChild and insert(idx, ...):
    // 1. Visit try getIndex() -> stmts: [tmp_idx, stmt]
    // 2. Visit try getValue() -> stmts: [tmp_val, tmp_idx, stmt]
    // Thus tmp_val (RHS) is FIRST.

    ASSERT_EQ(stmts->length(), 3);

    ASTNode* var1 = (*stmts)[0];
    ASTNode* var2 = (*stmts)[1];

    // var1 should be getValue's result.
    // var1->as.var_decl->initializer is NODE_TRY_EXPR
    ASTNode* init1 = var1->as.var_decl->initializer;
    ASSERT_EQ(init1->type, NODE_TRY_EXPR);
    ASTNode* call1 = init1->as.try_expr.expression;
    ASSERT_EQ(call1->type, NODE_FUNCTION_CALL);
    const char* name1 = call1->as.function_call->callee->as.identifier.name;

    ASSERT_STREQ("getValue", name1);

    return true;
}

TEST_FUNC(ASTLifter_CompoundAssignment_Complex) {
    const char* source =
        "extern fn getIndex() usize;\n"
        "extern fn getValue() !i32;\n"
        "fn test_fn(arr: []i32) !void {\n"
        "    arr[getIndex()] += try getValue();\n"
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
    ASTNode* fn_node = NULL;
    for (size_t i = 0; i < ast->as.block_stmt.statements->length(); ++i) {
        ASTNode* s = (*ast->as.block_stmt.statements)[i];
        if (s->type == NODE_FN_DECL && strcmp(s->as.fn_decl->name, "test_fn") == 0) {
            fn_node = s;
            break;
        }
    }
    ASSERT_TRUE(fn_node != NULL);
    ASTNode* body = fn_node->as.fn_decl->body;
    DynamicArray<ASTNode*>* stmts = body->as.block_stmt.statements;

    ASSERT_EQ(stmts->length(), 2);
    ASSERT_EQ((*stmts)[0]->type, NODE_VAR_DECL);
    ASSERT_TRUE(strstr((*stmts)[0]->as.var_decl->name, "__tmp_try_") != NULL);
    ASSERT_EQ((*stmts)[1]->type, NODE_EXPRESSION_STMT);
    ASTNode* assign = (*stmts)[1]->as.expression_stmt.expression;
    ASSERT_EQ(assign->type, NODE_COMPOUND_ASSIGNMENT);

    return true;
}
