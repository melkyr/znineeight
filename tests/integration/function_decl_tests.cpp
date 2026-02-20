#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file function_decl_tests.cpp
 * @brief Integration tests for Zig function declarations in the RetroZig compiler.
 */

static bool run_fn_decl_test(const char* zig_code, const char* fn_name, const char* expected_signature) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateFunctionSignature(fn_name, expected_signature)) {
        return false;
    }

    return true;
}

// --- Basic Declarations ---

TEST_FUNC(FunctionIntegration_NoParams) {
    return run_fn_decl_test("fn foo() void {}", "foo", "void foo(void)");
}

TEST_FUNC(FunctionIntegration_FourParams) {
    const char* source = "fn add4(a: i32, b: i32, c: i32, d: i32) i32 { return a + b + c + d; }";
    return run_fn_decl_test(source, "add4", "int add4(int a, int b, int c, int d)");
}

TEST_FUNC(FunctionIntegration_PointerTypes) {
    const char* source = "fn ptr_func(p: *i32, s: *const u8) void {}";
    /* C89Emitter drops 'const' on pointers for simplicity */
    return run_fn_decl_test(source, "ptr_func", "void ptr_func(int* p, unsigned char* s)");
}

// --- Name Mangling ---

TEST_FUNC(FunctionIntegration_MangleKeyword) {
    // 'int' is a C keyword but NOT a Zig keyword, so it is a valid Zig identifier.
    // It should be mangled to 'z_int' by sanitizeForC89.
    return run_fn_decl_test("fn int() void {}", "int", "void z_int(void)");
}

TEST_FUNC(FunctionIntegration_MangleLongName) {
    const char* long_name = "this_is_a_very_long_function_name_that_exceeds_31_chars";
    // Truncated to 31: "this_is_a_very_long_function_na"
    return run_fn_decl_test("fn this_is_a_very_long_function_name_that_exceeds_31_chars() void {}", long_name, "void this_is_a_very_long_function_na(void)");
}

// --- Forward References & Recursion ---

TEST_FUNC(FunctionIntegration_Recursion) {
    const char* source =
        "fn factorial(n: i32) i32 {\n"
        "    if (n <= 1) { return 1; }\n"
        "    return (n * factorial(n - 1));\n"
        "}";
    // Current TypeChecker resolves factorial by recursion support.
    return run_fn_decl_test(source, "factorial", "int factorial(int n)");
}

TEST_FUNC(FunctionIntegration_ForwardReference) {
    const char* source =
        "fn first() void { second(); }\n"
        "fn second() void {}";
    return run_fn_decl_test(source, "first", "void first(void)");
}

// --- Negative Tests ---

TEST_FUNC(FunctionIntegration_AllowFiveParams) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source = "fn many_params(a: i32, b: i32, c: i32, d: i32, e: i32) void {}";
    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected 5-param support but pipeline failed\n");
        unit.getErrorHandler().printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(FunctionIntegration_RejectSliceReturn) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source = "fn get_slice() []u8 { return null; }";
    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected slice return rejection but pipeline succeeded\n");
        return false;
    }
    return true;
}

TEST_FUNC(FunctionIntegration_AllowMultiLevelPointer) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    // Multi-level pointers are now supported
    const char* source = "fn multi_ptr(p: **i32) void {}";
    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected multi-level pointer support but pipeline failed\n");
        return false;
    }
    return true;
}

TEST_FUNC(FunctionIntegration_RejectDuplicateName) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "fn foo() void {}\n"
        "fn foo() void {}";
    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected duplicate name rejection but pipeline succeeded\n");
        return false;
    }
    return true;
}
