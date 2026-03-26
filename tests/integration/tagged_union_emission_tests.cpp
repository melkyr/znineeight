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

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;

    if (!unit.validateVariableEmission("x", "struct U x = u;")) {
        return false;
    }
    return true;
}

TEST_FUNC(TaggedUnionEmission_AnonymousField) {
    const char* source =
        "const S = struct {\n"
        "    u: union(enum) { a: i32, b: f32 },\n"
        "};\n"
        "fn foo(s: S) void {\n"
        "    var x = s;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;

    const ASTVarDeclNode* decl = unit.extractVariableDeclaration("s");
    Symbol* sym = unit.getSymbolTable().lookup("S");
    Type* t = sym->symbol_type;
    if (t && t->kind == TYPE_PLACEHOLDER) {
        TypeChecker checker(unit);
        t = checker.resolvePlaceholder(t);
    }

    ASSERT_TRUE(t != NULL);
    ASSERT_TRUE(t->kind == TYPE_STRUCT);
    ASSERT_TRUE(t->as.struct_details.fields->length() == 1);
    Type* field_type = (*t->as.struct_details.fields)[0].type;
    ASSERT_TRUE(isTaggedUnion(field_type));

    return true;
}

TEST_FUNC(TaggedUnionEmission_Return) {
    const char* source =
        "const U = union(enum) { a: i32, b: f32 };\n"
        "fn foo() U {\n"
        "    return undefined;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;

    return unit.validateFunctionSignature("foo", "struct U zF_3_foo(void)");
}

TEST_FUNC(TaggedUnionEmission_Param) {
    const char* source =
        "const U = union(enum) { a: i32, b: f32 };\n"
        "fn foo(u: U) void {}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;

    return unit.validateFunctionSignature("foo", "void zF_3_foo(struct U u)");
}

TEST_FUNC(TaggedUnionEmission_VoidField) {
    const char* source =
        "const U = union(enum) { a: void, b: i32 };\n"
        "fn foo(u: U) void {\n"
        "    var x = u;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;

    Symbol* sym = unit.getSymbolTable().lookup("U");
    Type* t = sym->symbol_type;
    if (t && t->kind == TYPE_PLACEHOLDER) {
        TypeChecker checker(unit);
        t = checker.resolvePlaceholder(t);
    }
    ASSERT_TRUE(t != NULL);
    ASSERT_TRUE(isTaggedUnion(t));

    DynamicArray<StructField>* fields = (t->kind == TYPE_TAGGED_UNION) ? t->as.tagged_union.payload_fields : t->as.struct_details.fields;
    ASSERT_TRUE(fields != NULL);

    // Check that 'a' is void and 'b' is i32
    bool found_a = false;
    bool found_b = false;
    for (size_t i = 0; i < fields->length(); ++i) {
        if (plat_strcmp((*fields)[i].name, "a") == 0) {
            ASSERT_TRUE((*fields)[i].type->kind == TYPE_VOID);
            found_a = true;
        }
        if (plat_strcmp((*fields)[i].name, "b") == 0) {
            ASSERT_TRUE((*fields)[i].type->kind == TYPE_I32);
            found_b = true;
        }
    }
    ASSERT_TRUE(found_a && found_b);

    return true;
}

TEST_FUNC(TaggedUnionEmission_NakedTag) {
    const char* source =
        "const U = union(enum) { A, B: i32 };\n"
        "fn foo(u: U) void {\n"
        "    var x = u;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;

    Symbol* sym = unit.getSymbolTable().lookup("U");
    Type* t = sym->symbol_type;
    if (t && t->kind == TYPE_PLACEHOLDER) {
        TypeChecker checker(unit);
        t = checker.resolvePlaceholder(t);
    }
    ASSERT_TRUE(t != NULL);
    ASSERT_TRUE(isTaggedUnion(t));

    DynamicArray<StructField>* fields = (t->kind == TYPE_TAGGED_UNION) ? t->as.tagged_union.payload_fields : t->as.struct_details.fields;

    bool found_a = false;
    bool found_b = false;
    for (size_t i = 0; i < fields->length(); ++i) {
        if (plat_strcmp((*fields)[i].name, "A") == 0) {
            ASSERT_TRUE((*fields)[i].type->kind == TYPE_VOID);
            found_a = true;
        }
        if (plat_strcmp((*fields)[i].name, "B") == 0) {
            ASSERT_TRUE((*fields)[i].type->kind == TYPE_I32);
            found_b = true;
        }
    }
    ASSERT_TRUE(found_a && found_b);

    return true;
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
