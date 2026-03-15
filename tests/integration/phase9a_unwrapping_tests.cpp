#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file phase9a_unwrapping_tests.cpp
 * @brief Integration tests for Phase 9a: Meta-type unwrapping and constant folding through aliases.
 */

TEST_FUNC(Phase9a_ModuleQualifiedTaggedUnion) {
    const char* mod_source =
        "pub const JsonValue = union(enum) {\n"
        "    Null: void,\n"
        "    Integer: i32,\n"
        "};\n";

    const char* main_source =
        "const json = @import(\"json.zig\");\n"
        "fn doTest() json.JsonValue {\n"
        "    const x = json.JsonValue.Null;\n"
        "    return .{ .Null = {} };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    plat_write_file(plat_open_file("json.zig", true), mod_source, plat_strlen(mod_source));

    unit.addSource("json.zig", mod_source);
    u32 main_id = unit.addSource("test.zig", main_source);

    bool success = unit.performTestPipeline(main_id);
    plat_delete_file("json.zig");

    if (!success) {
        printf("FAIL: Pipeline execution failed for module-qualified tagged union access.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(Phase9a_LocalAliasTaggedUnion) {
    const char* source =
        "const U = union(enum) { A, B };\n"
        "const Alias = U;\n"
        "fn foo() void {\n"
        "    const val = Alias.A;\n"
        "    _ = val;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for local alias tagged union access.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(Phase9a_RecursiveAliasEnum) {
    const char* source =
        "const E = enum { First, Second };\n"
        "const Alias1 = E;\n"
        "const Alias2 = Alias1;\n"
        "fn foo() i32 {\n"
        "    const val = Alias2.Second;\n"
        "    return @enumToInt(val);\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for recursive enum alias.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(Phase9a_ErrorSetAlias) {
    const char* source =
        "const MyError = error { Fail, Bad };\n"
        "const Alias = MyError;\n"
        "fn foo() Alias {\n"
        "    return Alias.Fail;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for error set alias.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(Phase9a_ModuleQualifiedEnum) {
    const char* mod_source =
        "pub const Color = enum { Red, Green, Blue };\n";

    const char* main_source =
        "const colors = @import(\"colors.zig\");\n"
        "fn doTest() i32 {\n"
        "    const c = colors.Color.Green;\n"
        "    return @enumToInt(c);\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    plat_write_file(plat_open_file("colors.zig", true), mod_source, plat_strlen(mod_source));

    unit.addSource("colors.zig", mod_source);
    u32 main_id = unit.addSource("test.zig", main_source);

    bool success = unit.performTestPipeline(main_id);
    plat_delete_file("colors.zig");

    if (!success) {
        printf("FAIL: Pipeline execution failed for module-qualified enum access.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}
