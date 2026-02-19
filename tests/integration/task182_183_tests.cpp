#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "mock_emitter.hpp"
#include <cstdio>

/**
 * @file task182_183_tests.cpp
 * @brief Integration tests for Task 182 (*void conversion) and Task 183 (usize/isize).
 */

static bool run_task_test(const char* zig_code, bool expected_success = true) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    bool success = unit.performTestPipeline(file_id);

    if (success != expected_success) {
        printf("FAIL: Test %s. Expected success: %d, Got: %d\n", zig_code, expected_success, success);
        if (!success) unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(Task183_USizeISizeSupported) {
    return run_task_test(
        "fn foo() void {\n"
        "    var x: usize = 10u;\n"
        "    var y: isize = -5;\n"
        "}\n"
    );
}

TEST_FUNC(Task182_ArenaAllocReturnsVoidPtr) {
    // arena_alloc now returns *void. We can assign it to *void without conversion.
    return run_task_test(
        "fn foo() void {\n"
        "    var p: *void = arena_alloc_default(16u);\n"
        "}\n"
    );
}

TEST_FUNC(Task182_ImplicitVoidPtrToTypedPtrAssignment) {
    // Implicit conversion from *void to *i32
    return run_task_test(
        "fn foo() void {\n"
        "    var p: *i32 = arena_alloc_default(4u);\n"
        "}\n"
    );
}

TEST_FUNC(Task182_ImplicitVoidPtrToTypedPtrArgument) {
    return run_task_test(
        "fn bar(p: *f64) void {}\n"
        "fn foo() void {\n"
        "    bar(arena_alloc_default(8u));\n"
        "}\n"
    );
}

TEST_FUNC(Task182_ImplicitVoidPtrToTypedPtrReturn) {
    return run_task_test(
        "fn foo() *u8 {\n"
        "    return arena_alloc_default(10u);\n"
        "}\n"
    );
}

TEST_FUNC(Task182_ConstCorrectness_AddConst) {
    // *void -> *const i32 (Allowed: adding const)
    return run_task_test(
        "fn foo() void {\n"
        "    var p: *const i32 = arena_alloc_default(4u);\n"
        "}\n"
    );
}

TEST_FUNC(Task182_ConstCorrectness_PreserveConst) {
    // *const void -> *const i32 (Allowed: same const-ness)
    // Note: arena_alloc returns *void (mutable).
    // We need a way to get a *const void.
    return run_task_test(
        "fn bar(p: *const void) *const i32 {\n"
        "    return p;\n"
        "}\n"
        "fn foo() void {\n"
        "    var p: *const void = arena_alloc_default(4u);\n"
        "    var q: *const i32 = bar(p);\n"
        "}\n"
    );
}

// These tests are expected to FAIL

TEST_FUNC(Task182_ConstCorrectness_DiscardConst_REJECT) {
    // *const void -> *i32 (Rejected: discarding const)
    // We expect a type checker abort or error.
    // Integration tests use unit.performTestPipeline(file_id) which returns false on error.
    return run_task_test(
        "fn bar(p: *const void) *i32 {\n"
        "    return p;\n"
        "}\n",
        false
    );
}

TEST_FUNC(Task182_NonC89Target_Allow) {
    // *void -> **i32 (Now allowed: **i32 is C89-compatible in stage 0)
    return run_task_test(
        "fn foo() void {\n"
        "    var p: * * i32 = arena_alloc_default(4u);\n"
        "}\n",
        true
    );
}
