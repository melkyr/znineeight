#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <cstring>

TEST_FUNC(UnionCapture_ForwardDeclaredStruct) {
    const char* source =
        "const S = struct {\n"
        "    x: i32,\n"
        "    u: U,\n"
        "};\n"
        "const U = union(enum) {\n"
        "    A: i32,\n"
        "    B: *const S,\n"
        "};\n"
        "fn example(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .A => |val| val,\n"
        "        .B => |ptr| ptr.x,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for UnionCapture_ForwardDeclaredStruct\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(UnionCapture_NestedUnion) {
    const char* source =
        "const Inner = union(enum) { x: i32, y: f64 };\n"
        "const Outer = union(enum) { a: Inner, b: i32 };\n"
        "fn foo(o: Outer) i32 {\n"
        "    return switch (o) {\n"
        "        .a => |inner| switch (inner) {\n"
        "            .x => |val| val,\n"
        "            .y => |_| 0,\n"
        "            else => 0,\n"
        "        },\n"
        "        .b => |val| val,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for UnionCapture_NestedUnion\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(UnionCapture_PointerToIncomplete) {
    const char* source =
        "const List = struct {\n"
        "    data: i32,\n"
        "    next: ?*List,\n"
        "};\n"
        "const U = union(enum) {\n"
        "    Node: *List,\n"
        "    Empty: void,\n"
        "};\n"
        "fn getData(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .Node => |node| node.data,\n"
        "        .Empty => 0,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for UnionCapture_PointerToIncomplete\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(UnionCapture_InvalidIntegerCase) {
    const char* source =
        "const U = union(enum) { A: i32, B: f64 };\n"
        "fn foo(u: U) void {\n"
        "    switch (u) {\n"
        "        1 => |val| { _ = val; },\n"
        "        else => {},\n"
        "    }\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    // This should fail during type checking
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected type error for invalid capture on integer case, but succeeded.\n");
        return false;
    }

    // Verify the error message
    bool found_error = false;
    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].hint && (strstr(errors[i].hint, "Capture requires a tag name case item") ||
                               strstr(errors[i].hint, "Switch case type mismatch"))) {
            found_error = true;
            break;
        }
    }

    if (!found_error) {
        printf("FAIL: Did not find expected error message about capture requiring tag name.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}
