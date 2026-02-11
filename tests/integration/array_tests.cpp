#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file array_tests.cpp
 * @brief Integration tests for Zig arrays in the RetroZig compiler.
 */

TEST_FUNC(ArrayIntegration_FixedSizeDecl) {
    const char* source =
        "fn foo(arr: [5]i32) void {\n"
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

    if (!unit.validateFunctionSignature("foo", "void foo(int arr[5])")) {
        return false;
    }

    return true;
}

TEST_FUNC(ArrayIntegration_Indexing) {
    const char* source =
        "fn foo(arr: [3]i32) i32 {\n"
        "    return arr[0];\n"
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

    if (emission.find("return arr[0];") == std::string::npos) {
        printf("FAIL: Expected 'return arr[0];' in emission, got: %s\n", emission.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(ArrayIntegration_MultiDimensionalIndexing) {
    const char* source =
        "fn foo(matrix: [2][2]i32) i32 {\n"
        "    return matrix[0][1];\n"
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

    if (emission.find("matrix[0][1]") == std::string::npos) {
        printf("FAIL: Expected 'matrix[0][1]' in emission, got: %s\n", emission.c_str());
        return false;
    }

    return true;
}
