#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include <cstdio>
#include <cstring>

#define ASSERT_NOT_NULL(ptr) \
    if ((ptr) == NULL) { \
        printf("FAIL: %s is NULL at %s:%d\n", #ptr, __FILE__, __LINE__); \
        return false; \
    }

#define ASSERT_NULL(ptr) \
    if ((ptr) != NULL) { \
        printf("FAIL: %s is NOT NULL at %s:%d\n", #ptr, __FILE__, __LINE__); \
        return false; \
    }

TEST_FUNC(switch_inclusive_range) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "extern fn print(msg: []const u8) void;\n"
        "pub fn main() void {\n"
        "    var x: i32 = 5;\n"
        "    switch (x) {\n"
        "        1...10 => print(\"range 1-10\"),\n"
        "        else => print(\"else\"),\n"
        "    }\n"
        "}\n";

    plat_mkdir("test_output_1");
    u32 file_id = unit.addSource("test_output_1/incl.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    ASSERT_TRUE(unit.generateCode("test_output_1/unused.c"));

    PlatFile f = plat_open_file("test_output_1/incl.c", false);
    ASSERT_TRUE(f != PLAT_INVALID_FILE);
    char buffer[16384];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer) - 1);
    buffer[bytes] = '\0';
    plat_close_file(f);

    ASSERT_NOT_NULL(strstr(buffer, "case 1:"));
    ASSERT_NOT_NULL(strstr(buffer, "case 5:"));
    ASSERT_NOT_NULL(strstr(buffer, "case 10:"));
    return true;
}

TEST_FUNC(switch_exclusive_range) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "extern fn print(msg: []const u8) void;\n"
        "pub fn main() void {\n"
        "    var x: i32 = 5;\n"
        "    switch (x) {\n"
        "        1..5 => print(\"range 1-4\"),\n"
        "        else => print(\"else\"),\n"
        "    }\n"
        "}\n";

    plat_mkdir("test_output_2");
    u32 file_id = unit.addSource("test_output_2/excl.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    ASSERT_TRUE(unit.generateCode("test_output_2/unused.c"));

    PlatFile f = plat_open_file("test_output_2/excl.c", false);
    ASSERT_TRUE(f != PLAT_INVALID_FILE);
    char buffer[16384];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer) - 1);
    buffer[bytes] = '\0';
    plat_close_file(f);

    ASSERT_NOT_NULL(strstr(buffer, "case 1:"));
    ASSERT_NOT_NULL(strstr(buffer, "case 4:"));
    ASSERT_NULL(strstr(buffer, "case 5:"));
    return true;
}

TEST_FUNC(switch_mixed_ranges) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "extern fn print(msg: []const u8) void;\n"
        "pub fn main() void {\n"
        "    var x: i32 = 15;\n"
        "    switch (x) {\n"
        "        1...3, 5, 10...12 => print(\"hit\"),\n"
        "        else => print(\"else\"),\n"
        "    }\n"
        "}\n";

    plat_mkdir("test_output_3");
    u32 file_id = unit.addSource("test_output_3/mixed.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    ASSERT_TRUE(unit.generateCode("test_output_3/unused.c"));

    PlatFile f = plat_open_file("test_output_3/mixed.c", false);
    ASSERT_TRUE(f != PLAT_INVALID_FILE);
    char buffer[16384];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer) - 1);
    buffer[bytes] = '\0';
    plat_close_file(f);

    ASSERT_NOT_NULL(strstr(buffer, "case 1:"));
    ASSERT_NOT_NULL(strstr(buffer, "case 2:"));
    ASSERT_NOT_NULL(strstr(buffer, "case 3:"));
    ASSERT_NOT_NULL(strstr(buffer, "case 5:"));
    ASSERT_NOT_NULL(strstr(buffer, "case 10:"));
    ASSERT_NOT_NULL(strstr(buffer, "case 11:"));
    ASSERT_NOT_NULL(strstr(buffer, "case 12:"));
    return true;
}

TEST_FUNC(switch_enum_range) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "const Color = enum { Red, Green, Blue, Yellow, Purple };\n"
        "extern fn print(msg: []const u8) void;\n"
        "pub fn main() void {\n"
        "    var c = Color.Green;\n"
        "    switch (c) {\n"
        "        Color.Red...Color.Blue => print(\"primaryish\"),\n"
        "        else => print(\"other\"),\n"
        "    }\n"
        "}\n";

    plat_mkdir("test_output_4");
    u32 file_id = unit.addSource("test_output_4/enm.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    ASSERT_TRUE(unit.generateCode("test_output_4/unused.c"));

    PlatFile f = plat_open_file("test_output_4/enm.c", false);
    ASSERT_TRUE(f != PLAT_INVALID_FILE);
    char buffer[16384];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer) - 1);
    buffer[bytes] = '\0';
    plat_close_file(f);

    /* Assuming Red=0, Green=1, Blue=2 */
    ASSERT_NOT_NULL(strstr(buffer, "case 0:"));
    ASSERT_NOT_NULL(strstr(buffer, "case 1:"));
    ASSERT_NOT_NULL(strstr(buffer, "case 2:"));
    ASSERT_NULL(strstr(buffer, "case 3:"));
    return true;
}

TEST_FUNC(switch_large_range_fail) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "extern fn print(msg: []const u8) void;\n"
        "pub fn main() void {\n"
        "    var x: i32 = 0;\n"
        "    switch (x) {\n"
        "        0...1001 => print(\"too big\"),\n"
        "        else => print(\"else\"),\n"
        "    }\n"
        "}\n";

    u32 file_id = unit.addSource("large.zig", source);
    ASSERT_FALSE(unit.performTestPipeline(file_id));
    return true;
}

TEST_FUNC(switch_non_const_range_fail) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "extern fn print(msg: []const u8) void;\n"
        "pub fn main() void {\n"
        "    var x: i32 = 0;\n"
        "    var y: i32 = 10;\n"
        "    switch (x) {\n"
        "        0...y => print(\"non-const\"),\n"
        "        else => print(\"else\"),\n"
        "    }\n"
        "}\n";

    u32 file_id = unit.addSource("nonconst.zig", source);
    ASSERT_FALSE(unit.performTestPipeline(file_id));
    return true;
}

int main() {
    bool success = true;
    if (!test_switch_inclusive_range()) success = false;
    if (!test_switch_exclusive_range()) success = false;
    if (!test_switch_mixed_ranges()) success = false;
    if (!test_switch_enum_range()) success = false;
    if (!test_switch_large_range_fail()) success = false;
    if (!test_switch_non_const_range_fail()) success = false;

    if (success) {
        printf("ALL TESTS PASSED\n");
        return 0;
    } else {
        printf("SOME TESTS FAILED\n");
        return 1;
    }
}
