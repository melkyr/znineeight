#include "test_framework.hpp"
#include "compilation_unit.hpp"

TEST_FUNC(RecursiveTypes_SelfRecursiveStruct) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "const Node = struct {\n"
        "    value: i32,\n"
        "    next: *Node,\n"
        "};\n"
        "fn main() void {\n"
        "    var n: Node = undefined;\n"
        "    n.value = 1;\n"
        "    n.next = &n;\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    unit.performFullPipeline(file_id);

    return !unit.getErrorHandler().hasErrors();
}

TEST_FUNC(RecursiveTypes_MutualRecursiveStructs) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "const A = struct {\n"
        "    b: *B,\n"
        "};\n"
        "const B = struct {\n"
        "    a: *A,\n"
        "};\n"
        "fn main() void {\n"
        "    var a: A = undefined;\n"
        "    var b: B = undefined;\n"
        "    a.b = &b;\n"
        "    b.a = &a;\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    unit.performFullPipeline(file_id);

    return !unit.getErrorHandler().hasErrors();
}

TEST_FUNC(RecursiveTypes_RecursiveSlice) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "const JsonValue = struct {\n"
        "    tag: i32,\n"
        "    children: []JsonValue,\n"
        "};\n"
        "fn main() void {\n"
        "    var j: JsonValue = undefined;\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    unit.performFullPipeline(file_id);

    return !unit.getErrorHandler().hasErrors();
}

TEST_FUNC(RecursiveTypes_IllegalDirectRecursion) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "const Node = struct {\n"
        "    inner: Node,\n"
        "};\n";

    u32 file_id = unit.addSource("test.zig", source);
    unit.performFullPipeline(file_id);

    return unit.getErrorHandler().hasErrors(); // We expect errors
}
