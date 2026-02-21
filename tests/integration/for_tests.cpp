#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file for_tests.cpp
 * @brief Integration tests for Zig for loops in the RetroZig compiler.
 */

TEST_FUNC(ForIntegration_Basic) {
    const char* source =
        "fn foo(arr: [5]i32) void {\n"
        "    for (arr) |item| {\n"
        "        var dummy = item;\n"
        "    }\n"
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

    if (emission.find("while") == std::string::npos) {
        printf("FAIL: Expected 'while' in emission, got: %s\n", emission.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(ForIntegration_InvalidIterable) {
    const char* source =
        "fn foo() void {\n"
        "    var x: bool = true;\n"
        "    for (x) |item| {\n"
        "        var dummy = item;\n"
        "    }\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected pipeline to fail for non-iterable type\n");
        return false;
    }

    return true;
}

TEST_FUNC(ForIntegration_ImmutableCapture) {
    const char* source =
        "fn foo(arr: [3]i32) void {\n"
        "    for (arr) |item| {\n"
        "        item = 10;\n"
        "    }\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected pipeline to fail when assigning to immutable capture\n");
        return false;
    }

    return true;
}

TEST_FUNC(ForIntegration_DiscardCapture) {
    const char* source =
        "fn foo(arr: [3]i32) void {\n"
        "    for (arr) |_, index| {\n"
        "        var x: usize = index;\n"
        "    }\n"
        "    for (arr) |item, _| {\n"
        "        var y: i32 = item;\n"
        "    }\n"
        "    for (0..10) |_| {\n"
        "        var z: i32 = 1;\n"
        "    }\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for discard captures:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTFnDeclNode* fn = unit.extractFunctionDeclaration("foo");
    if (!fn) return false;

    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    std::string emission = emitter.emitExpression(fn->body);

    // Verify that '_' captures do not appear as variable declarations
    if (emission.find(" _ =") != std::string::npos || emission.find(" _;") != std::string::npos) {
        printf("FAIL: Found '_' in emission, should have been discarded: %s\n", emission.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(ForIntegration_Scoping) {
    const char* source =
        "fn foo(arr: [3]i32) void {\n"
        "    for (arr) |item| {\n"
        "        var x: i32 = item;\n"
        "    }\n"
        "    // item should not be visible here\n"
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

    // Verify 'item' is not in global scope (obviously)
    // and we can't easily check if it's NOT in the function scope after it's popped.
    // But if the TypeChecker didn't error on 'var x: i32 = item;', it means it was in scope there.

    return true;
}
