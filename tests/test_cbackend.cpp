#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "cbackend.hpp"
#include "platform.hpp"
#include <cstdio>
#include <cstring>

TEST_FUNC(CBackend_Skeleton_MultiFile) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source1 = "pub fn main() void { }";
    const char* source2 = "pub fn helper() i32 { return 42; }";

    // Add source 1
    unit.setCurrentModule("main");
    u32 file1 = unit.addSource("main.zig", source1);
    ASSERT_TRUE(unit.performFullPipeline(file1));

    // Add source 2
    unit.setCurrentModule("utils");
    u32 file2 = unit.addSource("utils.zig", source2);
    ASSERT_TRUE(unit.performFullPipeline(file2));

    // Run CBackend
    const char* out_dir = "test_gen_dir";
    // Create directory if not exists - platform dependent but for test we can use system
#ifdef _WIN32
    system("mkdir test_gen_dir 2>nul");
#else
    system("mkdir -p test_gen_dir");
#endif

    CBackend backend(unit);
    ASSERT_TRUE(backend.generate(out_dir));

    // Verify files exist
    char path[256];

    // main.c
    plat_strcpy(path, out_dir);
    plat_strcat(path, "/main.c");
    PlatFile f = plat_open_file(path, false);
    ASSERT_TRUE(f != PLAT_INVALID_FILE);
    plat_close_file(f);

    // main.h
    plat_strcpy(path, out_dir);
    plat_strcat(path, "/main.h");
    f = plat_open_file(path, false);
    ASSERT_TRUE(f != PLAT_INVALID_FILE);
    plat_close_file(f);

    // utils.c
    plat_strcpy(path, out_dir);
    plat_strcat(path, "/utils.c");
    f = plat_open_file(path, false);
    ASSERT_TRUE(f != PLAT_INVALID_FILE);
    plat_close_file(f);

    // utils.h
    plat_strcpy(path, out_dir);
    plat_strcat(path, "/utils.h");
    f = plat_open_file(path, false);
    ASSERT_TRUE(f != PLAT_INVALID_FILE);
    plat_close_file(f);

    // Clean up
#ifdef _WIN32
    system("rd /s /q test_gen_dir");
#else
    system("rm -rf test_gen_dir");
#endif

    return true;
}
