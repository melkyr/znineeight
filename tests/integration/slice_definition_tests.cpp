#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "compilation_unit.hpp"
#include "platform.hpp"
#include "utils.hpp"
#include "cbackend.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

/**
 * @file slice_definition_tests.cpp
 * @brief Integration tests for missing slice definitions in private functions.
 */

TEST_FUNC(SliceDefinition_PrivateFunction) {
    ArenaAllocator arena(1024 * 1024 * 2);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "fn private() void {\n"
        "    var x: []u8 = undefined;\n"
        "}\n"
        "pub fn main() void {\n"
        "    private();\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    unit.setCurrentModule("test");

    if (!unit.performFullPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    // Generate code
    system("mkdir -p slice_test_output");
    if (!unit.generateCode("slice_test_output/output.c")) {
        return false;
    }

    // Check zig_special_types.h content for Slice_u8 typedef
    PlatFile f = plat_open_file("slice_test_output/zig_special_types.h", false);
    if (f == PLAT_INVALID_FILE) {
        printf("FAIL: Failed to open generated test.c\n");
        return false;
    }

    char* content = (char*)malloc(100000);
    size_t bytes = plat_read_file_raw(f, content, 99999);
    content[bytes] = '\0';
    plat_close_file(f);

    bool found = (strstr(content, "typedef struct { unsigned char* ptr; usize len; } Slice_u8;") != NULL);

    if (!found) {
        printf("FAIL: Slice_u8 definition not found in generated C code.\n");
        // printf("Content:\n%s\n", content);
    }

    free(content);
    return found;
}

TEST_FUNC(SliceDefinition_RecursiveType) {
    ArenaAllocator arena(1024 * 1024 * 2);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "pub const Node = struct {\n"
        "    next: ?*Node,\n"
        "    data: []u8,\n"
        "};\n"
        "pub fn main() void {}\n";

    u32 file_id = unit.addSource("test.zig", source);
    unit.setCurrentModule("test");

    if (!unit.performFullPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    // Generate code
    system("mkdir -p slice_test_output_rec");
    if (!unit.generateCode("slice_test_output_rec/output.c")) {
        return false;
    }

    // Check zig_special_types.h content for Slice_u8 typedef
    PlatFile f = plat_open_file("slice_test_output_rec/zig_special_types.h", false);
    if (f == PLAT_INVALID_FILE) return false;

    char* content = (char*)malloc(100000);
    size_t bytes = plat_read_file_raw(f, content, 99999);
    content[bytes] = '\0';
    plat_close_file(f);

    bool found_slice = (strstr(content, "Slice_u8") != NULL);
    // If module is "test", it skips the z_test_ prefix.
    // Check test.h for struct definition
    plat_close_file(f);
    f = plat_open_file("slice_test_output_rec/test.h", false);
    bytes = plat_read_file_raw(f, content, 99999);
    content[bytes] = '\0';
    bool found_struct = (strstr(content, "struct Node") != NULL);

    if (!found_slice) {
        printf("FAIL: Slice_u8 definition not found for recursive struct usage.\n");
    }
    if (!found_struct) {
        printf("FAIL: Node struct definition not found in header.\n");
    }

    free(content);
    return found_slice && found_struct;
}

TEST_FUNC(SliceDefinition_NestedType) {
    ArenaAllocator arena(1024 * 1024 * 2);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "const S = struct { s: []f32 };\n"
        "fn private(ptr: *[]i32, s: S) void {\n"
        "    _ = ptr;\n"
        "    _ = s;\n"
        "}\n"
        "pub fn main() void {\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    unit.setCurrentModule("test");

    if (!unit.performFullPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    // Generate code
    system("mkdir -p slice_test_output_nested");
    if (!unit.generateCode("slice_test_output_nested/output.c")) {
        return false;
    }

    // Check zig_special_types.h content for Slice_i32 typedef
    PlatFile f = plat_open_file("slice_test_output_nested/zig_special_types.h", false);
    if (f == PLAT_INVALID_FILE) return false;

    char* content = (char*)malloc(100000);
    size_t bytes = plat_read_file_raw(f, content, 99999);
    content[bytes] = '\0';
    plat_close_file(f);

    bool found_i32 = (strstr(content, "Slice_i32") != NULL || strstr(content, "ptr_i32") != NULL);
    bool found_f32 = (strstr(content, "Slice_f32") != NULL || strstr(content, "ptr_f32") != NULL);

    if (!found_i32) {
        printf("FAIL: Slice_i32 typedef not found for nested pointer usage (*[]i32).\n");
        printf("Content:\n%s\n", content);
    }
    if (!found_f32) {
        printf("FAIL: Slice_f32 typedef not found for nested struct field usage (struct { s: []f32 }).\n");
    }

    free(content);
    return found_i32 && found_f32;
}

TEST_FUNC(SliceDefinition_PublicSignatureNested) {
    ArenaAllocator arena(1024 * 1024 * 2);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "pub fn public_func(ptr: *[]u16) void {\n"
        "    _ = ptr;\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    unit.setCurrentModule("test");

    if (!unit.performFullPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    // Generate code
    system("mkdir -p slice_test_output_pub");
    if (!unit.generateCode("slice_test_output_pub/output.c")) {
        return false;
    }

    // Check zig_special_types.h content for Slice_u16 typedef
    PlatFile f = plat_open_file("slice_test_output_pub/zig_special_types.h", false);
    if (f == PLAT_INVALID_FILE) return false;

    char* content = (char*)malloc(100000);
    size_t bytes = plat_read_file_raw(f, content, 99999);
    content[bytes] = '\0';
    plat_close_file(f);

    bool found = (strstr(content, "Slice_u16") != NULL);

    if (!found) {
        printf("FAIL: Slice_u16 definition not found in public header for nested pointer usage (*[]u16).\n");
    }

    free(content);
    return found;
}
