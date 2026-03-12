#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file union_naked_tag_tests.cpp
 * @brief Integration tests for naked tags in tagged unions (sugar for : void).
 */

TEST_FUNC(Union_NakedTagsImplicitEnum) {
    const char* source =
        "const U = union(enum) {\n"
        "    A,\n"
        "    B: i32,\n"
        "    C,\n"
        "};\n"
        "fn foo(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .A => 1,\n"
        "        .B => |val| val,\n"
        "        .C => 3,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(Union_NakedTagsExplicitEnum) {
    const char* source =
        "const Tag = enum { X, Y, Z };\n"
        "const U = union(Tag) {\n"
        "    X,\n"
        "    Y: f32,\n"
        "    Z,\n"
        "};\n"
        "fn foo(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .X => 10,\n"
        "        .Y => 20,\n"
        "        .Z => 30,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(Union_NakedTagsRejectionUntagged) {
    const char* source =
        "const U = union {\n"
        "    A,\n"
        "    B: i32,\n"
        "};\n";

    return expect_parser_abort(source);
}

TEST_FUNC(Struct_NakedTagsRejection) {
    const char* source =
        "const S = struct {\n"
        "    A,\n"
        "    B: i32,\n"
        "};\n";

    return expect_parser_abort(source);
}
