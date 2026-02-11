#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>
#include <string>

/**
 * @file rejection_tests.cpp
 * @brief Integration tests for non-C89 feature rejection and cataloguing.
 */

TEST_FUNC(RejectionIntegration_ErrorUnion) {
    const char* source = "fn fail() !i32 { return 42; }";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    // Should fail validation (Pass 1)
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected rejection of error union but pipeline succeeded\n");
        return false;
    }

    // Verify it's in the ErrorFunctionCatalogue (populated in Pass 1)
    if (!unit.hasErrorFunction("fail")) {
        printf("FAIL: Function 'fail' not found in ErrorFunctionCatalogue\n");
        return false;
    }

    return unit.hasErrorMatching("returns error type");
}

TEST_FUNC(RejectionIntegration_Optional) {
    const char* source = "var opt: ?i32 = null;";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected rejection of optional but pipeline succeeded\n");
        return false;
    }

    return unit.hasErrorMatching("Optional types");
}

TEST_FUNC(RejectionIntegration_TryExpression) {
    const char* source =
        "fn mightFail() !i32 { return 42; }\n"
        "fn foo() !void { _ = try mightFail(); }";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected rejection of try but pipeline succeeded\n");
        return false;
    }

    // Verify 'mightFail' is in ErrorFunctionCatalogue
    if (!unit.hasErrorFunction("mightFail")) {
        printf("FAIL: Function 'mightFail' not found in ErrorFunctionCatalogue\n");
        return false;
    }

    // Verify 'try' is in TryExpressionCatalogue
    if (unit.getTryExpressionCatalogue().count() == 0) {
        printf("FAIL: No entries in TryExpressionCatalogue\n");
        return false;
    }

    return unit.hasErrorMatching("Try expression");
}
