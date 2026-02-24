#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file tagged_union_tests.cpp
 * @brief Integration tests for Zig tagged unions and switch captures.
 */

TEST_FUNC(TaggedUnion_BasicSwitch) {
    const char* source =
        "const Tag = enum { a, b };\n"
        "const U = union(Tag) { a: i32, b: f32 };\n"
        "fn foo(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .a => |val| val,\n"
        "        .b => |val| 0,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(TaggedUnion_ExplicitEnumCustomValues) {
    const char* source =
        "const Tag = enum(i32) { a = 100, b = 200 };\n"
        "const U = union(Tag) { a: i32, b: f32 };\n"
        "fn foo(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .a => |val| val,\n"
        "        .b => |_| 0,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(TaggedUnion_ImplicitEnum) {
    const char* source =
        "const U = union(enum) { a: i32, b: f32 };\n"
        "fn foo(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .a => |val| val,\n"
        "        .b => |_| 0,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(TaggedUnion_ElseProng) {
    const char* source =
        "const U = union(enum) { a: i32, b: f32, c: bool };\n"
        "fn foo(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .a => |val| val,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(TaggedUnion_CaptureImmutability) {
    const char* source =
        "const U = union(enum) { a: i32 };\n"
        "fn foo(u: U) void {\n"
        "    switch (u) {\n"
        "        .a => |val| {\n"
        "            val = 42;\n"
        "        },\n"
        "        else => {},\n"
        "    }\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    // This should fail during type checking
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected type error for immutable capture assignment, but succeeded.\n");
        return false;
    }

    // Verify the error message
    bool found_error = false;
    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (strstr(errors[i].message, "l-value is const")) {
            found_error = true;
            break;
        }
    }

    if (!found_error) {
        printf("FAIL: Did not find expected error message about immutable capture.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}
