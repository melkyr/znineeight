#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include "platform.hpp"

TEST_FUNC(ForwardReference_GlobalVariable) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn main() i32 { return x; }\n"
        "const x: i32 = 42;\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    ASSERT_TRUE(success);

    return true;
}

TEST_FUNC(ForwardReference_MutualFunction) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn a() void { b(); }\n"
        "fn b() void { a(); }\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    ASSERT_TRUE(success);

    return true;
}

TEST_FUNC(ForwardReference_StructType) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "const p: Point = Point { .x = 1, .y = 2 };\n"
        "const Point = struct { x: i32, y: i32 };\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    ASSERT_TRUE(success);

    return true;
}
