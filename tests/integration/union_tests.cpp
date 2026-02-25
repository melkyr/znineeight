#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file union_tests.cpp
 * @brief Integration tests for Zig unions in the RetroZig compiler.
 */

TEST_FUNC(UnionIntegration_BareUnion) {
    const char* source =
        "const U = union { a: i32, b: f32 };\n"
        "fn foo(u: U) void {}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateFunctionSignature("foo", "void foo(union U u)")) {
        return false;
    }

    return true;
}

TEST_FUNC(UnionIntegration_RejectTaggedUnion) {
    /* Tagged unions are now supported in the bootstrap compiler. */
    const char* source = "const Tag = enum { A, B };\nconst U = union(Tag) { a: i32, b: f32 };";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    return unit.performTestPipeline(file_id);
}
