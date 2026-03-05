#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "ast_utils.hpp"
#include "platform.hpp"

TEST_FUNC(ASTCloning_Basic) {
    const char* source = "fn bar() void { const x = 42 + 5; }";
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* original = parser->parse();
    ASSERT_TRUE(original != NULL);

    ASTNode* clone = cloneASTNode(original, &arena);
    ASSERT_TRUE(clone != NULL);
    ASSERT_TRUE(clone != original);
    ASSERT_EQ(clone->type, original->type);

    // Verify deep copy of binary op
    // original is BLOCK (file) -> FN_DECL -> BLOCK (body) -> VAR_DECL -> BINARY_OP
    ASTNode* orig_fn = (*original->as.block_stmt.statements)[0];
    ASTNode* clone_fn = (*clone->as.block_stmt.statements)[0];
    ASSERT_TRUE(orig_fn != clone_fn);
    ASSERT_EQ(orig_fn->type, clone_fn->type);

    ASTNode* orig_body = orig_fn->as.fn_decl->body;
    ASTNode* clone_body = clone_fn->as.fn_decl->body;
    ASSERT_TRUE(orig_body != clone_body);

    ASTNode* orig_decl = (*orig_body->as.block_stmt.statements)[0];
    ASTNode* clone_decl = (*clone_body->as.block_stmt.statements)[0];
    ASSERT_TRUE(orig_decl != clone_decl);

    ASTNode* orig_bin = orig_decl->as.var_decl->initializer;
    ASTNode* clone_bin = clone_decl->as.var_decl->initializer;
    ASSERT_TRUE(orig_bin != clone_bin);
    ASSERT_EQ(orig_bin->type, clone_bin->type);

    // Modify clone, original should remain unchanged
    clone_bin->as.binary_op->left->as.integer_literal.value = 100;
    ASSERT_EQ(orig_bin->as.binary_op->left->as.integer_literal.value, 42ULL);
    ASSERT_EQ(clone_bin->as.binary_op->left->as.integer_literal.value, 100ULL);

    return true;
}

TEST_FUNC(ASTCloning_FunctionCall) {
    const char* source = "fn bar() void { foo(1, 2, 3); }";
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* original = parser->parse();

    ASTNode* clone = cloneASTNode(original, &arena);

    ASTNode* orig_fn = (*original->as.block_stmt.statements)[0];
    ASTNode* clone_fn = (*clone->as.block_stmt.statements)[0];

    ASTNode* orig_expr_stmt = (*orig_fn->as.fn_decl->body->as.block_stmt.statements)[0];
    ASTNode* clone_expr_stmt = (*clone_fn->as.fn_decl->body->as.block_stmt.statements)[0];

    ASTFunctionCallNode* orig_call = orig_expr_stmt->as.expression_stmt.expression->as.function_call;
    ASTFunctionCallNode* clone_call = clone_expr_stmt->as.expression_stmt.expression->as.function_call;

    ASSERT_TRUE(orig_call != clone_call);
    ASSERT_TRUE(orig_call->args != clone_call->args);
    ASSERT_EQ(orig_call->args->length(), clone_call->args->length());

    for (size_t i = 0; i < orig_call->args->length(); ++i) {
        ASSERT_TRUE((*orig_call->args)[i] != (*clone_call->args)[i]);
        ASSERT_EQ((*orig_call->args)[i]->as.integer_literal.value, (*clone_call->args)[i]->as.integer_literal.value);
    }

    return true;
}

TEST_FUNC(ASTCloning_Switch) {
    const char* source =
        "fn bar(y: i32) void {\n"
        "    const x = switch (y) {\n"
        "        0 => 1,\n"
        "        1...5 => 10,\n"
        "        else => 0,\n"
        "    };\n"
        "}";
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* original = parser->parse();

    ASTNode* clone = cloneASTNode(original, &arena);

    ASTNode* orig_fn = (*original->as.block_stmt.statements)[0];
    ASTNode* clone_fn = (*clone->as.block_stmt.statements)[0];

    ASTNode* orig_decl = (*orig_fn->as.fn_decl->body->as.block_stmt.statements)[0];
    ASTNode* clone_decl = (*clone_fn->as.fn_decl->body->as.block_stmt.statements)[0];

    ASTSwitchExprNode* orig_sw = orig_decl->as.var_decl->initializer->as.switch_expr;
    ASTSwitchExprNode* clone_sw = clone_decl->as.var_decl->initializer->as.switch_expr;

    ASSERT_TRUE(orig_sw != clone_sw);
    ASSERT_TRUE(orig_sw->prongs != clone_sw->prongs);
    ASSERT_EQ(orig_sw->prongs->length(), clone_sw->prongs->length());

    for (size_t i = 0; i < orig_sw->prongs->length(); ++i) {
        ASTSwitchProngNode* orig_prong = (*orig_sw->prongs)[i];
        ASTSwitchProngNode* clone_prong = (*clone_sw->prongs)[i];
        ASSERT_TRUE(orig_prong != clone_prong);
        if (orig_prong->items) {
            ASSERT_TRUE(orig_prong->items != clone_prong->items);
            ASSERT_EQ(orig_prong->items->length(), clone_prong->items->length());
        }
        ASSERT_TRUE(orig_prong->body != clone_prong->body);
    }

    return true;
}
