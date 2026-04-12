#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>

TEST_FUNC(TaggedUnion_ArrayDecomposition) {
    const char* source =
        "const Cell = union(enum) { Alive: void, Dead: void };\n"
        "pub fn main() void {\n"
        "    var arr: [2]Cell = .{ .Alive, .Dead };\n"
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

TEST_FUNC(TaggedUnion_NestedIfExpr) {
    const char* source =
        "const Cell = union(enum) { A: void, B: void, C: void };\n"
        "pub fn main() void {\n"
        "    var a = true;\n"
        "    var b = false;\n"
        "    var x: Cell = if (a) (if (b) .A else .B) else .C;\n"
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

TEST_FUNC(TaggedUnion_NestedSwitchExpr) {
    const char* source =
        "const Cell = union(enum) { A: void, B: void, C: void };\n"
        "pub fn main() void {\n"
        "    var a = 1;\n"
        "    var x: Cell = switch (a) {\n"
        "        1 => switch (a) { 1 => .A, else => .B },\n"
        "        else => .C,\n"
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
