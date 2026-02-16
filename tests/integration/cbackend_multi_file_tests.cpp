#include "test_utils.hpp"
#include "test_declarations.hpp"
#include "compilation_unit.hpp"
#include "platform.hpp"
#include "utils.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>

TEST_FUNC(CBackend_MultiFile) {
    ArenaAllocator arena(1024 * 1024 * 2);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* utils_source =
        "pub const Point = struct { x: i32, y: i32 };\n"
        "pub fn add(a: i32, b: i32) i32 { return a + b; }\n";

    const char* main_source =
        "const utils = @import(\"utils.zig\");\n"
        "var int: i32 = 0;\n"
        "pub fn main() void {\n"
        "    const p = utils.Point { .x = 1, .y = 2 };\n"
        "    const sum = utils.add(p.x, p.y);\n"
        "    int = sum;\n"
        "}\n";

    u32 utils_id = unit.addSource("utils.zig", utils_source);
    u32 main_id = unit.addSource("main.zig", main_source);

    // Perform pipeline for both
    unit.setCurrentModule("utils");
    if (!unit.performFullPipeline(utils_id)) {
        plat_print_debug("Failed to compile utils.zig\n");
        exit(1);
    }

    unit.setCurrentModule("main");
    bool success = unit.performFullPipeline(main_id);
    if (!success) {
        plat_print_debug("Failed to compile main.zig\n");
        unit.getErrorHandler().printErrors();
        exit(1);
    }

    // Generate code
    system("mkdir -p test_output");
    if (!unit.generateCode("test_output/output.c")) {
        plat_print_debug("Failed to generate code\n");
        exit(1);
    }

    // Verify files exist
    PlatFile f1 = plat_open_file("test_output/main.c", false);
    PlatFile f1_mod = plat_open_file("test_output/main_module.c", false);
    PlatFile f2 = plat_open_file("test_output/main.h", false);
    PlatFile f3 = plat_open_file("test_output/utils.c", false);
    PlatFile f4 = plat_open_file("test_output/utils.h", false);

    if (f1 == PLAT_INVALID_FILE || f1_mod == PLAT_INVALID_FILE || f2 == PLAT_INVALID_FILE ||
        f3 == PLAT_INVALID_FILE || f4 == PLAT_INVALID_FILE) {
        plat_print_debug("Missing generated files\n");
        exit(1);
    }

    plat_close_file(f1);
    plat_close_file(f1_mod);
    plat_close_file(f2);
    plat_close_file(f3);
    plat_close_file(f4);

    // Check main.c (master) content for #include "main_module.c"
    char* content = (char*)malloc(10000);
    PlatFile f_main = plat_open_file("test_output/main.c", false);
    size_t bytes = plat_read_file_raw(f_main, content, 9999);
    content[bytes] = '\0';
    plat_close_file(f_main);

    if (strstr(content, "#include \"main_module.c\"") == NULL) {
        plat_print_debug("main.c missing #include \"main_module.c\"\n");
        plat_print_debug(content);
        exit(1);
    }

    if (strstr(content, "#include \"utils.c\"") == NULL) {
        plat_print_debug("main.c missing #include \"utils.c\"\n");
        plat_print_debug(content);
        exit(1);
    }

    // Check main_module.c content
    PlatFile f_main_mod = plat_open_file("test_output/main_module.c", false);
    bytes = plat_read_file_raw(f_main_mod, content, 9999);
    content[bytes] = '\0';
    plat_close_file(f_main_mod);

    if (strstr(content, "#include \"utils.h\"") == NULL) {
        plat_print_debug("main_module.c missing #include \"utils.h\"\n");
        plat_print_debug(content);
        exit(1);
    }

    if (strstr(content, "static int z_int = 0;") == NULL) {
        plat_print_debug("main_module.c missing z_int\n");
        plat_print_debug(content);
        exit(1);
    }

    if (strstr(content, "z_utils_add") == NULL) {
        plat_print_debug("main_module.c missing z_utils_add\n");
        plat_print_debug(content);
        exit(1);
    }

    // Check main.h content for #include "utils.h" (Task 209 Requirement)
    PlatFile f_main_h = plat_open_file("test_output/main.h", false);
    bytes = plat_read_file_raw(f_main_h, content, 9999);
    content[bytes] = '\0';
    plat_close_file(f_main_h);
    if (strstr(content, "#include \"utils.h\"") == NULL) {
        plat_print_debug("main.h missing #include \"utils.h\"\n");
        plat_print_debug(content);
        exit(1);
    }

    // Check utils.h for struct Point
    PlatFile f_utils_h = plat_open_file("test_output/utils.h", false);
    bytes = plat_read_file_raw(f_utils_h, content, 9999);
    content[bytes] = '\0';
    plat_close_file(f_utils_h);

    if (strstr(content, "struct z_utils_Point") == NULL) {
        plat_print_debug("utils.h missing struct z_utils_Point\n");
        plat_print_debug(content);
        exit(1);
    }

    if (strstr(content, "#include \"zig_runtime.h\"") == NULL) {
        plat_print_debug("utils.h missing #include \"zig_runtime.h\"\n");
        exit(1);
    }

    free(content);
    plat_print_info("test_CBackend_MultiFile PASSED\n");
    return true;
}
