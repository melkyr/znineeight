#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include "ast_lifter.hpp"
#include <cstdio>
#include <string>

/**
 * @file switch_lifter_tests.cpp
 * @brief Integration tests for switch expression lifting.
 */

TEST_FUNC(SwitchLifter_NestedControlFlow) {
    const char* source =
        "fn foo(x: i32, cond: bool) i32 {\n"
        "    return switch (x) {\n"
        "        1 => if (cond) 10 else 20,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTFnDeclNode* fn = unit.extractFunctionDeclaration("foo");
    if (!fn) return false;

    ASTSwitchStmtNode* sw = NULL;
    ASTBlockStmtNode* body = &fn->body->as.block_stmt;
    for (size_t i = 0; i < body->statements->length(); ++i) {
        if ((*body->statements)[i]->type == NODE_SWITCH_STMT) {
            sw = (*body->statements)[i]->as.switch_stmt;
            break;
        }
    }

    if (!sw) {
        printf("FAIL: Could not find switch statement in lifted AST\n");
        return false;
    }

    if (sw->prongs->length() < 1) {
        printf("FAIL: Switch has no prongs\n");
        return false;
    }

    ASTSwitchStmtProngNode* prong = (*sw->prongs)[0];
    if (prong->body->type != NODE_BLOCK_STMT) {
        printf("FAIL: Prong body is not a block statement\n");
        return false;
    }

    ASTBlockStmtNode* prong_block = &prong->body->as.block_stmt;
    bool found_nested_if = false;
    for (size_t i = 0; i < prong_block->statements->length(); ++i) {
        if ((*prong_block->statements)[i]->type == NODE_IF_STMT) {
            found_nested_if = true;
            break;
        }
    }

    if (!found_nested_if) {
        printf("FAIL: Nested 'if' expression was not lifted into a statement inside the switch prong\n");
        return false;
    }

    return true;
}
