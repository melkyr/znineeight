#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>

/**
 * @file while_capture_tests.cpp
 * @brief Minimal integration test for while capture to fix broken batch runners.
 */

TEST_FUNC(WhileCapture_Basic) {
    const char* source =
        "fn test_while_capture(opt: ?i32) i32 {\n"
        "    var sum: i32 = 0;\n"
        "    var current = opt;\n"
        "    while (current) |val| {\n"
        "        sum = sum + val;\n"
        "        current = null;\n"
        "    }\n"
        "    return sum;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performFullPipeline(file_id)) {
        printf("FAIL: While capture basic test failed pipeline.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}
