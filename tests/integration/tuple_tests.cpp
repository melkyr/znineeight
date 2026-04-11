#include "test_utils.hpp"
#include "test_declarations.hpp"
#include "compilation_unit.hpp"
#include "platform.hpp"
#include "utils.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>

static bool run_command(const char* cmd) {
    int res = system(cmd);
    return res == 0;
}

TEST_FUNC(Tuple_Basic) {
    ArenaAllocator arena(1024 * 1024 * 4);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* std_debug_source =
        "extern fn __bootstrap_print(s: *const c_char) void;\n"
        "extern fn __bootstrap_print_int(n: i32) void;\n"
        "pub fn print(fmt: *const c_char, args: anytype) void {\n"
        "    // lowered by compiler\n"
        "}\n";

    const char* std_source =
        "pub const debug = @import(\"std_debug.zig\");\n";

    const char* main_source =
        "const std = @import(\"std.zig\");\n"
        "fn takeTuple(t: struct {i32, bool}) void {\n"
        "    std.debug.print(\"Function: {}-{}\\n\", .{ t.0, t.1 });\n"
        "}\n"
        "pub fn main() void {\n"
        "    const empty = .{};\n"
        "    _ = empty;\n"
        "    std.debug.print(\"Empty: .{}!\\n\", .{1});\n"
        "\n"
        "    const simple = .{ 1, 2, 3 };\n"
        "    std.debug.print(\"Simple: {}-{}-{}\\n\", .{ simple.0, simple.1, simple.2 });\n"
        "\n"
        "    var mutable_tuple = .{ 100, 200 };\n"
        "    mutable_tuple = .{ 300, 400 };\n"
        "    std.debug.print(\"Mutable: {}-{}\\n\", .{ mutable_tuple.0, mutable_tuple.1 });\n"
        "\n"
        "    takeTuple(.{ 500, true });\n"
        "}\n";

    u32 id1 = unit.addSource("std_debug.zig", std_debug_source);
    u32 id2 = unit.addSource("std.zig", std_source);
    u32 id3 = unit.addSource("main.zig", main_source);

    unit.setCurrentModule("std_debug");
    if (!unit.performFullPipeline(id1)) { unit.getErrorHandler().printErrors(); return false; }
    unit.setCurrentModule("std");
    if (!unit.performFullPipeline(id2)) { unit.getErrorHandler().printErrors(); return false; }
    unit.setCurrentModule("main");
    if (!unit.performFullPipeline(id3)) { unit.getErrorHandler().printErrors(); return false; }

    run_command("mkdir temp_tuple 2>/dev/null || mkdir temp_tuple");
    if (!unit.generateCode("temp_tuple/output.c")) return false;
    run_command("cp src/include/zig_runtime.h temp_tuple/ 2>/dev/null || copy src\\include\\zig_runtime.h temp_tuple\\");
    run_command("cp src/runtime/zig_runtime.c temp_tuple/ 2>/dev/null || copy src\\runtime\\zig_runtime.c temp_tuple\\");
    run_command("cp zig_compat.h temp_tuple/ 2>/dev/null || copy zig_compat.h temp_tuple\\");
    run_command("cp zig_special_types.h temp_tuple/ 2>/dev/null || copy zig_special_types.h temp_tuple\\");

    if (!run_command("cd temp_tuple && sh build_target.sh")) {
        plat_print_error("Failed to compile tuple code via build_target.sh\n");
        return false;
    }

    run_command("./temp_tuple/app >temp_tuple/output.txt 2>&1");

    char* buffer = NULL;
    size_t size = 0;
    if (!plat_file_read("temp_tuple/output.txt", &buffer, &size)) {
        plat_print_error("Failed to read output.txt\n");
        return false;
    }

    const char* expected = 
        "Empty: .1!\n"
        "Simple: 1-2-3\n"
        "Mutable: 300-400\n"
        "Function: 500-1\n";

    if (buffer && strstr(buffer, expected) != NULL) {
        plat_print_info("Tuple Basic integration test PASSED\n");
        plat_free(buffer);
        return true;
    } else {
        plat_print_error("Output mismatch\n");
        if (buffer) plat_print_error(buffer);
        if (buffer) plat_free(buffer);
        return false;
    }
}
