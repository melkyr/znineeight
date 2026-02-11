#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "mock_emitter.hpp"
#include "../test_utils.hpp"
#include <cstdio>
#include <string>

/**
 * @file pointer_arithmetic_tests.cpp
 * @brief Integration tests for pointer arithmetic using usize and isize.
 */

static bool run_ptr_arith_test(const char* zig_code, TypeKind expected_kind, const char* expected_c89) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (expected_kind != TYPE_VOID) { // TYPE_VOID means we don't check type
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

TEST_FUNC(PointerArithmetic_PtrPlusUSize) {
    const char* source =
        "fn foo(ptr: *i32, offset: usize) *i32 {\n"
        "    return ptr + offset;\n"
        "}";
    return run_ptr_arith_test(source, TYPE_POINTER, "ptr + offset");
}

TEST_FUNC(PointerArithmetic_SizeOfUSize) {
    const char* source =
        "fn foo() usize {\n"
        "    return @sizeOf(usize);\n"
        "}";
    // For now we just check that it parses and types correctly.
    // It returns get_g_type_usize().
    return run_ptr_arith_test(source, TYPE_USIZE, NULL);
}

TEST_FUNC(PointerArithmetic_AlignOfISize) {
    const char* source =
        "fn foo() usize {\n"
        "    return @alignOf(isize);\n"
        "}";
    return run_ptr_arith_test(source, TYPE_USIZE, NULL);
}

TEST_FUNC(PointerArithmetic_USizePlusPtr) {
    const char* source =
        "fn foo(ptr: *i32, offset: usize) *i32 {\n"
        "    return offset + ptr;\n"
        "}";
    return run_ptr_arith_test(source, TYPE_POINTER, "offset + ptr");
}

TEST_FUNC(PointerArithmetic_PtrMinusUSize) {
    const char* source =
        "fn foo(ptr: *i32, offset: usize) *i32 {\n"
        "    return ptr - offset;\n"
        "}";
    return run_ptr_arith_test(source, TYPE_POINTER, "ptr - offset");
}

TEST_FUNC(PointerArithmetic_PtrMinusPtr) {
    const char* source =
        "fn foo(ptr1: *i32, ptr2: *i32) isize {\n"
        "    return ptr1 - ptr2;\n"
        "}";
    // isize is a primitive type in our system
    return run_ptr_arith_test(source, TYPE_ISIZE, "ptr1 - ptr2");
}

TEST_FUNC(PointerArithmetic_PtrPlusISize) {
    const char* source =
        "fn foo(ptr: *i32, offset: isize) *i32 {\n"
        "    return ptr + offset;\n"
        "}";
    return run_ptr_arith_test(source, TYPE_POINTER, "ptr + offset");
}

// --- Negative Tests ---

TEST_FUNC(PointerArithmetic_PtrPlusPtr_Error) {
    const char* source =
        "fn foo(ptr1: *i32, ptr2: *i32) void {\n"
        "    var res: *i32 = ptr1 + ptr2;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected pointer + pointer error but pipeline succeeded\n");
        return false;
    }
    bool matched = unit.hasErrorMatching("invalid operands for arithmetic operator");
    if (!matched) {
        printf("FAIL: Expected error 'invalid operands for arithmetic operator' but got other errors:\n");
        unit.getErrorHandler().printErrors();
    }
    return matched;
}

TEST_FUNC(PointerArithmetic_PtrMulInt_Error) {
    const char* source =
        "fn foo(ptr: *i32) void {\n"
        "    var res: *i32 = ptr * 2;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected pointer * int error but pipeline succeeded\n");
        return false;
    }
    bool matched = unit.hasErrorMatching("invalid operands for arithmetic operator");
    if (!matched) {
        printf("FAIL: Expected error 'invalid operands for arithmetic operator' but got other errors:\n");
        unit.getErrorHandler().printErrors();
    }
    return matched;
}

TEST_FUNC(PointerArithmetic_DiffDifferentTypes_Error) {
    const char* source =
        "fn foo(ptr1: *i32, ptr2: *u8) void {\n"
        "    var res: isize = ptr1 - ptr2;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected pointer difference type mismatch error but pipeline succeeded\n");
        return false;
    }
    bool matched = unit.hasErrorMatching("cannot subtract pointers to different types");
    if (!matched) {
        printf("FAIL: Expected error 'cannot subtract pointers to different types' but got other errors:\n");
        unit.getErrorHandler().printErrors();
    }
    return matched;
}
