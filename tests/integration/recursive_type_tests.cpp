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

TEST_FUNC(RecursiveTypes_CrossModuleCircular) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    // a.zig
    FILE* fa = fopen("a_circular.zig", "w");
    fprintf(fa, "const b = @import(\"b_circular.zig\");\n");
    fprintf(fa, "pub const A = struct { b: *b.B };\n");
    fclose(fa);

    // b.zig
    FILE* fb = fopen("b_circular.zig", "w");
    fprintf(fb, "const a = @import(\"a_circular.zig\");\n");
    fprintf(fb, "pub const B = struct { a: *a.A };\n");
    fclose(fb);

    const char* main_source =
        "const a = @import(\"a_circular.zig\");\n"
        "fn main() void {\n"
        "    var x: a.A = undefined;\n"
        "}\n";

    u32 main_id = unit.addSource("main_circular.zig", main_source);
    unit.addIncludePath(".");
    bool success = unit.performFullPipeline(main_id);

    remove("a_circular.zig");
    remove("b_circular.zig");

    return success && !unit.getErrorHandler().hasErrors();
}
