#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>

static bool run_braceless_test(const char* zig_code, const char* fn_name, const char* expected_c89) {
    ArenaAllocator arena(2 * 1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateFunctionEmission(fn_name, expected_c89)) {
        return false;
    }

    return true;
}

TEST_FUNC(BracelessControlFlow_If) {
    const char* source =
        "fn foo(b: bool) i32 {\n"
        "    if (b) return 1; else return 0;\n"
        "}";
    // Lifter will wrap branches in blocks
    return run_braceless_test(source, "foo", "int foo(int b) { if (b) { return 1; } else { return 0; } }");
}

TEST_FUNC(BracelessControlFlow_ElseIf) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    if (x > 0) return 1;\n"
        "    else if (x < 0) return -1;\n"
        "    else return 0;\n"
        "}";
    return run_braceless_test(source, "foo", "int foo(int x) { if (x > 0) { return 1; } else if (x < 0) { return -1; } else { return 0; } }");
}

TEST_FUNC(BracelessControlFlow_While) {
    const char* source =
        "fn foo(n: i32) void {\n"
        "    var i: i32 = 0;\n"
        "    while (i < n) i = i + 1;\n"
        "}";
    return run_braceless_test(source, "foo", "void foo(int n) { int i = 0; while (i < n) { i = i + 1; } }");
}

TEST_FUNC(BracelessControlFlow_For) {
    const char* source =
        "fn foo(arr: [5]i32) i32 {\n"
        "    var sum: i32 = 0;\n"
        "    for (arr) |item| sum = sum + item;\n"
        "    return sum;\n"
        "}";
    // For loop emission is complex in Mock, but we check if it contains the wrapped statement.
    ArenaAllocator arena(2 * 1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;

    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    std::string actual = emitter.emitFnDecl(unit.extractFunctionDeclaration("foo"));

    if (actual.find("{ sum = sum + item; }") == std::string::npos) {
        printf("FAIL: Braceless for body not wrapped in braces.\nActual: %s\n", actual.c_str());
        return false;
    }
    return true;
}

TEST_FUNC(BracelessControlFlow_ErrDefer) {
    const char* source =
        "fn cleanup() void {}\n"
        "fn foo(b: bool) !void {\n"
        "    errdefer cleanup();\n"
        "    if (b) return error.Fail;\n"
        "}";
    // Lifter now wraps errdefer.
    return run_braceless_test(source, "foo", "struct ErrorUnion_void foo(int b) { /* unsupported node type */ if (b) { { struct ErrorUnion_void __return_val; __return_val.err = ERROR_Fail; __return_val.is_error = 1; return __return_val; } } }");
}

TEST_FUNC(BracelessControlFlow_Defer) {
    const char* source =
        "fn cleanup() void {}\n"
        "fn foo(b: bool) void {\n"
        "    defer cleanup();\n"
        "    if (b) return;\n"
        "}";
    // After lifting, defer is processed and cleanup() is injected before returns and at end of block.
    return run_braceless_test(source, "foo", "void foo(int b) { if (b) { { { cleanup(); } return; } } { cleanup(); } }");
}

TEST_FUNC(BracelessControlFlow_Nested) {
    const char* source =
        "fn foo(a: bool, b: bool) i32 {\n"
        "    if (a) if (b) return 1; else return 2; else return 3;\n"
        "}";
    return run_braceless_test(source, "foo", "int foo(int a, int b) { if (a) { if (b) { return 1; } else { return 2; } } else { return 3; } }");
}

TEST_FUNC(BracelessControlFlow_MixedBraced) {
    const char* source =
        "fn foo(b: bool) void {\n"
        "    if (b) {\n"
        "        var x: i32 = 1;\n"
        "    } else bar();\n"
        "}\n"
        "fn bar() void {}\n";
    return run_braceless_test(source, "foo", "void foo(int b) { if (b) { int x = 1; } else { bar(); } }");
}

TEST_FUNC(BracelessControlFlow_EmptyWhile) {
    const char* source =
        "fn foo(b: bool) void {\n"
        "    while (b) ;\n"
        "}";
    return run_braceless_test(source, "foo", "void foo(int b) { while (b) { /* unsupported node type */ } }");
}

TEST_FUNC(BracelessControlFlow_ForBreak) {
    const char* source =
        "fn foo(arr: [5]i32) void {\n"
        "    for (arr) |item| if (item > 0) break;\n"
        "}";
    ArenaAllocator arena(2 * 1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;
    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    std::string actual = emitter.emitFnDecl(unit.extractFunctionDeclaration("foo"));
    if (actual.find("{ if (item > 0) { break; } }") == std::string::npos) {
        printf("FAIL: Braceless for with if-break not wrapped correctly.\nActual: %s\n", actual.c_str());
        return false;
    }
    return true;
}

TEST_FUNC(BracelessControlFlow_CombinedDefers) {
    const char* source =
        "fn cleanup() void {}\n"
        "fn foo() !void {\n"
        "    defer cleanup();\n"
        "    errdefer cleanup();\n"
        "}";
    return run_braceless_test(source, "foo", "struct ErrorUnion_void foo(void) { /* unsupported node type */ { cleanup(); } }");
}

TEST_FUNC(BracelessControlFlow_InsideLifted) {
    const char* source =
        "fn foo(b: bool) i32 {\n"
        "    const x = if (b) (if (true) 1 else 2) else 0;\n"
        "    return x;\n"
        "}";
    // This is more about checking that it compiles and runs without crashing during lifting
    ArenaAllocator arena(2 * 1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    return unit.performTestPipeline(file_id);
}

TEST_FUNC(BracelessControlFlow_EmptyFor) {
    const char* source =
        "fn foo(arr: [5]i32) void {\n"
        "    for (arr) |_| ;\n"
        "}";
    return run_braceless_test(source, "foo", "void foo(int arr[5]) { { unsigned int __idx = 0; while (__idx < /* len */) { { /* unsupported node type */ } __idx++; } } }");
}
