#include "test_runner_main.hpp"
#include "test_compilation_unit.hpp"
#include <cstring>

/**
 * @file phase9b_tagged_union_init_tests.cpp
 * @brief Integration tests for Phase 9b: Tagged Union Initialization.
 */

TEST_FUNC(TaggedUnionInit_ReturnAnonymous) {
    const char* source =
        "const U = union(enum) { A: i32, B: bool };\n"
        "fn foo() U {\n"
        "    return .{ .A = 42 };\n"
        "}\n"
        "fn bar() U {\n"
        "    return .{ .B = true };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(TaggedUnionInit_Assignment) {
    const char* source =
        "const U = union(enum) { A: i32, B: bool };\n"
        "export fn test_assign() void {\n"
        "    var u: U = .{ .A = 42 };\n"
        "    u = .{ .B = false };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(TaggedUnionInit_NakedTag) {
    const char* source =
        "const U = union(enum) { A, B: i32 };\n"
        "fn foo() U {\n"
        "    return .{ .A };\n"
        "}\n"
        "export fn test_naked() void {\n"
        "    var u: U = .{ .A };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(TaggedUnionInit_SwitchInference) {
    const char* source =
        "const U = union(enum) { A: i32, B: bool };\n"
        "fn foo(u: U) U {\n"
        "    return switch (u) {\n"
        "        .A => |a| .{ .A = a },\n"
        "        .B => |b| .{ .B = b },\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(TaggedUnionInit_ErrorCases) {
    // 1. Extra fields
    {
        const char* source = "const U = union(enum) { A: i32, B: bool }; fn f() void { var u: U = .{ .A = 1, .B = true }; }";
        if (!expect_type_checker_abort(source)) return false;
    }
    // 2. Missing tag
    {
        const char* source = "const U = union(enum) { A: i32, B: bool }; fn f() void { var u: U = .{ .C = 1 }; }";
        if (!expect_type_checker_abort(source)) return false;
    }
    // 3. Wrong payload type
    {
        const char* source = "const U = union(enum) { A: i32, B: bool }; fn f() void { var u: U = .{ .A = true }; }";
        if (!expect_type_checker_abort(source)) return false;
    }
    // 4. Naked tag for non-void
    {
        const char* source = "const U = union(enum) { A: i32, B: bool }; fn f() void { var u: U = .{ .A }; }";
        if (!expect_type_checker_abort(source)) return false;
    }
    // 5. Value for void tag
    {
        const char* source = "const U = union(enum) { A, B: i32 }; fn f() void { var u: U = .{ .A = 1 }; }";
        if (!expect_type_checker_abort(source)) return false;
    }
    return true;
}

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_TaggedUnionInit_ReturnAnonymous,
        test_TaggedUnionInit_Assignment,
        test_TaggedUnionInit_NakedTag,
        test_TaggedUnionInit_SwitchInference,
        test_TaggedUnionInit_ErrorCases
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
