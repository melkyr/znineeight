#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "mock_emitter.hpp"
#include "../test_utils.hpp"
#include <cstdio>

/**
 * @file multi_level_pointer_tests.cpp
 * @brief Integration tests for multi-level pointers (**T).
 */

static bool run_ptr_test(const char* zig_code, TypeKind expected_kind, const char* expected_c89) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (expected_kind != TYPE_VOID) {
        if (!unit.validateExpressionType(expected_kind)) {
            printf("FAIL: Expression type mismatch for: %s\n", zig_code);
            return false;
        }
    }

    if (expected_c89) {
        if (!unit.validateExpressionEmission(expected_c89)) {
            printf("FAIL: Expression emission mismatch for: %s\n", zig_code);
            return false;
        }
    }

    return true;
}

TEST_FUNC(Pointer_Pointer_Decl) {
    const char* source =
        "fn foo() void {\n"
        "    var x: i32 = 42;\n"
        "    var p: *i32 = &x;\n"
        "    var pp: **i32 = &p;\n"
        "    _ = pp;\n"
        "}";
    return run_ptr_test(source, TYPE_VOID, NULL);
}

TEST_FUNC(Pointer_Pointer_Dereference) {
    const char* source =
        "fn foo() i32 {\n"
        "    var x: i32 = 42;\n"
        "    var p: *i32 = &x;\n"
        "    var pp: **i32 = &p;\n"
        "    return pp.*.*;\n"
        "}";
    return run_ptr_test(source, TYPE_I32, "**pp");
}

TEST_FUNC(Pointer_Pointer_Triple) {
    const char* source =
        "fn foo(ppp: ***i32) i32 {\n"
        "    return ppp.*.*.*;\n"
        "}";
    return run_ptr_test(source, TYPE_I32, "***ppp");
}

TEST_FUNC(Pointer_Pointer_Param_Return) {
    const char* source =
        "fn foo(pp: **i32) **i32 {\n"
        "    return pp;\n"
        "}";
    return run_ptr_test(source, TYPE_POINTER, "pp");
}

TEST_FUNC(Pointer_Pointer_Const_Ignored) {
    const char* source =
        "fn foo(p: *const *i32) void {\n"
        "    var x: **i32 = @ptrCast(**i32, p);\n"
        "    _ = x;\n"
        "}";
    return run_ptr_test(source, TYPE_VOID, NULL);
}

TEST_FUNC(Pointer_Pointer_Global_Emission) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "var x: i32 = 42;\n"
        "var p: *i32 = &x;\n"
        "pub var pp: *const *i32 = &p;";

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    // Verify emission of 'pp'. Should ignore 'const'.
    // Zig: *const *i32 pp = &p;
    // Expected C89: int** pp = &p; (approx, MockC89Emitter might use mangled names)
    return unit.validateVariableEmission("pp", "int** pp = &p;");
}
