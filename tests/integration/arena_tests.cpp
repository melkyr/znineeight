#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include <cstdio>

/**
 * @file arena_tests.cpp
 * @brief Integration tests for Task 211 (Arena memory management).
 */

static bool run_arena_test(const char* zig_code, bool expected_success = true) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    bool success = unit.performTestPipeline(file_id);

    if (success != expected_success) {
        printf("FAIL: Arena Test. Expected success: %d, Got: %d\n", expected_success, success);
        if (!success) unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(Task211_MultiArenaUsage) {
    return run_arena_test(
        "pub fn main() void {\n"
        "    const a = arena_create(1024u);\n"
        "    const p1 = arena_alloc(a, 16u);\n"
        "    const p2 = arena_alloc(zig_default_arena, 32u);\n"
        "    arena_reset(a);\n"
        "    const p3 = arena_alloc(a, 8u);\n"
        "    arena_destroy(a);\n"
        "}\n"
    );
}

TEST_FUNC(Task211_ArenaCodegen) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "pub fn test_arenas() void {\n"
        "    const a = arena_create(1024u);\n"
        "    const p = arena_alloc(a, 16u);\n"
        "}\n";

    u32 file_id = unit.addSource("test_arena.zig", source);
    ASSERT_TRUE(unit.performFullPipeline(file_id));

    char* temp_c = plat_create_temp_file("arena_codegen", ".c");
    ASSERT_TRUE(unit.generateCode(temp_c));

    // Read generated code
    size_t size = 0;
    char* content = NULL;
    ASSERT_TRUE(plat_file_read(temp_c, &content, &size));
    ASSERT_TRUE(content != NULL);

    // Check for expected patterns
    // Note: C89Emitter might emit slightly different spacing or suffixes.
    // For u32, it uses 'U'.
    ASSERT_TRUE(strstr(content, "arena_create(1024U)") != NULL);
    ASSERT_TRUE(strstr(content, "arena_alloc(a, 16U)") != NULL);

    plat_free(content);
    plat_delete_file(temp_c);
    plat_free(temp_c);

    return true;
}

TEST_FUNC(Task211_ArenaAllocDefault) {
    return run_arena_test(
        "pub fn main() void {\n"
        "    const p = arena_alloc_default(64u);\n"
        "}\n"
    );
}

TEST_FUNC(Task211_ArenaTypeRecognition) {
    return run_arena_test(
        "pub fn process(a: *Arena) void {\n"
        "    const p = arena_alloc(a, 100u);\n"
        "}\n"
    );
}
