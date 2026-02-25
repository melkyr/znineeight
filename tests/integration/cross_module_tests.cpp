#include "test_framework.hpp"
#include "compilation_unit.hpp"

TEST_FUNC(CrossModule_EnumAccess) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* main_source =
        "const json = @import(\"json.zig\");\n"
        "fn main() void {\n"
        "    var t: json.JsonValueTag = json.JsonValueTag.Number;\n"
        "    var v: json.JsonValue = undefined;\n"
        "    v.tag = t;\n"
        "}\n";

    u32 main_id = unit.addSource("main.zig", main_source);

    // Add current directory to include paths for json.zig
    unit.addIncludePath(".");

    unit.performFullPipeline(main_id);

    if (unit.getErrorHandler().hasErrors()) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(CrossModule_FunctionSignature) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    // a.zig
    const char* a_source = "pub const Point = struct { x: i32, y: i32 };\n";
    FILE* fa = fopen("a.zig", "w");
    fprintf(fa, "%s", a_source);
    fclose(fa);

    const char* main_source =
        "const a = @import(\"a.zig\");\n"
        "fn process(p: a.Point) a.Point {\n"
        "    return p;\n"
        "}\n"
        "fn main() void {\n"
        "    var p: a.Point = .{ .x = 1, .y = 2 };\n"
        "    _ = process(p);\n"
        "}\n";

    u32 main_id = unit.addSource("main.zig", main_source);
    unit.addIncludePath(".");
    bool success = unit.performFullPipeline(main_id);

    remove("a.zig");
    return success && !unit.getErrorHandler().hasErrors();
}

TEST_FUNC(CrossModule_ArrayAndPointer) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* a_source = "pub const Point = struct { x: i32, y: i32 };\n";
    FILE* fa = fopen("a.zig", "w");
    fprintf(fa, "%s", a_source);
    fclose(fa);

    const char* main_source =
        "const a = @import(\"a.zig\");\n"
        "fn main() void {\n"
        "    var arr: [10]a.Point = undefined;\n"
        "    var ptr: *a.Point = &arr[0];\n"
        "    _ = ptr;\n"
        "}\n";

    u32 main_id = unit.addSource("main.zig", main_source);
    unit.addIncludePath(".");
    bool success = unit.performFullPipeline(main_id);

    remove("a.zig");
    return success && !unit.getErrorHandler().hasErrors();
}

TEST_FUNC(CrossModule_TypeAlias) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* a_source = "pub const Point = struct { x: i32, y: i32 };\n";
    FILE* fa = fopen("a.zig", "w");
    fprintf(fa, "%s", a_source);
    fclose(fa);

    const char* main_source =
        "const a = @import(\"a.zig\");\n"
        "const MyPoint = a.Point;\n"
        "fn main() void {\n"
        "    var p: MyPoint = .{ .x = 1, .y = 2 };\n"
        "    _ = p;\n"
        "}\n";

    u32 main_id = unit.addSource("main.zig", main_source);
    unit.addIncludePath(".");
    bool success = unit.performFullPipeline(main_id);

    remove("a.zig");
    return success && !unit.getErrorHandler().hasErrors();
}

TEST_FUNC(CrossModule_NestedModules) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    // c.zig
    FILE* fc = fopen("c.zig", "w");
    fprintf(fc, "pub const DeepType = struct { val: i32 };\n");
    fclose(fc);

    // b.zig
    FILE* fb = fopen("b.zig", "w");
    fprintf(fb, "pub const c = @import(\"c.zig\");\n");
    fclose(fb);

    // a.zig
    FILE* fa = fopen("a.zig", "w");
    fprintf(fa, "pub const b = @import(\"b.zig\");\n");
    fclose(fa);

    const char* main_source =
        "const a = @import(\"a.zig\");\n"
        "fn main() void {\n"
        "    var x: a.b.c.DeepType = .{ .val = 42 };\n"
        "    _ = x;\n"
        "}\n";

    u32 main_id = unit.addSource("main.zig", main_source);
    unit.addIncludePath(".");
    bool success = unit.performFullPipeline(main_id);

    remove("a.zig");
    remove("b.zig");
    remove("c.zig");
    return success && !unit.getErrorHandler().hasErrors();
}

TEST_FUNC(CrossModule_ErrorCases) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    FILE* fa = fopen("a.zig", "w");
    fprintf(fa, "pub const Point = struct { x: i32, y: i32 };\n");
    fclose(fa);

    const char* main_source =
        "const a = @import(\"a.zig\");\n"
        "fn main() void {\n"
        "    var y: a.UnknownType = undefined;\n" // Error: member not found
        "    var z: a = undefined;\n"           // Error: module is not a type
        "}\n";

    u32 main_id = unit.addSource("main.zig", main_source);
    unit.addIncludePath(".");
    unit.performFullPipeline(main_id);

    remove("a.zig");
    // Expecting 2 errors
    return unit.getErrorHandler().hasErrors();
}
