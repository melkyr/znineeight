#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <cstring>
#include <string>

/**
 * @file variable_decl_tests.cpp
 * @brief Integration tests for Zig variable declarations in the RetroZig compiler.
 */

static bool run_var_decl_test(const char* zig_code, const char* var_name, const char* expected_c89) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateVariableEmission(var_name, expected_c89)) {
        return false;
    }

    return true;
}

// --- Basic Declarations ---

TEST_FUNC(VariableIntegration_BasicI32) {
    return run_var_decl_test("var x: i32 = 42;", "x", "int x = 42;");
}

TEST_FUNC(VariableIntegration_BasicConstF64) {
    return run_var_decl_test("const y: f64 = 3.14;", "y", "const double y = 3.14;");
}

TEST_FUNC(VariableIntegration_GlobalVar) {
    return run_var_decl_test("var global_val: u32 = 100u;", "global_val", "unsigned int global_val = 100U;");
}

TEST_FUNC(VariableIntegration_LocalVar) {
    const char* source =
        "fn foo() void {\n"
        "    var local_val: i16 = 500;\n"
        "}";
    return run_var_decl_test(source, "local_val", "short local_val = 500;");
}

// --- Type Inference ---

TEST_FUNC(VariableIntegration_InferredInt) {
    return run_var_decl_test("var x = 42;", "x", "int x = 42;");
}

TEST_FUNC(VariableIntegration_InferredFloat) {
    return run_var_decl_test("var y = 3.14;", "y", "double y = 3.14;");
}

TEST_FUNC(VariableIntegration_InferredBool) {
    return run_var_decl_test("const b = true;", "b", "const int b = 1;");
}

// --- Name Mangling ---

TEST_FUNC(VariableIntegration_MangleKeyword) {
    // 'int' is a C keyword but NOT a Zig keyword, so it is a valid Zig identifier.
    // It should be mangled to 'z_int' by sanitizeForC89.
    return run_var_decl_test("var int: i32 = 0;", "int", "int z_int = 0;");
}

TEST_FUNC(VariableIntegration_MangleReserved) {
    // Names starting with __ are reserved in C.
    // sanitizeForC89 prepends 'z' if it starts with '_'.
    // Zig '__reserved' -> C 'z__reserved'
    return run_var_decl_test("var __reserved: i32 = 1;", "__reserved", "int z__reserved = 1;");
}

TEST_FUNC(VariableIntegration_MangleLongName) {
    // 31 character limit for MSVC 6.0
    const char* long_name = "this_is_a_very_long_variable_name_that_exceeds_31_chars";
    // Truncated to 31: "this_is_a_very_long_variable_na"
    return run_var_decl_test("var this_is_a_very_long_variable_name_that_exceeds_31_chars: i32 = 1;", long_name, "int this_is_a_very_long_variable_na = 1;");
}

// --- Negative Tests ---

TEST_FUNC(VariableIntegration_DuplicateNameError) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "var x: i32 = 1;\n"
        "var x: i32 = 2;";

    u32 file_id = unit.addSource("test.zig", source);
    // Should fail due to name collision
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected duplicate name error but pipeline succeeded\n");
        return false;
    }

    return true;
}

TEST_FUNC(VariableIntegration_RejectSlice) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source = "var s: []u8 = undefined;";

    u32 file_id = unit.addSource("test.zig", source);
    // Should fail because slices are not supported in bootstrap
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected rejection of slice but pipeline succeeded\n");
        return false;
    }

    return true;
}

TEST_FUNC(VariableIntegration_PointerToVoid) {
    return run_var_decl_test("var p: *void = null;", "p", "void* p = ((void*)0);");
}
