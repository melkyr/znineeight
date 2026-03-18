#include "test_runner_main.hpp"
#include "test_compilation_unit.hpp"
#include <cstring>

/**
 * @file phase9c_foundation_tests.cpp
 * @brief Verification tests for Phase 9c Phases 1-4: Expected Type Propagation and Switch Inference.
 */

// Test 1: Anonymous initializer in return statement (Switch)
TEST_FUNC(ExpectedType_SwitchReturn) {
    const char* source =
        "const MyUnion = union(enum) { A: i32, B: bool };\n"
        "fn testSwitch(u: MyUnion) MyUnion {\n"
        "    return switch (u) {\n"
        "        .A => |a| .{ .A = a },\n"
        "        .B => |b| .{ .B = b },\n"
        "        else => .{ .A = 0 },\n"
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

// Test 2: Anonymous initializer in assignment
TEST_FUNC(ExpectedType_Assignment) {
    const char* source =
        "const MyUnion = union(enum) { A: i32, B: bool };\n"
        "export fn testAssign(u: MyUnion) void {\n"
        "    var result: MyUnion = .{ .A = 0 };\n"
        "    result = switch (u) {\n"
        "        .A => |a| .{ .A = a },\n"
        "        .B => |b| .{ .B = b },\n"
        "        else => .{ .A = 0 },\n"
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

// Test 3: Anonymous initializer in variable declaration
TEST_FUNC(ExpectedType_VarDecl) {
    const char* source =
        "const MyUnion = union(enum) { A: i32, B: bool };\n"
        "export fn testVarDecl(u: MyUnion) void {\n"
        "    const result: MyUnion = switch (u) {\n"
        "        .A => |a| .{ .A = a },\n"
        "        .B => |b| .{ .B = b },\n"
        "        else => .{ .A = 0 },\n"
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

// Test 4: Anonymous initializer as function argument
TEST_FUNC(ExpectedType_FunctionArg) {
    const char* source =
        "const MyUnion = union(enum) { A: i32, B: bool };\n"
        "fn consume(u: MyUnion) void {}\n"
        "export fn testArg(u: MyUnion) void {\n"
        "    consume(switch (u) {\n"
        "        .A => |a| .{ .A = a },\n"
        "        .B => |b| .{ .B = b },\n"
        "        else => .{ .A = 0 },\n"
        "    });\n"
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

// Test 5: Nested switch expressions
TEST_FUNC(ExpectedType_NestedSwitch) {
    const char* source =
        "const MyUnion = union(enum) { A: i32, B: bool };\n"
        "fn testNested(u: MyUnion, v: MyUnion) MyUnion {\n"
        "    return switch (u) {\n"
        "        .A => |a| switch (v) {\n"
        "            .A => |va| .{ .A = a + va },\n"
        "            else => .{ .A = a },\n"
        "        },\n"
        "        .B => |b| .{ .B = b },\n"
        "        else => .{ .A = 0 },\n"
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

// Test 6: If expression with anonymous initializers
TEST_FUNC(ExpectedType_IfExpr) {
    const char* source =
        "const MyUnion = union(enum) { A: i32, B: bool };\n"
        "fn testIf(b: bool) MyUnion {\n"
        "    return if (b) .{ .A = 1 } else .{ .B = true };\n"
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

// Test 7: Block expression with anonymous initializer at the end
TEST_FUNC(ExpectedType_BlockExpr) {
    const char* source =
        "const MyUnion = union(enum) { A: i32, B: bool };\n"
        "fn testBlock(b: bool) MyUnion {\n"
        "    return {\n"
        "        var x = b;\n"
        "        .{ .A = 1 }\n"
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

// Test 8: Switch on Enum, return Tagged Union (Requires propagation from expected type if cond is not union)
TEST_FUNC(ExpectedType_SwitchEnumToUnion) {
    const char* source =
        "const MyEnum = enum { A, B };\n"
        "const MyUnion = union(enum) { A: i32, B: bool };\n"
        "fn translate(e: MyEnum) MyUnion {\n"
        "    return switch (e) {\n"
        "        .A => .{ .A = 1 },\n"
        "        .B => .{ .B = true },\n"
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

// Test 9: Void payload with various syntaxes
TEST_FUNC(ExpectedType_VoidPayloads) {
    const char* source =
        "const U = union(enum) { A, B: void, C: i32 };\n"
        "fn getVoid() void {}\n"
        "export fn testVoid() void {\n"
        "    var u: U = .{ .A };\n"
        "    u = .{ .B = {} };\n"
        "    u = .{ .B = getVoid() };\n"
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

// Test 10: Deeply nested anonymous initializers
TEST_FUNC(ExpectedType_DeeplyNested) {
    const char* source =
        "const Inner = union(enum) { A: i32, B: bool };\n"
        "const Outer = union(enum) { I: Inner, C: i32 };\n"
        "export fn testNestedAnon() void {\n"
        "    var o: Outer = .{ .I = .{ .A = 42 } };\n"
        "    o = .{ .I = .{ .B = true } };\n"
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

// Test 11: Switch expression missing else (Error case)
TEST_FUNC(ExpectedType_SwitchMissingElseError) {
    const char* source =
        "const U = union(enum) { A, B };\n"
        "fn testMissingElse(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .A => 1,\n"
        "        .B => 2,\n"
        "    };\n"
        "}\n";

    if (!expect_type_checker_abort(source)) return false;
    return true;
}

// Test 12: Anonymous tagged union initializer to non-union (Error case)
TEST_FUNC(ExpectedType_AnonymousToNonUnionError) {
    const char* source =
        "export fn testAnonToNonUnion() void {\n"
        "    var x: i32 = .{ .A = 1 };\n"
        "}\n";

    if (!expect_type_checker_abort(source)) return false;
    return true;
}

// Test 13: Mix typed and anonymous in switch (Should unify to typed)
TEST_FUNC(ExpectedType_MixedSwitch) {
    const char* source =
        "const U = union(enum) { A: i32, B: bool };\n"
        "fn testMixed(u: U) U {\n"
        "    return switch (u) {\n"
        "        .A => |a| U{ .A = a },\n"
        "        .B => |b| .{ .B = b },\n"
        "        else => .{ .A = 0 },\n"
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

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_ExpectedType_SwitchReturn,
        test_ExpectedType_Assignment,
        test_ExpectedType_VarDecl,
        test_ExpectedType_FunctionArg,
        test_ExpectedType_NestedSwitch,
        test_ExpectedType_IfExpr,
        test_ExpectedType_BlockExpr,
        test_ExpectedType_SwitchEnumToUnion,
        test_ExpectedType_VoidPayloads,
        test_ExpectedType_DeeplyNested,
        test_ExpectedType_SwitchMissingElseError,
        test_ExpectedType_AnonymousToNonUnionError,
        test_ExpectedType_MixedSwitch
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
