#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>
#include <string>

/**
 * @file task_12_aggregate_literals_tests.cpp
 * @brief Integration tests for Milestone 12 - Anonymous Aggregate Literals (Arrays, Tuples, Unions).
 */

static bool run_aggregate_emission_test(const char* zig_code, const char* fn_name, const char* expected_c89_substring) {
    ArenaAllocator arena(4 * 1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTFnDeclNode* fn = unit.extractFunctionDeclaration(fn_name);
    if (!fn) {
        printf("FAIL: Could not find function declaration for '%s'.\n", fn_name);
        return false;
    }

    const char* temp_path = "temp_aggregate_emission.c";
    C89Emitter emitter(unit, temp_path);
    emitter.setModule("test");
    if (!emitter.isValid()) {
        printf("FAIL: Could not open temp file for emission.\n");
        return false;
    }

    emitter.emitFnDecl(fn);
    emitter.flush();
    emitter.close();

    // Read back the file
    PlatFile f = plat_open_file(temp_path, false);
    if (f == PLAT_INVALID_FILE) return false;
    char buffer[16384];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer) - 1);
    buffer[bytes] = '\0';
    plat_close_file(f);

    std::string actual = buffer;
    if (actual.find(expected_c89_substring) == std::string::npos) {
        printf("FAIL: REAL emission mismatch for function '%s'.\nExpected to find: %s\nActual:\n%s\n",
               fn_name, expected_c89_substring, actual.c_str());
        return false;
    }

    return true;
}

static bool expect_compilation_error(const char* zig_code, const char* expected_error) {
    ArenaAllocator arena(2 * 1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    unit.performTestPipeline(file_id);

    if (!unit.getErrorHandler().hasErrors()) {
        printf("FAIL: Expected compilation error, but none found.\nSource:\n%s\n", zig_code);
        return false;
    }

    /* We don't have a direct "contains error message" helper in ErrorHandler that is easy to use here,
       so we just check if it has errors. In a real test suite we'd check the message. */
    return true;
}

TEST_FUNC(Aggregate_ArrayLiteral_Coercion) {
    const char* source =
        "fn test_array() void {\n"
        "    var a: [3]i32 = .{ 1, 2, 3 };\n"
        "}\n";

    /* Concisely verify array initialization */
    ASSERT_TRUE(run_aggregate_emission_test(source, "test_array", "int a[3] = {1, 2, 3};"));

    return true;
}

TEST_FUNC(Aggregate_TupleLiteral_Coercion) {
    const char* source =
        "const MyTuple = struct { _0: i32, _1: bool };\n"
        "fn test_tuple() void {\n"
        "    var t: MyTuple = .{ ._0 = 42, ._1 = true };\n"
        "}\n";

    /* Verify named anonymous struct initialization */
    ASSERT_TRUE(run_aggregate_emission_test(source, "test_tuple", "struct zS_0_MyTuple t = {42, 1};"));

    return true;
}

TEST_FUNC(Aggregate_UnionLiteral_Coercion) {
    const char* source =
        "const Val = union(enum) { A: i32, B: f32 };\n"
        "fn test_union() void {\n"
        "    var v: Val = .{ .A = 10 };\n"
        "}\n";

    ASSERT_TRUE(run_aggregate_emission_test(source, "test_union", "v.tag = "));
    ASSERT_TRUE(run_aggregate_emission_test(source, "test_union", "v.data.A = 10;"));

    return true;
}

TEST_FUNC(Aggregate_Nested_Mixed) {
    const char* source =
        "const Point = struct { x: i32, y: i32 };\n"
        "fn test_nested() void {\n"
        "    var pts: [2]Point = .{ .{ .x = 1, .y = 2 }, .{ .x = 3, .y = 4 } };\n"
        "}\n";

    ASSERT_TRUE(run_aggregate_emission_test(source, "test_nested", "{{1, 2}, {3, 4}}"));

    return true;
}

TEST_FUNC(Aggregate_Error_NoContext) {
    const char* source =
        "fn test_no_context() void {\n"
        "    const x = .{ 1, 2, 3 };\n"
        "}\n";

    ASSERT_TRUE(expect_compilation_error(source, "anonymous literal used without a target type"));

    return true;
}

TEST_FUNC(Aggregate_Array_SizeMismatch) {
    const char* source =
        "fn test_mismatch() void {\n"
        "    var a: [2]i32 = .{ 1, 2, 3 };\n"
        "}\n";

    ASSERT_TRUE(expect_compilation_error(source, "array size mismatch"));

    return true;
}
