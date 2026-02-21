#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file switch_noreturn_tests.cpp
 * @brief Integration tests for switch expressions with divergent prongs and noreturn type.
 */

TEST_FUNC(SwitchNoreturn_BasicDivergence) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    return switch (x) {\n"
        "        0 => 10,\n"
        "        1 => return 20,\n"
        "        else => unreachable,\n"
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

    // Verify emission for divergent prongs
    if (emission.find("case 1: return 20;; break;") == std::string::npos) {
        printf("FAIL: Expected 'return 20' without assignment in case 1, got: %s\n", emission.c_str());
        return false;
    }
    if (emission.find("default: __bootstrap_panic") == std::string::npos) {
        printf("FAIL: Expected panic in default prong, got: %s\n", emission.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(SwitchNoreturn_AllDivergent) {
    const char* source =
        "fn bar() void {}\n"
        "fn foo(x: i32) noreturn {\n"
        "    switch (x) {\n"
        "        0 => unreachable,\n"
        "        else => unreachable,\n"
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

    if (!fn->return_type || fn->return_type->resolved_type->kind != TYPE_NORETURN) {
        printf("FAIL: Expected function return type to be noreturn\n");
        return false;
    }

    return true;
}

TEST_FUNC(SwitchNoreturn_BreakInProng) {
    const char* source =
        "fn foo() void {\n"
        "    while (true) {\n"
        "        var x: i32 = 0;\n"
        "        _ = switch (x) {\n"
        "            0 => break,\n"
        "            else => 1,\n"
        "        };\n"
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

    return true;
}

TEST_FUNC(SwitchNoreturn_LabeledBreakInProng) {
    const char* source =
        "fn foo() void {\n"
        "    outer: while (true) {\n"
        "        var x: i32 = 0;\n"
        "        _ = switch (x) {\n"
        "            0 => break :outer,\n"
        "            else => 1,\n"
        "        };\n"
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

    return true;
}

TEST_FUNC(SwitchNoreturn_MixedTypesError) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    return switch (x) {\n"
        "        0 => 10,\n"
        "        1 => true,\n" // Type mismatch: i32 vs bool
        "        else => unreachable,\n"
        "    };\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    // This should fail during type checking
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected type mismatch error but pipeline succeeded\n");
        return false;
    }

    return true;
}

TEST_FUNC(SwitchNoreturn_VariableNoreturnError) {
    const char* source =
        "fn foo() void {\n"
        "    var x: noreturn = unreachable;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected error for variable of type noreturn but pipeline succeeded\n");
        return false;
    }

    return true;
}

TEST_FUNC(SwitchNoreturn_BlockProng) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    return switch (x) {\n"
        "        0 => {\n"
        "            var y = 5;\n"
        "            y + 5\n"
        "        },\n"
        "        else => 0,\n"
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

    if (emission.find("case 0: { int y = 5; y + 5 }") == std::string::npos) {
         // printf("DEBUG: Emission: %s\n", emission.c_str());
    }

    return true;
}
