#include "test_framework.hpp"
#include "../test_utils.hpp"
#include "test_compilation_unit.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file function_call_tests.cpp
 * @brief Integration tests for Zig function calls in the RetroZig compiler.
 */

static bool run_function_call_test(const char* zig_code, const char* call_name, const char* expected_c89) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTNode* call_node = unit.extractFunctionCall(call_name);
    if (!call_node) {
        printf("FAIL: Could not find call to '%s'.\n", call_name);
        return false;
    }

    MockC89Emitter emitter(&unit.getCallSiteLookupTable());
    std::string actual = emitter.emitFunctionCall(call_node);

    if (actual != expected_c89) {
        printf("FAIL: Emission mismatch for call to '%s'.\nExpected: %s\nActual:   %s\n", call_name, expected_c89, actual.c_str());
        return false;
    }

    return true;
}

// --- Basic Calls ---

TEST_FUNC(FunctionCallIntegration_NoParams) {
    const char* source =
        "fn foo() void {}\n"
        "fn main_func() void { foo(); }";
    return run_function_call_test(source, "foo", "foo()");
}

TEST_FUNC(FunctionCallIntegration_TwoArgs) {
    const char* source =
        "fn add(a: i32, b: i32) i32 { return a + b; }\n"
        "fn main_func() i32 { return add(1, 2); }";
    return run_function_call_test(source, "add", "add(1, 2)");
}

TEST_FUNC(FunctionCallIntegration_FourArgs) {
    const char* source =
        "fn bar(a: i32, b: f64, c: bool, d: *i32) void {}\n"
        "fn main_func(p: *i32) void { bar(1, 2.0, true, p); }";
    return run_function_call_test(source, "bar", "bar(1, 2.0, 1, p)");
}

// --- Nested Calls ---

TEST_FUNC(FunctionCallIntegration_Nested) {
    const char* source =
        "fn inner() i32 { return 42; }\n"
        "fn outer(a: i32) i32 { return a; }\n"
        "fn main_func() i32 { return outer(inner()); }";
    // outer(inner())
    return run_function_call_test(source, "outer", "outer(inner())");
}

// --- Name Mangling ---

TEST_FUNC(FunctionCallIntegration_MangleKeyword) {
    // 'int' is a C keyword. Zig function 'int' -> C 'z_int'
    const char* source =
        "fn int() void {}\n"
        "fn main_func() void { int(); }";
    return run_function_call_test(source, "int", "z_int()");
}

// --- Void Calls as Statements ---

TEST_FUNC(FunctionCallIntegration_VoidStatement) {
    const char* source =
        "fn do_work() void {}\n"
        "fn main_func() void {\n"
        "    do_work();\n"
        "}";
    return run_function_call_test(source, "do_work", "do_work()");
}

// --- Call Resolution ---

TEST_FUNC(FunctionCallIntegration_CallResolution) {
    const char* source =
        "fn add(a: i32, b: i32) i32 { return a + b; }\n"
        "fn main_func() void { var x = add(1, 2); }";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    ASSERT_TRUE(unit.performTestPipeline(file_id));

    return unit.validateCallResolution("add", CALL_DIRECT);
}

// --- Negative Tests ---

TEST_FUNC(FunctionCallIntegration_RejectFiveArgs) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    // Bootstrap limit is 4 arguments
    const char* source =
        "fn too_many(a: i32, b: i32, c: i32, d: i32, e: i32) void {}\n"
        "fn main_func() void { too_many(1, 2, 3, 4, 5); }";

    u32 file_id = unit.addSource("test.zig", source);
    // Should fail validation
    ASSERT_FALSE(unit.performTestPipeline(file_id));
    return true;
}

TEST_FUNC(FunctionCallIntegration_RejectFunctionPointer) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    // Indirect calls via variables are not supported in bootstrap
    const char* source =
        "fn target() void {}\n"
        "fn main_func() void {\n"
        "    var fp = target;\n"
        "    fp();\n"
        "}";

    u32 file_id = unit.addSource("test.zig", source);
    // Should fail because function pointers are rejected
    ASSERT_FALSE(unit.performTestPipeline(file_id));
    return true;
}

TEST_FUNC(FunctionCallIntegration_TypeMismatch) {
    const char* source =
        "fn take_int(a: i32) void {}\n"
        "fn main_func() void { take_int(3.14); }";

    // This triggers a fatalError/abort in TypeChecker
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(FunctionCallIntegration_UndefinedFunction) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source = "fn main_func() void { undefined_func(); }";

    u32 file_id = unit.addSource("test.zig", source);
    ASSERT_FALSE(unit.performTestPipeline(file_id));
    return true;
}
