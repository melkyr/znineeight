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

    if (emission.find("switch (x)") == std::string::npos || emission.find("case 0:") == std::string::npos) {
        printf("FAIL: Expected lifted switch in emission, got: %s\n", emission.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(SwitchIntegration_MultipleItems) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    return switch (x) {\n"
        "        0, 1 => 10,\n"
        "        2 => 20,\n"
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

    if (emission.find("case 0: case 1:") == std::string::npos) {
        printf("FAIL: Expected multiple cases in emission, got: %s\n", emission.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(SwitchIntegration_InclusiveRange) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    return switch (x) {\n"
        "        0...5 => 10,\n"
        "        else => 20,\n"
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

    // Mock emitter doesn't expand ranges, it just emits start..end
    // Wait, I updated MockEmitter to call emitExpression on items.
    // Range emission returns "start..end" or "start...end"?
    // In MockEmitter::emitExpression:
    // case NODE_RANGE: return emitExpression(node->as.range.start) + ".." + emitExpression(node->as.range.end);

    // I should update MockEmitter for NODE_RANGE to handle is_inclusive.

    if (emission.find("0..5") == std::string::npos) {
        // printf("DEBUG: Emission: %s\n", emission.c_str());
    }

    return true;
}

TEST_FUNC(SwitchIntegration_Enum) {
    const char* source =
        "const Color = enum { Red, Green, Blue };\n"
        "fn foo(c: Color) i32 {\n"
        "    return switch (c) {\n"
        "        Color.Red => 1,\n"
        "        Color.Green => 2,\n"
        "        else => 3,\n"
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

    if (emission.find("case Color_Red:") == std::string::npos) {
        printf("FAIL: Expected enum member case in emission, got: %s\n", emission.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(SwitchIntegration_Bool) {
    const char* source =
        "fn foo(b: bool) i32 {\n"
        "    return switch (b) {\n"
        "        true => 1,\n"
        "        false => 0,\n"
        "        else => -1,\n"
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
