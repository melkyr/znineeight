#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file defer_tests.cpp
 * @brief Integration tests for Zig defer statements in the RetroZig compiler.
 */

TEST_FUNC(DeferIntegration_Basic) {
    const char* source =
        "fn foo() void {\n"
        "    defer { bar(); }\n"
        "}\n"
        "fn bar() void {}";

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

    if (emission.find("/* defer { bar(); } */") == std::string::npos) {
        printf("FAIL: Expected '/* defer { bar(); } */' in emission, got: %s\n", emission.c_str());
        return false;
    }

    return true;
}
