#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>

TEST_FUNC(ParamIntegration_Immutable) {
    const char* source =
        "fn foo(x: i32) void {\n"
        "    x = 10;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected pipeline to fail when assigning to function parameter\n");
        return false;
    }

    return true;
}

TEST_FUNC(ParamIntegration_MutablePointer) {
    const char* source =
        "fn foo(ptr: *i32) void {\n"
        "    ptr.* = 10; // This should be allowed\n"
        "    // ptr = @ptrCast(*i32, 0); // This should be forbidden\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for valid pointer dereference in parameter:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}
