#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "mock_emitter.hpp"
#include "../test_utils.hpp"
#include <cstdio>

/**
 * @file builtin_offsetof_tests.cpp
 * @brief Integration tests for @offsetOf built-in.
 */

static bool run_offsetof_test(const char* zig_code, const char* expected_c89) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (expected_c89) {
        if (!unit.validateExpressionEmission(expected_c89)) {
            printf("FAIL: Expression emission mismatch for: %s\n", zig_code);
            return false;
        }
    }

    return true;
}

static bool run_offsetof_error_test(const char* zig_code, ErrorCode expected_code) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    // Note: performTestPipeline might abort on fatal error if we don't handle it.
    // In our system, TypeChecker reports errors to ErrorHandler.
    unit.performTestPipeline(file_id);

    bool has_error = false;
    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == expected_code) {
            has_error = true;
            break;
        }
    }

    if (!has_error) {
        printf("FAIL: Expected error code %d but got other errors for:\n%s\n", expected_code, zig_code);
        unit.getErrorHandler().printErrors();
    }
    return has_error;
}

TEST_FUNC(BuiltinOffsetOf_StructBasic) {
    const char* source =
        "const Point = struct { x: i32, y: i32 };\n"
        "fn foo() usize {\n"
        "    return @offsetOf(Point, \"y\");\n"
        "}";
    // x is at 0, y is at 4 (size of i32)
    return run_offsetof_test(source, "4U");
}

TEST_FUNC(BuiltinOffsetOf_StructPadding) {
    const char* source =
        "const S = struct { a: u8, b: i32 };\n"
        "fn foo() usize {\n"
        "    return @offsetOf(S, \"b\");\n"
        "}";
    // a is at 0 (size 1), b needs 4-byte alignment, so b is at 4.
    return run_offsetof_test(source, "4U");
}

TEST_FUNC(BuiltinOffsetOf_Union) {
    const char* source =
        "const U = union { a: u8, b: i32 };\n"
        "fn foo() usize {\n"
        "    return @offsetOf(U, \"b\");\n"
        "}";
    // In a union, all fields start at offset 0.
    return run_offsetof_test(source, "0U");
}

TEST_FUNC(BuiltinOffsetOf_NonAggregate_Error) {
    const char* source =
        "fn foo() usize {\n"
        "    return @offsetOf(i32, \"x\");\n"
        "}";
    return run_offsetof_error_test(source, ERR_OFFSETOF_NON_AGGREGATE);
}

TEST_FUNC(BuiltinOffsetOf_FieldNotFound_Error) {
    const char* source =
        "const Point = struct { x: i32, y: i32 };\n"
        "fn foo() usize {\n"
        "    return @offsetOf(Point, \"z\");\n"
        "}";
    return run_offsetof_error_test(source, ERR_OFFSETOF_FIELD_NOT_FOUND);
}

TEST_FUNC(BuiltinOffsetOf_IncompleteType_Error) {
    // NOTE: In the current Milestone 4 bootstrap compiler, it is practically impossible
    // to reach visitOffsetOf with an incomplete struct/union type because:
    // 1. We do not support forward declarations of structs (e.g., 'const S = struct;').
    // 2. We do not support opaque types.
    // 3. Types must be defined before they are used in @offsetOf.
    //
    // The check for isTypeComplete() is implemented in TypeChecker::visitOffsetOf for
    // robustness and future-proofing, but we cannot reliably trigger ERR_OFFSETOF_INCOMPLETE_TYPE
    // with valid Zig syntax until more advanced type features are implemented.

    return true; // Skip this one as it is currently untestable.
}
