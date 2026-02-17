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

TEST_FUNC(EndToEnd_HelloWorld) {
    ArenaAllocator arena(1024 * 1024 * 4);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* std_debug_source =
        "extern fn __bootstrap_print(s: *const u8) void;\n"
        "pub fn print(msg: *const u8) void {\n"
        "    __bootstrap_print(msg);\n"
        "}\n";

    const char* std_source =
        "pub const debug = @import(\"std_debug.zig\");\n";

    const char* greetings_source =
        "const std = @import(\"std.zig\");\n"
        "pub fn sayHello() void {\n"
        "    std.debug.print(\"Hello, world!\\n\");\n"
        "}\n";

    const char* main_source =
        "const greetings = @import(\"greetings.zig\");\n"
        "pub fn main() void {\n"
        "    greetings.sayHello();\n"
        "}\n";

    u32 id1 = unit.addSource("std_debug.zig", std_debug_source);
    u32 id2 = unit.addSource("std.zig", std_source);
    u32 id3 = unit.addSource("greetings.zig", greetings_source);
    u32 id4 = unit.addSource("main.zig", main_source);

    // Compile all
    unit.setCurrentModule("std_debug");
    if (!unit.performFullPipeline(id1)) {
        plat_print_error("Failed std_debug\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    unit.setCurrentModule("std");
    if (!unit.performFullPipeline(id2)) {
        plat_print_error("Failed std\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    unit.setCurrentModule("greetings");
    if (!unit.performFullPipeline(id3)) {
        plat_print_error("Failed greetings\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    unit.setCurrentModule("main");
    if (!unit.performFullPipeline(id4)) {
        plat_print_error("Failed main\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    // Generate C code
    run_command("mkdir temp_hello 2>/dev/null || mkdir temp_hello");
    if (!unit.generateCode("temp_hello/output.c")) return false;

    // Copy runtime files (portable version)
    run_command("cp src/include/zig_runtime.h temp_hello/ 2>/dev/null || copy src\\include\\zig_runtime.h temp_hello\\");
    run_command("cp src/runtime/zig_runtime.c temp_hello/ 2>/dev/null || copy src\\runtime\\zig_runtime.c temp_hello\\");

    // Compile with GCC
    if (!run_command("gcc -std=c89 -pedantic -Wno-pointer-sign -Itemp_hello -o temp_hello/hello temp_hello/main.c temp_hello/zig_runtime.c")) {
        plat_print_error("Failed to compile generated C code\n");
        return false;
    }

    // Run and capture output portably
    run_command("./temp_hello/hello 2>temp_hello/output.txt");

    char* buffer = NULL;
    size_t size = 0;
    if (!plat_file_read("temp_hello/output.txt", &buffer, &size)) {
        plat_print_error("Failed to read output.txt\n");
        return false;
    }

    if (buffer && strstr(buffer, "Hello, world!") != NULL) {
        plat_print_info("End-to-End Hello World PASSED\n");
        plat_free(buffer);
        return true;
    } else {
        plat_print_error("Output mismatch: ");
        if (buffer) plat_print_error(buffer);
        else plat_print_error("(null)");
        if (buffer) plat_free(buffer);
        return false;
    }
}

TEST_FUNC(EndToEnd_PrimeNumbers) {
    ArenaAllocator arena(1024 * 1024 * 4);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* std_debug_source =
        "extern fn __bootstrap_print_int(n: i32) void;\n"
        "pub fn printInt(n: i32) void {\n"
        "    __bootstrap_print_int(n);\n"
        "}\n";

    const char* std_source =
        "pub const debug = @import(\"std_debug.zig\");\n";

    const char* main_source =
        "const std = @import(\"std.zig\");\n"
        "fn isPrime(n: u32) bool {\n"
        "    if (n < 2) { return false; }\n"
        "    var i: u32 = 2;\n"
        "    while (i * i <= n) {\n"
        "        if (n % i == 0) { return false; }\n"
        "        i += 1;\n"
        "    }\n"
        "    return true;\n"
        "}\n"
        "pub fn main() void {\n"
        "    var i: u32 = 1;\n"
        "    while (i <= 10) {\n"
        "        if (isPrime(i)) {\n"
        "            std.debug.printInt(@intCast(i32, i));\n"
        "        }\n"
        "        i += 1;\n"
        "    }\n"
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

    run_command("mkdir temp_prime 2>/dev/null || mkdir temp_prime");
    if (!unit.generateCode("temp_prime/output.c")) return false;
    run_command("cp src/include/zig_runtime.h temp_prime/ 2>/dev/null || copy src\\include\\zig_runtime.h temp_prime\\");
    run_command("cp src/runtime/zig_runtime.c temp_prime/ 2>/dev/null || copy src\\runtime\\zig_runtime.c temp_prime\\");

    if (!run_command("gcc -std=c89 -pedantic -Wno-pointer-sign -Itemp_prime -o temp_prime/prime temp_prime/main.c temp_prime/zig_runtime.c")) {
        plat_print_error("Failed to compile prime code\n");
        return false;
    }

    run_command("./temp_prime/prime 2>temp_prime/output.txt");

    char* buffer = NULL;
    size_t size = 0;
    if (!plat_file_read("temp_prime/output.txt", &buffer, &size)) {
        plat_print_error("Failed to read output.txt\n");
        return false;
    }

    if (buffer && strstr(buffer, "2357") != NULL) {
        plat_print_info("End-to-End Prime Numbers PASSED\n");
        plat_free(buffer);
        return true;
    } else {
        plat_print_error("Output mismatch: ");
        if (buffer) plat_print_error(buffer);
        else plat_print_error("(null)");
        if (buffer) plat_free(buffer);
        return false;
    }
}
