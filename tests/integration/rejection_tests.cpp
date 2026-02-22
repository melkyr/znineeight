#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>
#include <string>

/**
 * @file rejection_tests.cpp
 * @brief Integration tests for non-C89 feature rejection and cataloguing.
 */

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

