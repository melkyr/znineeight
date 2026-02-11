#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file pointer_tests.cpp
 * @brief Integration tests for Zig pointer operations in the RetroZig compiler.
 */

static bool run_pointer_test(const char* zig_code, const char* var_name, const char* expected_c89) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (var_name) {
        if (!unit.validateVariableEmission(var_name, expected_c89)) {
            return false;
        }
    }

    return true;
}

static bool run_pointer_expression_test(const char* zig_code, const char* expected_c89) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateExpressionEmission(expected_c89)) {
        return false;
    }

    return true;
}

// --- Positive Tests ---

TEST_FUNC(PointerIntegration_AddressOfDereference) {
    const char* source =
        "fn foo() i32 {\n"
        "    var x: i32 = 42;\n"
        "    var p: *i32 = &x;\n"
        "    return p.*;\n"
        "}";
    return run_pointer_test(source, "p", "int* p = &x;");
}

TEST_FUNC(PointerIntegration_DereferenceExpression) {
    const char* source =
        "fn foo() i32 {\n"
        "    var x: i32 = 42;\n"
        "    var p: *i32 = &x;\n"
        "    return p.*;\n"
        "}";
    return run_pointer_expression_test(source, "*p");
}

TEST_FUNC(PointerIntegration_PointerArithmeticAdd) {
    const char* source =
        "fn foo(p: *i32, i: i32) *i32 {\n"
        "    return p + i;\n"
        "}";
    return run_pointer_expression_test(source, "p + i");
}

TEST_FUNC(PointerIntegration_PointerArithmeticSub) {
    const char* source =
        "fn foo(p: *i32, i: i32) *i32 {\n"
        "    return p - i;\n"
        "}";
    return run_pointer_expression_test(source, "p - i");
}

TEST_FUNC(PointerIntegration_NullLiteral) {
    const char* source =
        "var p: *i32 = null;";
    return run_pointer_test(source, "p", "int* p = ((void*)0);");
}

TEST_FUNC(PointerIntegration_NullComparison) {
    const char* source =
        "fn foo(p: *i32) bool {\n"
        "    return p == null;\n"
        "}";
    return run_pointer_expression_test(source, "p == ((void*)0)");
}

TEST_FUNC(PointerIntegration_PointerToStruct) {
    const char* source =
        "const Point = struct { x: i32, y: i32 };\n"
        "fn foo(p: *Point) i32 {\n"
        "    return p.x;\n"
        "}";
    return run_pointer_expression_test(source, "p->x");
}

TEST_FUNC(PointerIntegration_VoidPointerAssignment) {
    const char* source =
        "fn foo(p: *i32) *void {\n"
        "    var v: *void = p;\n"
        "    return v;\n"
        "}";
    return run_pointer_test(source, "v", "void* v = p;");
}

TEST_FUNC(PointerIntegration_ConstAdding) {
    const char* source =
        "fn foo(p: *i32) *const i32 {\n"
        "    var cp: *const i32 = p;\n"
        "    return cp;\n"
        "}";
    return run_pointer_test(source, "cp", "const int* cp = p;");
}

// --- Negative Tests ---

TEST_FUNC(PointerIntegration_ReturnLocalAddressError) {
    const char* source =
        "fn bar() *i32 {\n"
        "    var x: i32 = 42;\n"
        "    return &x;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    unit.getOptions().enable_lifetime_analysis = true;

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected lifetime error but pipeline succeeded\n");
        return false;
    }

    return unit.hasErrorMatching("address of local variable") || unit.hasErrorMatching("lifetime");
}

TEST_FUNC(PointerIntegration_DereferenceNullError) {
    const char* source =
        "fn bar() void {\n"
        "    var p: *i32 = null;\n"
        "    var v = p.*;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    unit.getOptions().enable_null_pointer_analysis = true;

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected null pointer error but pipeline succeeded\n");
        return false;
    }

    return unit.hasErrorMatching("null pointer dereference");
}

TEST_FUNC(PointerIntegration_PointerPlusPointerError) {
    const char* source =
        "fn bar(p: *i32, q: *i32) *i32 {\n"
        "    return p + q;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected pointer + pointer error but pipeline succeeded\n");
        return false;
    }

    return unit.hasErrorMatching("invalid operands to binary expression");
}

TEST_FUNC(PointerIntegration_DereferenceNonPointerError) {
    const char* source =
        "fn bar(x: i32) i32 {\n"
        "    return x.*;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected dereference error but pipeline succeeded\n");
        return false;
    }

    return unit.hasErrorMatching("dereference operator '*' only allowed on pointer types");
}

TEST_FUNC(PointerIntegration_AddressOfNonLValue) {
    const char* source =
        "fn bar() *i32 {\n"
        "    return &(1 + 2);\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected l-value error but pipeline succeeded\n");
        return false;
    }

    return unit.hasErrorMatching("l-value expected");
}

TEST_FUNC(PointerIntegration_IncompatiblePointerAssignment) {
    const char* source =
        "fn bar(p: *i32) *f32 {\n"
        "    var q: *f32 = p;\n"
        "    return q;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected type mismatch but pipeline succeeded\n");
        return false;
    }

    return unit.hasErrorMatching("Type mismatch");
}
