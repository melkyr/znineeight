#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file switch_tests.cpp
 * @brief Integration tests for Zig switch expressions in the RetroZig compiler.
 */

TEST_FUNC(SwitchIntegration_Basic) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    return switch (x) {\n"
        "        0 => 10,\n"
        "        1 => 20,\n"
        "        else => 30,\n"
        "    };\n"
        "}";

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

    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    std::string emission = emitter.emitExpression(fn->body);

    if (emission.find("return /* switch expression */;") == std::string::npos) {
        printf("FAIL: Expected 'return /* switch expression */;' in emission, got: %s\n", emission.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(SwitchIntegration_InferredType) {
    const char* source =
        "fn foo(x: i32) void {\n"
        "    var y = switch (x) {\n"
        "        0 => true,\n"
        "        else => false,\n"
        "    };\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTNode* y_node = unit.extractVariableDeclarationNode("y");
    if (!y_node) return false;

    if (!y_node->resolved_type || y_node->resolved_type->kind != TYPE_BOOL) {
        printf("FAIL: Expected variable 'y' to have bool type inferred from switch\n");
        return false;
    }

    return true;
}
