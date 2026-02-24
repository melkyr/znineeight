#include "test_utils.hpp"
#include "test_declarations.hpp"
#include "compilation_unit.hpp"
#include "platform.hpp"
#include "utils.hpp"
#include <cstdio>
#include <cstdlib>

TEST_FUNC(Import_Simple) {
    ArenaAllocator arena(1024 * 1024 * 2);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    // Create files on disk
    const char* lib_source = "pub fn add(a: i32, b: i32) i32 { return a + b; }\n";
    FILE* f = fopen("test_lib.zig", "w");
    if (!f) return false;
    fprintf(f, "%s", lib_source);
    fclose(f);

    const char* main_source = "const lib = @import(\"test_lib.zig\");\n"
                              "pub fn main() void {\n"
                              "    _ = lib.add(1, 2);\n"
                              "}\n";

    u32 main_id = unit.addSource("test_main.zig", main_source);

    bool success = unit.performFullPipeline(main_id);

    // Cleanup files
    remove("test_lib.zig");

    ASSERT_TRUE(success);
    ASSERT_EQ(unit.getModules().length(), 2);
    return true;
}

TEST_FUNC(Import_Circular) {
    ArenaAllocator arena(1024 * 1024 * 2);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    // Create circular dependency
    // a.zig -> b.zig -> a.zig
    FILE* fa = fopen("a_circ.zig", "w");
    if (!fa) return false;
    fprintf(fa, "const b = @import(\"b_circ.zig\");\n");
    fclose(fa);

    FILE* fb = fopen("b_circ.zig", "w");
    if (!fb) return false;
    fprintf(fb, "const a = @import(\"a_circ.zig\");\n");
    fclose(fb);

    // Use a different filename to avoid collision with existing modules if any
    u32 a_id = unit.addSource("a_circ.zig", "const b = @import(\"b_circ.zig\");\n");

    bool success = unit.performFullPipeline(a_id);

    remove("a_circ.zig");
    remove("b_circ.zig");

    // Circular imports are now allowed to support mutual recursion across modules
    ASSERT_TRUE(success);
    return true;
}

TEST_FUNC(Import_Missing) {
    ArenaAllocator arena(1024 * 1024 * 2);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    u32 main_id = unit.addSource("missing_main.zig", "const lib = @import(\"nonexistent.zig\");\n");

    bool success = unit.performFullPipeline(main_id);

    ASSERT_FALSE(success);
    return true;
}
