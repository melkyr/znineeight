#include "test_utils.hpp"
#include "test_declarations.hpp"
#include "test_compilation_unit.hpp"
#include "platform.hpp"
#include "utils.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>

TEST_FUNC(Phase3_ErrorUnionRecursion) {
    ArenaAllocator arena(1024 * 1024 * 2);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "pub const Node = struct {\n"
        "    next: ?*Node,\n"
        "};\n"
        "pub fn get_node() !Node {\n"
        "    return undefined;\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    unit.setCurrentModule("test");
    if (!unit.performFullPipeline(file_id)) {
        plat_print_debug("Failed to compile test.zig\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    // Generate code
    system("mkdir -p phase3_output");
    if (!unit.generateCode("phase3_output/output.c")) {
        plat_print_debug("Failed to generate code\n");
        return false;
    }

    // Check test.h content
    char* content = (char*)malloc(10000);
    PlatFile f_h = plat_open_file("phase3_output/test.h", false);
    if (f_h == PLAT_INVALID_FILE) {
        plat_print_debug("Failed to open generated header test.h\n");
        free(content);
        return false;
    }
    size_t bytes = plat_read_file_raw(f_h, content, 9999);
    content[bytes] = '\0';
    plat_close_file(f_h);

    const char* struct_def = "struct zS_1_Node {";
    const char* mangled_error_union = "ErrorUnion_zS_1_Node";

    char* struct_ptr = strstr(content, struct_def);
    char* error_union_ptr = strstr(content, mangled_error_union);

    if (!struct_ptr) {
        plat_print_debug("struct z_test_Node not found in header\n");
        plat_print_debug(content);
        free(content);
        return false;
    }

    if (!error_union_ptr) {
        plat_print_debug("ErrorUnion_z_test_Node not found in header\n");
        plat_print_debug(content);
        free(content);
        return false;
    }

    if (error_union_ptr < struct_ptr) {
        plat_print_debug("FAIL: ErrorUnion emitted BEFORE struct Node\n");
        // This is the BUG we want to fix.
        free(content);
        return false;
    }

    free(content);
    plat_print_info("Phase3_ErrorUnionRecursion PASSED\n");
    return true;
}
