#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>
#include <string>

/**
 * @file anon_init_tests.cpp
 * @brief Integration tests for Anonymous Initializers (Batch 74).
 */

static bool run_real_emission_test(const char* zig_code, const char* fn_name, const char* expected_c89_substring) {
    ArenaAllocator arena(2 * 1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTFnDeclNode* fn = unit.extractFunctionDeclaration(fn_name);
    if (!fn) {
        printf("FAIL: Could not find function declaration for '%s'.\n", fn_name);
        return false;
    }

    const char* temp_path = "temp_anon_init_emission.c";
    C89Emitter emitter(unit, temp_path);
    emitter.setModule("test");
    if (!emitter.isValid()) {
        printf("FAIL: Could not open temp file for emission.\n");
        return false;
    }

    emitter.emitFnDecl(fn);
    emitter.flush();
    emitter.close();

    // Read back the file
    PlatFile f = plat_open_file(temp_path, false);
    if (f == PLAT_INVALID_FILE) return false;
    char buffer[8192];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer) - 1);
    buffer[bytes] = '\0';
    plat_close_file(f);

    std::string actual = buffer;
    if (actual.find(expected_c89_substring) == std::string::npos) {
        printf("FAIL: REAL emission mismatch for function '%s'.\nExpected to find: %s\nActual:\n%s\n",
               fn_name, expected_c89_substring, actual.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(AnonInit_TaggedUnion_NestedStruct) {
    const char* source =
        "const Value = union(enum) {\n"
        "    Cons: struct { car: i32, cdr: i32 },\n"
        "    Nil: void,\n"
        "};\n"
        "fn test_anon() void {\n"
        "    var v: Value = undefined;\n"
        "    v = Value{ .Cons = .{ .car = 1, .cdr = 2 } };\n"
        "}\n";

    /* Before the fix, the tag assignment 'v.tag = ...' would be missing. */
    /* We expect to find both the tag assignment and the field assignments. */
    ASSERT_TRUE(run_real_emission_test(source, "test_anon", "v.tag = zE_"));
    ASSERT_TRUE(run_real_emission_test(source, "test_anon", "v.data.Cons.car = 1;"));
    ASSERT_TRUE(run_real_emission_test(source, "test_anon", "v.data.Cons.cdr = 2;"));

    return true;
}

TEST_FUNC(AnonInit_DeeplyNested) {
    const char* source =
        "const Node = struct {\n"
        "    data: union(enum) {\n"
        "        Int: i32,\n"
        "        Nested: struct { x: i32, y: i32 },\n"
        "    },\n"
        "};\n"
        "fn test_deep() void {\n"
        "    var n: Node = undefined;\n"
        "    n = Node{ .data = .{ .Nested = .{ .x = 10, .y = 20 } } };\n"
        "}\n";

    /* Note: Nested anonymous tagged unions inside structs might not receive a name in the C89 backend
       if they are truly anonymous. They often get mangled as _Nested in the tag. */
    ASSERT_TRUE(run_real_emission_test(source, "test_deep", "n.data.tag = "));
    ASSERT_TRUE(run_real_emission_test(source, "test_deep", "n.data.data.Nested.x = 10;"));
    ASSERT_TRUE(run_real_emission_test(source, "test_deep", "n.data.data.Nested.y = 20;"));

    return true;
}

TEST_FUNC(AnonInit_Alias) {
    const char* source =
        "const Value = union(enum) {\n"
        "    A: i32,\n"
        "    B: void,\n"
        "};\n"
        "const V2 = Value;\n"
        "fn test_alias() void {\n"
        "    var v: V2 = .{ .A = 100 };\n"
        "}\n";

    ASSERT_TRUE(run_real_emission_test(source, "test_alias", "v.tag = "));
    ASSERT_TRUE(run_real_emission_test(source, "test_alias", "v.data.A = 100;"));

    return true;
}

TEST_FUNC(AnonInit_NakedTag_Coercion) {
    const char* source =
        "const Value = union(enum) {\n"
        "    A: i32,\n"
        "    B: void,\n"
        "};\n"
        "fn test_naked() void {\n"
        "    var v: Value = .B;\n"
        "}\n";

    ASSERT_TRUE(run_real_emission_test(source, "test_naked", "v.tag = "));
    /* For void payload, we only expect the tag assignment. */
    return true;
}
