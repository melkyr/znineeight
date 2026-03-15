#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>

/**
 * @file recursive_slice_tests.cpp
 * @brief Integration tests for Task 9.6: Recursive Type Instability for Slices.
 */

TEST_FUNC(RecursiveSlice_MultiModule) {
    const char* a_source =
        "const b = @import(\"b.zig\");\n"
        "pub const A = struct {\n"
        "    data: []b.B,\n"
        "};\n";

    const char* b_source =
        "const a = @import(\"a.zig\");\n"
        "pub const B = struct {\n"
        "    value: i32,\n"
        "    next: ?*a.A,\n"
        "};\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    unit.addSource("a.zig", a_source);
    u32 b_id = unit.addSource("b.zig", b_source);
    unit.addIncludePath(".");

    if (!unit.performFullPipeline(b_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(RecursiveSlice_MutuallyRecursive) {
    const char* source =
        "const A = struct {\n"
        "    bs: []B,\n"
        "};\n"
        "const B = struct {\n"
        "    as: []A,\n"
        "};\n"
        "pub fn main() void {\n"
        "    var a: A = undefined;\n"
        "    var b: B = undefined;\n"
        "    _ = a;\n"
        "    _ = b;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performFullPipeline(file_id)) {
        printf("FAIL: Mutually recursive slice test failed.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(RecursiveSlice_CrossModuleMutual) {
    const char* a_source =
        "const b = @import(\"b_cross.zig\");\n"
        "pub const A = struct {\n"
        "    bs: []b.B,\n"
        "};\n";

    const char* b_source =
        "const a = @import(\"a_cross.zig\");\n"
        "pub const B = struct {\n"
        "    as: []a.A,\n"
        "};\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    unit.addSource("a_cross.zig", a_source);
    u32 b_id = unit.addSource("b_cross.zig", b_source);
    unit.addIncludePath(".");

    if (!unit.performFullPipeline(b_id)) {
        printf("FAIL: Cross-module mutual recursive slice test failed.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(RecursiveSlice_InsideUnion) {
    const char* source =
        "const JsonValue = union(enum) {\n"
        "    Object: []JsonField,\n"
        "    Array: []JsonValue,\n"
        "    String: []const u8,\n"
        "    Number: f64,\n"
        "};\n"
        "const JsonField = struct {\n"
        "    name: []const u8,\n"
        "    value: []JsonValue,\n"
        "};\n"
        "pub fn main() void {\n"
        "    var v: JsonValue = undefined;\n"
        "    _ = v;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performFullPipeline(file_id)) {
        printf("FAIL: Recursive slice inside union test failed.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(RecursiveSlice_SelfReference) {
    const char* source =
        "const JsonValue = union(enum) {\n"
        "    Object: []JsonField,\n"
        "    Array: []JsonValue,\n"
        "    String: []const u8,\n"
        "    Number: f64,\n"
        "};\n"
        "const JsonField = struct {\n"
        "    name: []const u8,\n"
        "    value: []JsonValue,\n"
        "};\n"
        "fn foo(v: JsonValue) usize {\n"
        "    return switch (v) {\n"
        "        .Array => |arr| arr.len,\n"
        "        .Object => |obj| obj.len,\n"
        "        else => @intCast(usize, 0),\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performFullPipeline(file_id)) {
        printf("FAIL: Recursive self-reference slice test failed.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}
