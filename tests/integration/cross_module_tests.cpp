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

    return !unit.getErrorHandler().hasErrors();
}
