#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file task_9_3_test.cpp
 * @brief Integration tests for string literal coercion and pointer-to-array decay.
 */

TEST_FUNC(StringLiteral_To_ManyPtr) {
    const char* source =
        "extern fn puts(s: [*]const u8) i32;\n"
        "pub fn main() void {\n"
        "    _ = puts(\"hello\");\n"
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

    /* Verify that the string literal was passed directly as a pointer in C */
    if (!unit.validateFunctionCallEmission("puts", "puts(\"hello\")")) {
        return false;
    }

    return true;
}

TEST_FUNC(StringLiteral_To_Slice) {
    const char* source =
        "extern fn take_slice(s: []const u8) void;\n"
        "pub fn main() void {\n"
        "    take_slice(\"slice\");\n"
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

    /* Verify that it calls __make_slice_u8 (or similar) with the literal and length 5 */
    if (!unit.validateFunctionCallEmission("take_slice", "take_slice(__make_slice_u8(\"slice\", 5U))")) {
        return false;
    }

    return true;
}

TEST_FUNC(StringLiteral_BackwardCompat) {
    const char* source =
        "extern fn legacy_puts(s: *const u8) i32;\n"
        "pub fn main() void {\n"
        "    _ = legacy_puts(\"compat\");\n"
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

    if (!unit.validateFunctionCallEmission("legacy_puts", "legacy_puts(\"compat\")")) {
        return false;
    }

    return true;
}

TEST_FUNC(PtrToArray_To_ManyPtr) {
    const char* source =
        "extern fn puts(s: [*]const u8) i32;\n"
        "pub fn main() void {\n"
        "    const arr: [5]u8 = \"world\".*;\n"
        "    const arr_ptr: *const [5]u8 = &arr;\n"
        "    _ = puts(arr_ptr);\n"
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

    /* Verify decay to &(*arr_ptr)[0] */
    /* Note: Mock emitter currently emits it as &*arr_ptr[0U] because it handles pointer-to-array indexing by dereferencing. */
    if (!unit.validateFunctionCallEmission("puts", "puts(&*arr_ptr[0U])")) {
        return false;
    }

    return true;
}

TEST_FUNC(PtrToArray_To_Slice) {
    const char* source =
        "extern fn take_slice(s: []const u8) void;\n"
        "pub fn main() void {\n"
        "    const arr: [5]u8 = \"world\".*;\n"
        "    const arr_ptr: *const [5]u8 = &arr;\n"
        "    take_slice(arr_ptr);\n"
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

    /* Verify slice creation from pointer to array: __make_slice_u8(&(*arr_ptr)[0], 5) */
    if (!unit.validateFunctionCallEmission("take_slice", "take_slice(__make_slice_u8(&(*arr_ptr)[0U], 5U - 0U))")) {
        return false;
    }

    return true;
}
