#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file union_tag_access_tests.cpp
 * @brief Integration tests for tagged union tag access.
 */

TEST_FUNC(UnionTagAccess_Basic) {
    const char* source =
        "const Value = union(enum) { Int: i32, Float: f64 };\n"
        "var tag = Value.Int;";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    /* Verify that tag access was constant-folded to enum member */
    if (!unit.validateVariableEmission("tag", "enum zE_1_Value_Tag zV_3_tag = Value_Tag_Int;")) {
        return false;
    }

    return true;
}

TEST_FUNC(UnionTagAccess_Alias) {
    const char* source =
        "const Value = union(enum) { A, B };\n"
        "const V2 = Value;\n"
        "var t1 = V2.A;\n"
        "var t2 = V2.B;";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateVariableEmission("t1", "enum zE_1_Value_Tag zV_4_t1 = Value_Tag_A;")) return false;
    if (!unit.validateVariableEmission("t2", "enum zE_1_Value_Tag zV_5_t2 = Value_Tag_B;")) return false;

    return true;
}

TEST_FUNC(UnionTagAccess_Imported) {
    const char* mod_source =
        "pub const JsonValue = union(enum) {\n"
        "    Null,\n"
        "    Bool: bool,\n"
        "    Number: f64,\n"
        "};";

    const char* main_source =
        "const json = @import(\"json.zig\");\n"
        "var t = json.JsonValue.Null;";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    unit.addSource("json.zig", mod_source);
    u32 file_id = unit.addSource("main.zig", main_source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for imported tag access\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    /* Null is the first field, so value should be the enum member */
    if (!unit.validateVariableEmission("t", "enum zE_#_JsonValue_Tag zV_#_t = JsonValue_Tag_Null;")) {
        return false;
    }

    return true;
}
