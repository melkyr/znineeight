#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "mock_emitter.hpp"
#include "../test_utils.hpp"
#include <cstdio>
#include <string>

/**
 * @file cast_tests.cpp
 * @brief Integration tests for explicit casts (@ptrCast).
 */

static bool run_cast_test(const char* zig_code, TypeKind expected_kind, const char* expected_c89) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (expected_kind != TYPE_VOID) {
        if (!unit.validateExpressionType(expected_kind)) {
            printf("FAIL: Expression type mismatch for: %s\n", zig_code);
            return false;
        }
    }

    if (expected_c89) {
        if (!unit.validateExpressionEmission(expected_c89)) {
            printf("FAIL: Expression emission mismatch for: %s\n", zig_code);
            return false;
        }
    }

    return true;
}

static bool run_cast_error_test(const char* zig_code, ErrorCode expected_error) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution succeeded for (expected failure):\n%s\n", zig_code);
        return false;
    }

    bool matched = unit.hasErrorCode(expected_error);
    if (!matched) {
        printf("FAIL: Expected error code %d but got other errors for:\n%s\n", (int)expected_error, zig_code);
        unit.getErrorHandler().printErrors();
    }
    return matched;
}

TEST_FUNC(PtrCast_Basic) {
    const char* source =
        "fn foo(ptr: *i32) *u8 {\n"
        "    return @ptrCast(*u8, ptr);\n"
        "}";
    return run_cast_test(source, TYPE_POINTER, "(unsigned char*)ptr");
}

TEST_FUNC(PtrCast_ToConst) {
    const char* source =
        "fn foo(ptr: *i32) *const i32 {\n"
        "    return @ptrCast(*const i32, ptr);\n"
        "}";
    return run_cast_test(source, TYPE_POINTER, "(int*)ptr");
}

TEST_FUNC(PtrCast_FromVoid) {
    const char* source =
        "fn foo(ptr: *void) *i32 {\n"
        "    return @ptrCast(*i32, ptr);\n"
        "}";
    return run_cast_test(source, TYPE_POINTER, "(int*)ptr");
}

TEST_FUNC(PtrCast_ToVoid) {
    const char* source =
        "fn foo(ptr: *i32) *void {\n"
        "    return @ptrCast(*void, ptr);\n"
        "}";
    return run_cast_test(source, TYPE_POINTER, "(void*)ptr");
}

TEST_FUNC(PtrCast_TargetNotPointer_Error) {
    const char* source =
        "fn foo(ptr: *i32) i32 {\n"
        "    return @ptrCast(i32, ptr);\n"
        "}";
    return run_cast_error_test(source, ERR_CAST_TARGET_NOT_POINTER);
}

TEST_FUNC(PtrCast_SourceNotPointer_Error) {
    const char* source =
        "fn foo(val: i32) *i32 {\n"
        "    return @ptrCast(*i32, val);\n"
        "}";
    return run_cast_error_test(source, ERR_CAST_SOURCE_NOT_POINTER);
}

TEST_FUNC(PtrCast_Nested) {
    const char* source =
        "fn foo(ptr: *void) *u8 {\n"
        "    return @ptrCast(*u8, @ptrCast(*i32, ptr));\n"
        "}";
    return run_cast_test(source, TYPE_POINTER, "(unsigned char*)(int*)ptr");
}

TEST_FUNC(IntCast_Constant_Fold) {
    const char* source =
        "fn foo() u8 {\n"
        "    return @intCast(u8, 100);\n"
        "}";
    return run_cast_test(source, TYPE_U8, "100U");
}

TEST_FUNC(IntCast_Constant_Overflow_Error) {
    const char* source =
        "fn foo() u8 {\n"
        "    return @intCast(u8, 300);\n"
        "}";
    return run_cast_error_test(source, ERR_INT_CAST_OVERFLOW);
}

TEST_FUNC(IntCast_Runtime) {
    const char* source =
        "fn foo(x: u32) i32 {\n"
        "    return @intCast(i32, x);\n"
        "}";
    // x is u32, target is i32. Sizes are both 4. Not widening.
    return run_cast_test(source, TYPE_I32, "__bootstrap_i32_from_u32(x)");
}

TEST_FUNC(IntCast_Widening) {
    const char* source =
        "fn foo(x: u8) i32 {\n"
        "    return @intCast(i32, x);\n"
        "}";
    // u8 to i32 is widening (1 to 4 bytes).
    return run_cast_test(source, TYPE_I32, "(int)x");
}

TEST_FUNC(IntCast_Bool) {
    const char* source =
        "fn foo(b: bool) u8 {\n"
        "    return @intCast(u8, b);\n"
        "}";
    // bool is i32 (4 bytes) in our system. target u8 (1 byte). Narrowing.
    return run_cast_test(source, TYPE_U8, "__bootstrap_u8_from_bool(b)");
}

TEST_FUNC(FloatCast_Constant_Fold) {
    const char* source =
        "fn foo() f32 {\n"
        "    return @floatCast(f32, 3.14);\n"
        "}";
    return run_cast_test(source, TYPE_F32, "3.14f");
}

TEST_FUNC(FloatCast_Runtime_Widening) {
    const char* source =
        "fn foo(x: f32) f64 {\n"
        "    return @floatCast(f64, x);\n"
        "}";
    return run_cast_test(source, TYPE_F64, "(double)x");
}

TEST_FUNC(FloatCast_Runtime_Narrowing) {
    const char* source =
        "fn foo(x: f64) f32 {\n"
        "    return @floatCast(f32, x);\n"
        "}";
    return run_cast_test(source, TYPE_F32, "__bootstrap_f32_from_f64(x)");
}

TEST_FUNC(Cast_Invalid_Types_Error) {
    const char* source =
        "fn foo(x: f32) i32 {\n"
        "    return @intCast(i32, x);\n"
        "}";
    return run_cast_error_test(source, ERR_CAST_SOURCE_NOT_INTEGER);
}
