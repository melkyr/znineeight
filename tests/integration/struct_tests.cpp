#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file struct_tests.cpp
 * @brief Integration tests for Zig structs in the RetroZig compiler.
 */

static bool run_struct_test(const char* zig_code, const char* var_name, const char* expected_c89) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateVariableEmission(var_name, expected_c89)) {
        return false;
    }

    return true;
}

// --- Basic Structs ---

TEST_FUNC(StructIntegration_BasicNamedStruct) {
    const char* source =
        "const Point = struct { x: i32, y: i32 };\n"
        "var p: Point = Point{ .x = 1, .y = 2 };";
    return run_struct_test(source, "p", "struct Point p = {1, 2};");
}

TEST_FUNC(StructIntegration_MemberAccess) {
    const char* source =
        "const Point = struct { x: i32, y: i32 };\n"
        "fn foo() i32 {\n"
        "    var p: Point = Point{ .x = 10, .y = 20 };\n"
        "    return p.x;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        return false;
    }

    // Verify emission of the return statement contains p.x
    const ASTFnDeclNode* fn = unit.extractFunctionDeclaration("foo");
    if (!fn) return false;

    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    std::string emission = emitter.emitExpression(fn->body);

    if (emission.find("return p.x;") == std::string::npos) {
        printf("FAIL: Expected 'return p.x;' in emission, got: %s\n", emission.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(StructIntegration_NamedInitializerOrder) {
    // Test that named initializers are reordered to match declaration order
    const char* source =
        "const Point = struct { x: i32, y: i32 };\n"
        "var p: Point = Point{ .y = 20, .x = 10 };";
    return run_struct_test(source, "p", "struct Point p = {10, 20};");
}

// --- Negative Tests ---

TEST_FUNC(StructIntegration_RejectAnonymousStruct) {
    const char* source =
        "fn foo() void {\n"
        "    var s: struct { x: i32 } = null;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    // Should fail in TypeChecker
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected failure for anonymous struct, but it succeeded\n");
        return false;
    }

    return unit.hasErrorMatching("anonymous structs");
}

TEST_FUNC(StructIntegration_RejectStructMethods) {
    const char* source =
        "const Point = struct {\n"
        "    x: i32,\n"
        "    fn length(self: *Point) i32 { return self.x; }\n"
        "};";

    // Parser::error is fatal and calls abort()
    return expect_parser_abort(source);
}

TEST_FUNC(StructIntegration_AllowSliceField) {
    const char* source =
        "const Buffer = struct {\n"
        "    data: []i32,\n"
        "};";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performFullPipeline(file_id)) {
        printf("FAIL: Expected struct with slice field to succeed\n");
        return false;
    }

    return true;
}

TEST_FUNC(StructIntegration_AllowMultiLevelPointerField) {
    const char* source =
        "const Data = struct {\n"
        "    ptr: **i32,\n"
        "};";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected success for multi-level pointer field, but it failed\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}
