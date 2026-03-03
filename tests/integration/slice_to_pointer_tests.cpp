#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "type_checker.hpp"

TEST_FUNC(SliceToPointer_Assignment) {
    const char* source =
        "fn foo() void {\n"
        "    var arr: [5]u8 = undefined;\n"
        "    var slice: []u8 = arr[0..5];\n"
        "    var p: [*]u8 = slice;\n"
        "    var cp: [*]const u8 = slice;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(SliceToPointer_Argument) {
    const char* source =
        "extern fn puts(s: [*]const u8) i32;\n"
        "fn foo(slice: []u8) void {\n"
        "    _ = puts(slice);\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(SliceToPointer_Return) {
    const char* source =
        "fn foo(slice: []u8) [*]u8 {\n"
        "    return slice;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(ArrayToPointer_Direct) {
    const char* source =
        "fn foo() void {\n"
        "    var arr: [5]u8 = undefined;\n"
        "    var p: [*]u8 = arr;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(SliceToPointer_ConstRejection) {
    const char* source =
        "fn foo(slice: []const u8) void {\n"
        "    var p: [*]u8 = slice;\n"
        "}\n";

    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(SliceToPointer_ArithmeticRejection) {
    const char* source =
        "fn foo(slice: []u8) void {\n"
        "    var p = slice + 1;\n"
        "}\n";

    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}
