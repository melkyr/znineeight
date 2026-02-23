#include "test_framework.hpp"
#include "c89_validation/c89_validator.hpp"
#include "test_utils.hpp"
#include "integration/test_compilation_unit.hpp"
#include "platform.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>

static bool run_command_task227(const char* cmd) {
    int res = system(cmd);
    return res == 0;
}

static bool run_integration_test(const char* source, const char* expected_output, const char* test_name) {
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
    run_command_task227(cmd);

    char dummy_path[512];
    sprintf(dummy_path, "%s/output.c", dir);
    if (!unit.generateCode(dummy_path)) {
        plat_print_error("generateCode failed\n");
        return false;
    }

    sprintf(cmd, "cp src/include/zig_runtime.h %s/ 2>/dev/null || copy src\\include\\zig_runtime.h %s\\", dir, dir);
    run_command_task227(cmd);
    sprintf(cmd, "cp src/runtime/zig_runtime.c %s/ 2>/dev/null || copy src\\runtime\\zig_runtime.c %s\\", dir, dir);
    run_command_task227(cmd);

    char exe[512];
    sprintf(exe, "%s/%s_bin", dir, test_name);

    sprintf(cmd, "gcc -std=c89 -pedantic -Wno-pointer-sign -I%s -o %s %s/main.c %s/zig_runtime.c", dir, exe, dir, dir);
    if (!run_command_task227(cmd)) {
        sprintf(cmd, "gcc -std=c89 -pedantic -Wno-pointer-sign -I%s -o %s %s/main_module.c %s/std.c %s/std_debug.c %s/zig_runtime.c", dir, exe, dir, dir, dir, dir);
        if (!run_command_task227(cmd)) {
             plat_print_error("Failed to compile generated C code\n");
             return false;
        }
    }

    char output_txt[512];
    sprintf(output_txt, "%s/output.txt", dir);
    sprintf(cmd, "%s >%s 2>&1", exe, output_txt);
    run_command_task227(cmd);

    char* buffer = NULL;
    size_t size = 0;
    if (!plat_file_read(output_txt, &buffer, &size)) {
        return false;
    }

    bool success = (buffer && strstr(buffer, expected_output) != NULL);
    if (!success) {
        plat_print_error("Expected output not found in ");
        plat_print_error(test_name);
        plat_print_error(". Got:\n");
        if (buffer) plat_print_error(buffer);
        else plat_print_error("<empty>\n");
    }
    if (buffer) plat_free(buffer);

    return success;
}

TEST_FUNC(Integration_Try_Defer_LIFO) {
    const char* source =
        "const std = @import(\"std.zig\");\n"
        "var log: i32 = 0;\n"
        "fn fail() !i32 { return error.Bad; }\n"
        "fn test_try() !i32 {\n"
        "    defer { log = log * 10 + 1; }\n"
        "    defer { log = log * 10 + 2; }\n"
        "    _ = try fail();\n"
        "    return 0;\n"
        "}\n"
        "pub fn main() void {\n"
        "    _ = test_try() catch 0;\n"
        "    std.debug.print(\"{}\\n\", .{log});\n"
        "}\n";
    return run_integration_test(source, "21\n", "Integration_Try_Defer_LIFO");
}

TEST_FUNC(Integration_Nested_Try_Catch) {
    const char* source =
        "const std = @import(\"std.zig\");\n"
        "fn fail1() !i32 { return error.Error1; }\n"
        "fn fail2() !i32 { return error.Error2; }\n"
        "fn test_nested() !i32 {\n"
        "    const x = fail1() catch |err| {\n"
        "        if (err == error.Error1) {\n"
        "             return fail2();\n"
        "        }\n"
        "        return 0;\n"
        "    };\n"
        "    return x;\n"
        "}\n"
        "pub fn main() void {\n"
        "    const res = test_nested() catch |err| if (err == error.Error2) 42 else 0;\n"
        "    std.debug.print(\"{}\\n\", .{res});\n"
        "}\n";
    return run_integration_test(source, "42\n", "Integration_Nested_Try_Catch");
}

TEST_FUNC(Integration_Try_In_Loop) {
    const char* source =
        "const std = @import(\"std.zig\");\n"
        "fn mayFail(i: i32) !i32 {\n"
        "    if (i == 3) { return error.Three; }\n"
        "    return i;\n"
        "}\n"
        "fn test_loop() !i32 {\n"
        "    var sum: i32 = 0;\n"
        "    var i: i32 = 1;\n"
        "    while (i <= 5) {\n"
        "        const val = try mayFail(i);\n"
        "        sum = sum + val;\n"
        "        i = i + 1;\n"
        "    }\n"
        "    return sum;\n"
        "}\n"
        "pub fn main() void {\n"
        "    const res = test_loop() catch 99;\n"
        "    std.debug.print(\"{}\\n\", .{res});\n"
        "}\n";
    return run_integration_test(source, "99\n", "Integration_Try_In_Loop");
}

TEST_FUNC(Integration_Catch_With_Complex_Block) {
    const char* source =
        "const std = @import(\"std.zig\");\n"
        "fn fail() !i32 { return error.Oops; }\n"
        "pub fn main() void {\n"
        "    const res = fail() catch |err| {\n"
        "        var x: i32 = 100;\n"
        "        if (err == error.Oops) {\n"
        "            x = x + 23;\n"
        "        }\n"
        "        x\n"
        "    };\n"
        "    std.debug.print(\"{}\\n\", .{res});\n"
        "}\n";
    return run_integration_test(source, "123\n", "Integration_Catch_With_Complex_Block");
}

TEST_FUNC(Integration_Catch_Basic) {
    const char* source =
        "const std = @import(\"std.zig\");\n"
        "const MyError = error { Bad, ReallyBad };\n"
        "fn fail(really: bool) !i32 {\n"
        "    if (really) {\n"
        "        return MyError.ReallyBad;\n"
        "    }\n"
        "    return MyError.Bad;\n"
        "}\n"
        "pub fn main() void {\n"
        "    const res1 = fail(false) catch 10;\n"
        "    const res2 = fail(true) catch 20;\n"
        "    const tmp1 = fail(false) catch 30;\n"
        "    const tmp2 = fail(true) catch 40;\n"
        "    const res3 = tmp1 + tmp2;\n"
        "    std.debug.print(\"{}, {}, {}\\n\", .{res1, res2, res3});\n"
        "}\n";
    return run_integration_test(source, "10, 20, 70\n", "Integration_Catch_Basic");
}

TEST_FUNC(TypeChecker_Try_Invalid) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);

    // try on non-error union
    {
        const char* source = "fn foo() void { var x: i32 = 0; _ = try x; }";
        CompilationUnit unit(arena, interner);
        u32 file_id = unit.addSource("test.zig", source);
        ASSERT_FALSE(unit.performFullPipeline(file_id));
        bool found = false;
        const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
        for (size_t i = 0; i < errors.length(); ++i) {
            if (errors[i].code == ERR_TRY_ON_NON_ERROR_UNION) found = true;
        }
        ASSERT_TRUE(found);
    }

    // try in non-error function
    {
        const char* source = "fn foo() i32 { var x: !i32 = 0; return try x; }";
        CompilationUnit unit(arena, interner);
        u32 file_id = unit.addSource("test.zig", source);
        ASSERT_FALSE(unit.performFullPipeline(file_id));
        bool found = false;
        const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
        for (size_t i = 0; i < errors.length(); ++i) {
            if (errors[i].code == ERR_TRY_IN_NON_ERROR_FUNCTION) found = true;
        }
        ASSERT_TRUE(found);
    }

    return true;
}
