#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <cstring>
#include <string>

/**
 * @file if_statement_tests.cpp
 * @brief Integration tests for Zig if statements in the RetroZig compiler.
 */

static bool run_if_stmt_test(const char* zig_code, const char* fn_name, const char* expected_c89) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateFunctionEmission(fn_name, expected_c89)) {
        return false;
    }

    return true;
}

// --- Condition Types ---

TEST_FUNC(IfStatementIntegration_BoolCondition) {
    const char* source =
        "fn foo(b: bool) void {\n"
        "    if (b) { }\n"
        "}";
    return run_if_stmt_test(source, "foo", "void foo(int b) { if (b) { } }");
}

TEST_FUNC(IfStatementIntegration_IntCondition) {
    const char* source =
        "fn foo(x: i32) void {\n"
        "    if (x) { }\n"
        "}";
    return run_if_stmt_test(source, "foo", "void foo(int x) { if (x) { } }");
}

TEST_FUNC(IfStatementIntegration_PointerCondition) {
    const char* source =
        "fn foo(ptr: *i32) void {\n"
        "    if (ptr) { }\n"
        "}";
    return run_if_stmt_test(source, "foo", "void foo(int* ptr) { if (ptr) { } }");
}

// --- Basic if-else ---

TEST_FUNC(IfStatementIntegration_IfElse) {
    const char* source =
        "fn foo(b: bool) i32 {\n"
        "    if (b) {\n"
        "        return 1;\n"
        "    } else {\n"
        "        return 0;\n"
        "    }\n"
        "}";
    return run_if_stmt_test(source, "foo", "int foo(int b) { if (b) { return 1; } else { return 0; } }");
}

// --- Chaining and Nesting ---

TEST_FUNC(IfStatementIntegration_ElseIfChain) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    if (x < 0) {\n"
        "        return -1;\n"
        "    } else if (x == 0) {\n"
        "        return 0;\n"
        "    } else {\n"
        "        return 1;\n"
        "    }\n"
        "}";
    // Zig's "else if" is else { if ... }
    return run_if_stmt_test(source, "foo", "int foo(int x) { if (x < 0) { return -1; } else if (x == 0) { return 0; } else { return 1; } }");
}

TEST_FUNC(IfStatementIntegration_NestedIf) {
    const char* source =
        "fn foo(a: bool, b: bool) void {\n"
        "    if (a) {\n"
        "        if (b) {\n"
        "            return;\n"
        "        }\n"
        "    }\n"
        "}";
    return run_if_stmt_test(source, "foo", "void foo(int a, int b) { if (a) { if (b) { return; } } }");
}

// --- Complex Conditions ---

TEST_FUNC(IfStatementIntegration_LogicalAnd) {
    const char* source =
        "fn foo(a: bool, b: bool) void {\n"
        "    if (a and b) { }\n"
        "}";
    return run_if_stmt_test(source, "foo", "void foo(int a, int b) { if (a && b) { } }");
}

TEST_FUNC(IfStatementIntegration_LogicalOr) {
    const char* source =
        "fn foo(a: bool, b: bool) void {\n"
        "    if (a or b) { }\n"
        "}";
    return run_if_stmt_test(source, "foo", "void foo(int a, int b) { if (a || b) { } }");
}

TEST_FUNC(IfStatementIntegration_LogicalNot) {
    const char* source =
        "fn foo(a: bool) void {\n"
        "    if (!a) { }\n"
        "}";
    return run_if_stmt_test(source, "foo", "void foo(int a) { if (!a) { } }");
}

// --- Edge Cases ---

TEST_FUNC(IfStatementIntegration_EmptyBlocks) {
    const char* source =
        "fn foo(b: bool) void {\n"
        "    if (b) { } else { }\n"
        "}";
    return run_if_stmt_test(source, "foo", "void foo(int b) { if (b) { } else { } }");
}

TEST_FUNC(IfStatementIntegration_ReturnFromBranches) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    if (x > 10) {\n"
        "        return 1;\n"
        "    }\n"
        "    return 0;\n"
        "}";
    return run_if_stmt_test(source, "foo", "int foo(int x) { if (x > 10) { return 1; } return 0; }");
}

// --- Negative Tests ---

TEST_FUNC(IfStatementIntegration_RejectFloatCondition) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "fn foo(f: f64) void {\n"
        "    if (f) { }\n"
        "}";

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected rejection of float condition but pipeline succeeded\n");
        return false;
    }

    return true;
}

TEST_FUNC(IfStatementIntegration_RejectBracelessIf) {
    const char* source =
        "fn foo(b: bool) void {\n"
        "    if (b) return;\n"
        "}";

    return expect_parser_abort(source);
}
