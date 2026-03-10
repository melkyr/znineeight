#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>

/**
 * @file switch_range_tests.cpp
 * @brief Integration tests for range-based switch arms.
 */

TEST_FUNC(SwitchRange_Inclusive) {
    const char* source =
        "extern fn print_int(val: i32) void;\n"
        "pub fn main() void {\n"
        "    var x: i32 = 3;\n"
        "    switch (x) {\n"
        "        1...5 => print_int(100),\n"
        "        else => print_int(0),\n"
        "    }\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    // Since performTestPipeline includes lifting and codegen (via CBackend typically,
    // but here we just want to verify the AST structure or emission).
    // Let's verify emission if possible, or just that it passed.

    return true;
}

TEST_FUNC(SwitchRange_Exclusive) {
    const char* source =
        "extern fn print_int(val: i32) void;\n"
        "pub fn main() void {\n"
        "    var x: i32 = 5;\n"
        "    switch (x) {\n"
        "        1..5 => print_int(100),\n"
        "        else => print_int(0),\n"
        "    }\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(SwitchRange_ErrorNonConstant) {
    const char* source =
        "pub fn main() void {\n"
        "    var x: i32 = 3;\n"
        "    var a: i32 = 1;\n"
        "    switch (x) {\n"
        "        a...5 => {},\n"
        "        else => {},\n"
        "    }\n"
        "}";

    if (!expect_type_checker_abort(source)) {
        printf("FAIL: Expected type checker to abort for non-constant range bound\n");
        return false;
    }
    return true;
}

TEST_FUNC(SwitchRange_ErrorCaptureWithRange) {
    const char* source =
        "const U = union(enum) { A: i32, B: i32, C: i32 };\n"
        "pub fn main() void {\n"
        "    var u = U{ .A = 42 };\n"
        "    switch (u) {\n"
        "        U.A...U.B => |val| { _ = val; },\n"
        "        else => {},\n"
        "    }\n"
        "}";

    if (!expect_type_checker_abort(source)) {
        printf("FAIL: Expected type checker to abort for capture with range\n");
        return false;
    }
    return true;
}

TEST_FUNC(SwitchRange_ErrorEmpty) {
    const char* source =
        "pub fn main() void {\n"
        "    var x: i32 = 5;\n"
        "    switch (x) {\n"
        "        5...3 => {},\n"
        "        else => {},\n"
        "    }\n"
        "}";

    if (!expect_type_checker_abort(source)) {
        printf("FAIL: Expected type checker to abort for empty/inverted range\n");
        return false;
    }
    return true;
}

TEST_FUNC(SwitchRange_ErrorTooLarge) {
    const char* source =
        "pub fn main() void {\n"
        "    var x: i32 = 5;\n"
        "    switch (x) {\n"
        "        0...1001 => {},\n"
        "        else => {},\n"
        "    }\n"
        "}";

    if (!expect_type_checker_abort(source)) {
        printf("FAIL: Expected type checker to abort for too large range\n");
        return false;
    }
    return true;
}
