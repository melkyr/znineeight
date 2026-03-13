#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file tagged_union_emission_tests.cpp
 * @brief Integration tests for Tagged Union emission to C89.
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

    const char* temp_path = "temp_tagged_union_emission.c";
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

TEST_FUNC(TaggedUnionEmission_Named) {
    const char* source =
        "const U = union(enum) { a: i32, b: f32 };\n"
        "fn foo(u: U) void {\n"
        "    var x: U = u;\n"
        "}";
    // Should emit "struct U" instead of "union U"
    return run_real_emission_test(source, "foo", "struct U x;");
}

TEST_FUNC(TaggedUnionEmission_AnonymousField) {
    const char* source =
        "const S = struct {\n"
        "    u: union(enum) { a: i32, b: f32 },\n"
        "};\n"
        "export fn foo(s: S) void {}\n";

    ArenaAllocator arena(2 * 1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;

    const char* temp_path = "temp_anon_field.c";
    C89Emitter emitter(unit, temp_path);
    emitter.setModule("test");

    Symbol* sym = unit.getSymbolTable().lookup("S");
    Type* t = sym->symbol_type;
    if (t->kind == TYPE_PLACEHOLDER) {
        TypeChecker checker(unit);
        t = checker.resolvePlaceholder(t);
    }
    emitter.emitTypeDefinition(t);
    emitter.flush();
    emitter.close();

    PlatFile f = plat_open_file(temp_path, false);
    char buffer[4096];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer)-1);
    buffer[bytes] = '\0';
    plat_close_file(f);

    std::string actual = buffer;
    // Should contain the inline struct definition for field 'u'
    return actual.find("struct {\n") != std::string::npos &&
           actual.find("enum /* anonymous */ tag;") != std::string::npos &&
           actual.find("union {\n") != std::string::npos;
}

TEST_FUNC(TaggedUnionEmission_Return) {
    const char* source =
        "const U = union(enum) { a: i32, b: f32 };\n"
        "fn foo() U {\n"
        "    return undefined;\n"
        "}";
    // Return type should be struct.
    return run_real_emission_test(source, "foo", "struct U foo(void)");
}

TEST_FUNC(TaggedUnionEmission_Param) {
    const char* source =
        "const U = union(enum) { a: i32, b: f32 };\n"
        "fn foo(u: U) void {}";
    // Param type should be struct
    return run_real_emission_test(source, "foo", "void foo(struct U u)");
}

TEST_FUNC(TaggedUnionEmission_VoidField) {
    const char* source =
        "const U = union(enum) { a: void, b: i32 };\n"
        "fn foo(u: U) void {}";
    // We can't use anonymous tagged unions in locals easily due to TypeChecker restrictions.
    // We check the type definition of U instead.
    ArenaAllocator arena(2 * 1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;

    const char* temp_path = "temp_void_field.c";
    C89Emitter emitter(unit, temp_path);
    emitter.setModule("test");

    Symbol* sym = unit.getSymbolTable().lookup("U");
    Type* t = sym->symbol_type;
    if (t->kind == TYPE_PLACEHOLDER) {
        TypeChecker checker(unit);
        t = checker.resolvePlaceholder(t);
    }
    emitter.emitTypeDefinition(t);
    emitter.flush();
    emitter.close();

    PlatFile f = plat_open_file(temp_path, false);
    char buffer[4096];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer)-1);
    buffer[bytes] = '\0';
    plat_close_file(f);

    std::string actual = buffer;
    // Should NOT contain 'void a;' in the union part
    if (actual.find("void a;") != std::string::npos) return false;
    return actual.find("union {\n        int b;\n    } data;") != std::string::npos;
}

TEST_FUNC(TaggedUnionEmission_NakedTag) {
    const char* source =
        "const U = union(enum) { A, B: i32 };\n"
        "fn foo(u: U) void {}";
    ArenaAllocator arena(2 * 1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;

    const char* temp_path = "temp_naked_tag.c";
    C89Emitter emitter(unit, temp_path);
    emitter.setModule("test");

    Symbol* sym = unit.getSymbolTable().lookup("U");
    Type* t = sym->symbol_type;
    if (t->kind == TYPE_PLACEHOLDER) {
        TypeChecker checker(unit);
        t = checker.resolvePlaceholder(t);
    }
    emitter.emitTypeDefinition(t);
    emitter.flush();
    emitter.close();

    PlatFile f = plat_open_file(temp_path, false);
    char buffer[4096];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer)-1);
    buffer[bytes] = '\0';
    plat_close_file(f);

    std::string actual = buffer;
    // Naked tag A is void, should be omitted from union
    if (actual.find(" A;") != std::string::npos) return false;
    return actual.find("union {\n        int B;\n    } data;") != std::string::npos;
}

#ifndef RETROZIG_TEST
int main() {
    int passed = 0;
    int total = 0;

    total++; if (test_TaggedUnionEmission_Named()) passed++;
    total++; if (test_TaggedUnionEmission_AnonymousField()) passed++;
    total++; if (test_TaggedUnionEmission_Return()) passed++;
    total++; if (test_TaggedUnionEmission_Param()) passed++;
    total++; if (test_TaggedUnionEmission_VoidField()) passed++;
    total++; if (test_TaggedUnionEmission_NakedTag()) passed++;

    printf("Tagged Union Emission Integration Tests: %d/%d passed\n", passed, total);
    return (passed == total) ? 0 : 1;
}
#endif
