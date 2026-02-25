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

TEST_FUNC(RecursiveSlice_MutualTaggedUnion) {
    plat_mkdir("test_recursive_slice");
    write_test_file("test_recursive_slice/a.zig",
        "const b = @import(\"b.zig\");\n"
        "pub const A = union(enum) {\n"
        "    Int: i32,\n"
        "    Ref: *b.B,\n"
        "    List: []A,\n"
        "};\n"
    );
    write_test_file("test_recursive_slice/b.zig",
        "const a = @import(\"a.zig\");\n"
        "pub const B = struct {\n"
        "    value: i32,\n"
        "    maybe: ?*a.A,\n"
        "};\n"
    );
    write_test_file("test_recursive_slice/main.zig",
        "const a = @import(\"a.zig\");\n"
        "const b = @import(\"b.zig\");\n"
        "const A = a.A;\n"
        "const B = b.B;\n"
        "pub fn main() void {\n"
        "    var a_val = A{ .Int = 42 };\n"
        "    var b_val = B{ .value = 10, .maybe = &a_val };\n"
        "    var list: [2]A = undefined;\n"
        "    list[0] = a_val;\n"
        "    var slice = list[0..];\n"
        "    switch (slice[0]) {\n"
        "        .Int => |x| {\n"
        "            _ = x;\n"
        "        },\n"
        "        else => {},\n"
        "    }\n"
        "}\n"
    );

    ArenaAllocator arena(16 * 1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    char* source = NULL;
    size_t size = 0;
    if (!plat_file_read("test_recursive_slice/main.zig", &source, &size)) return false;

    u32 file_id = unit.addSource("test_recursive_slice/main.zig", source);
    bool success = unit.performFullPipeline(file_id);

    plat_free(source);
    plat_delete_file("test_recursive_slice/main.zig");
    plat_delete_file("test_recursive_slice/a.zig");
    plat_delete_file("test_recursive_slice/b.zig");

    if (!success) {
        unit.getErrorHandler().printErrors();
    }
    ASSERT_TRUE(success);
    return true;
}

TEST_FUNC(RecursiveSlice_CascadingIncomplete) {
    plat_mkdir("test_cascading");
    write_test_file("test_cascading/a.zig",
        "pub const A = struct {\n"
        "    data: []B,\n"
        "};\n"
        "pub const B = struct {\n"
        "    opt: ?A,\n"
        "};\n"
        "pub fn main() void {\n"
        "    var b: B = undefined;\n"
        "    _ = b.opt;\n"
        "}\n"
    );

    ArenaAllocator arena(16 * 1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    char* source = NULL;
    size_t size = 0;
    if (!plat_file_read("test_cascading/a.zig", &source, &size)) return false;

    u32 file_id = unit.addSource("test_cascading/a.zig", source);
    bool success = unit.performFullPipeline(file_id);

    plat_free(source);
    plat_delete_file("test_cascading/a.zig");

    if (!success) {
        unit.getErrorHandler().printErrors();
    }
    ASSERT_TRUE(success);
    return true;
}
