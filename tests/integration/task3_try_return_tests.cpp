#include "test_framework.hpp"
#include "test_utils.hpp"
#include "integration/test_compilation_unit.hpp"
#include "platform.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>

static bool run_command_task3(const char* cmd) {
    int res = system(cmd);
    return res == 0;
}

static bool run_integration_test_task3(const char* source, const char* expected_output, const char* test_name) {
    ArenaAllocator arena(1024 * 1024 * 16);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* std_debug_source =
        "extern fn __bootstrap_print(s: *const u8) void;\n"
        "extern fn __bootstrap_print_int(i: i32) void;\n"
        "pub fn print(fmt: *const u8, args: anytype) void {\n"
        "    // lowered by compiler\n"
        "}\n";
    const char* std_source = "pub const debug = @import(\"std_debug.zig\");\n";

    u32 id_debug = unit.addSource("std_debug.zig", std_debug_source);
    u32 id_std = unit.addSource("std.zig", std_source);
    u32 id_main = unit.addSource("main.zig", source);

    unit.setCurrentModule("std_debug");
    if (!unit.performFullPipeline(id_debug)) { unit.getErrorHandler().printErrors(); return false; }
    unit.setCurrentModule("std");
    if (!unit.performFullPipeline(id_std)) { unit.getErrorHandler().printErrors(); return false; }
    unit.setCurrentModule("main");
    if (!unit.performFullPipeline(id_main)) { unit.getErrorHandler().printErrors(); return false; }

    char dir[256];
    sprintf(dir, "temp_%s", test_name);
    char cmd[1024];
    sprintf(cmd, "rm -rf %s && mkdir %s", dir, dir);
    run_command_task3(cmd);

    char dummy_path[512];
    sprintf(dummy_path, "%s/output.c", dir);
    if (!unit.generateCode(dummy_path)) {
        plat_print_error("generateCode failed\n");
        return false;
    }

    sprintf(cmd, "cp src/include/zig_runtime.h %s/ 2>/dev/null || copy src\\include\\zig_runtime.h %s\\", dir, dir);
    run_command_task3(cmd);
    sprintf(cmd, "cp src/runtime/zig_runtime.c %s/ 2>/dev/null || copy src\\runtime\\zig_runtime.c %s\\", dir, dir);
    run_command_task3(cmd);

    char exe[512];
    sprintf(exe, "%s/%s_bin", dir, test_name);

    // Try various GCC invocations to handle different module structures
    sprintf(cmd, "gcc -std=c89 -pedantic -Wno-pointer-sign -I%s -o %s %s/main.c %s/zig_runtime.c", dir, exe, dir, dir);
    if (!run_command_task3(cmd)) {
        sprintf(cmd, "gcc -std=c89 -pedantic -Wno-pointer-sign -I%s -o %s %s/main_module.c %s/std_debug.c %s/std.c %s/zig_runtime.c", dir, exe, dir, dir, dir, dir);
        if (!run_command_task3(cmd)) {
             plat_print_error("Failed to compile generated C code for ");
             plat_print_error(test_name);
             plat_print_error("\n");
             return false;
        }
    }

    char output_txt[512];
    sprintf(output_txt, "%s/output.txt", dir);
    sprintf(cmd, "%s >%s 2>&1", exe, output_txt);
    run_command_task3(cmd);

    char* buffer = NULL;
    size_t size = 0;
    if (!plat_file_read(output_txt, &buffer, &size)) {
        return false;
    }

    bool success = (buffer && strstr(buffer, expected_output) != NULL);
    if (!success) {
        plat_print_error("Expected output '");
        plat_print_error(expected_output);
        plat_print_error("' not found in ");
        plat_print_error(test_name);
        plat_print_error(". Got:\n");
        if (buffer) plat_print_error(buffer);
        else plat_print_error("<empty>\n");
    }
    if (buffer) plat_free(buffer);

    return success;
}

TEST_FUNC(Integration_Return_Try_I32) {
    const char* source =
        "const std = @import(\"std.zig\");\n"
        "fn mayFail(fail: bool) !i32 {\n"
        "    if (fail) { return error.Oops; }\n"
        "    return 42;\n"
        "}\n"
        "fn wrapper(fail: bool) !i32 {\n"
        "    return try mayFail(fail);\n"
        "}\n"
        "pub fn main() void {\n"
        "    const res1 = wrapper(false) catch 0;\n"
        "    const res2 = wrapper(true) catch 99;\n"
        "    std.debug.print(\"{}, {}\\n\", .{res1, res2});\n"
        "}\n";
    return run_integration_test_task3(source, "42, 99\n", "Integration_Return_Try_I32");
}

TEST_FUNC(Integration_Return_Try_Void) {
    const char* source =
        "const std = @import(\"std.zig\");\n"
        "fn mayFail(fail: bool) !void {\n"
        "    if (fail) { return error.Oops; }\n"
        "    return;\n"
        "}\n"
        "fn wrapper(fail: bool) !void {\n"
        "    return try mayFail(fail);\n"
        "}\n"
        "pub fn main() void {\n"
        "    var ok: i32 = 0;\n"
        "    wrapper(false) catch {};\n"
        "    ok = 1;\n"
        "    var err: i32 = 0;\n"
        "    wrapper(true) catch {};\n"
        "    err = 1;\n"
        "    std.debug.print(\"{}, {}\\n\", .{ok, err});\n"
        "}\n";
    return run_integration_test_task3(source, "1, 1\n", "Integration_Return_Try_Void");
}

TEST_FUNC(Integration_Return_Try_In_Expression) {
    const char* source =
        "const std = @import(\"std.zig\");\n"
        "fn mayFail() !i32 {\n"
        "    return 10;\n"
        "}\n"
        "fn wrapper() !i32 {\n"
        "    // This should NOT use the special wrapping because try is not a direct child of return\n"
        "    return (try mayFail()) + 5;\n"
        "}\n"
        "pub fn main() void {\n"
        "    const res = wrapper() catch 0;\n"
        "    std.debug.print(\"{}\\n\", .{res});\n"
        "}\n";
    return run_integration_test_task3(source, "15\n", "Integration_Return_Try_In_Expression");
}
