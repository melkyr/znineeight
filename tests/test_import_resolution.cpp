#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "platform.hpp"
#include "utils.hpp"

static void write_test_file(const char* path, const char* content) {
    PlatFile f = plat_open_file(path, true);
    if (f != PLAT_INVALID_FILE) {
        plat_write_file(f, content, plat_strlen(content));
        plat_close_file(f);
    }
}

TEST_FUNC(ImportResolution_Basic) {
    plat_mkdir("test_basic");
    write_test_file("test_basic/main.zig", "const other = @import(\"other.zig\"); pub fn main() void {}");
    write_test_file("test_basic/other.zig", "pub const x = 1;");

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    char* source = NULL;
    size_t size = 0;
    if (!plat_file_read("test_basic/main.zig", &source, &size)) return false;

    u32 file_id = unit.addSource("test_basic/main.zig", source);
    bool success = unit.performFullPipeline(file_id);

    plat_free(source);
    plat_delete_file("test_basic/main.zig");
    plat_delete_file("test_basic/other.zig");
    // rmdir("test_basic"); // Not in platform.hpp

    ASSERT_TRUE(success);
    ASSERT_TRUE(unit.getModule("other") != NULL);
    return true;
}

TEST_FUNC(ImportResolution_IncludePath) {
    plat_mkdir("test_inc_root");
    plat_mkdir("test_inc_root/inc");
    write_test_file("test_inc_root/main.zig", "const ext = @import(\"ext.zig\"); pub fn main() void {}");
    write_test_file("test_inc_root/inc/ext.zig", "pub const y = 2;");

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.addIncludePath("test_inc_root/inc");

    char* source = NULL;
    size_t size = 0;
    if (!plat_file_read("test_inc_root/main.zig", &source, &size)) return false;

    u32 file_id = unit.addSource("test_inc_root/main.zig", source);
    bool success = unit.performFullPipeline(file_id);

    plat_free(source);
    plat_delete_file("test_inc_root/main.zig");
    plat_delete_file("test_inc_root/inc/ext.zig");

    ASSERT_TRUE(success);
    ASSERT_TRUE(unit.getModule("ext") != NULL);
    return true;
}

TEST_FUNC(ImportResolution_DefaultLib) {
    // We expect the executable to be in the current directory during tests
    plat_mkdir("lib");
    write_test_file("lib/std_mock.zig", "pub const z = 3;");

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source = "const std = @import(\"std_mock.zig\"); pub fn main() void {}";
    u32 file_id = unit.addSource("test_lib.zig", source);

    bool success = unit.performFullPipeline(file_id);

    plat_delete_file("lib/std_mock.zig");

    ASSERT_TRUE(success);
    ASSERT_TRUE(unit.getModule("std_mock") != NULL);
    return true;
}

TEST_FUNC(ImportResolution_PrecedenceLocal) {
    plat_mkdir("test_prec");
    plat_mkdir("test_prec/inc");
    write_test_file("test_prec/main.zig", "const mod = @import(\"mod.zig\"); pub fn main() void {}");
    write_test_file("test_prec/mod.zig", "pub const source = 1;"); // Local
    write_test_file("test_prec/inc/mod.zig", "pub const source = 2;"); // -I path

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.addIncludePath("test_prec/inc");

    char* source = NULL;
    size_t size = 0;
    if (!plat_file_read("test_prec/main.zig", &source, &size)) return false;

    u32 file_id = unit.addSource("test_prec/main.zig", source);
    bool success = unit.performFullPipeline(file_id);

    plat_free(source);

    ASSERT_TRUE(success);
    Module* m = unit.getModule("mod");
    ASSERT_TRUE(m != NULL);

    // Check that it's the local one.
    // On Linux/POSIX it should be "test_prec/mod.zig"
    // Since we normalize paths, we can check if it contains "inc"
    const char* p = m->filename;
    bool found_inc = false;
    while (*p) {
        if (plat_strncmp(p, "inc", 3) == 0) {
            found_inc = true;
            break;
        }
        p++;
    }
    ASSERT_FALSE(found_inc);

    plat_delete_file("test_prec/main.zig");
    plat_delete_file("test_prec/mod.zig");
    plat_delete_file("test_prec/inc/mod.zig");
    return true;
}

TEST_FUNC(ImportResolution_NotFound) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source = "const missing = @import(\"nonexistent.zig\");";
    u32 file_id = unit.addSource("bad.zig", source);

    bool success = unit.performFullPipeline(file_id);

    ASSERT_FALSE(success);
    ASSERT_TRUE(unit.getErrorHandler().hasErrors());
    return true;
}
