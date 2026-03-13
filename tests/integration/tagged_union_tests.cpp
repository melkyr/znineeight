#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file tagged_union_tests.cpp
 * @brief Integration tests for Zig tagged unions and switch captures.
 */

TEST_FUNC(TaggedUnion_BasicSwitch) {
    const char* source =
        "const Tag = enum { a, b };\n"
        "const U = union(Tag) { a: i32, b: f32 };\n"
        "fn foo(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .a => |val| val,\n"
        "        .b => |val| 0,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("repro.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(TaggedUnion_Emission_Comprehensive) {
    const char* source =
        "const U = union(enum) { A: i32, B: f64 };\n"
        "pub var global_u: U = undefined;\n"
        "fn takeU(u: U) void { _ = u; }\n"
        "fn returnU() U { var u: U = undefined; return u; }\n"
        "export fn test_all() void {\n"
        "    var local_u: U = undefined;\n"
        "    takeU(local_u);\n"
        "    local_u = returnU();\n"
        "    global_u = local_u;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("comp.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTFnDeclNode* fn_take = unit.extractFunctionDeclaration("takeU");
    const ASTFnDeclNode* fn_ret = unit.extractFunctionDeclaration("returnU");
    const ASTFnDeclNode* fn_all = unit.extractFunctionDeclaration("test_all");

    const char* temp_path = "temp_test_emission_union_comp.c";
    C89Emitter emitter(unit, temp_path);
    emitter.setModule("comp");

    Symbol* u_sym = unit.getSymbolTable("comp").lookup("U");
    if (u_sym && u_sym->symbol_type) {
        u_sym->symbol_type->c_name = "z_comp_U";
    }

    if (fn_take) emitter.emitFnDecl(fn_take);
    if (fn_ret) emitter.emitFnDecl(fn_ret);
    if (fn_all) emitter.emitFnDecl(fn_all);
    emitter.flush();
    emitter.close();

    PlatFile f = plat_open_file(temp_path, false);
    if (f == PLAT_INVALID_FILE) return false;
    char buffer[4096];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer) - 1);
    buffer[bytes] = '\0';
    plat_close_file(f);

    if (strstr(buffer, "struct z_comp_U u") == NULL) {
        printf("FAIL: Expected 'struct z_comp_U' in parameters or variables.\nActual output:\n%s\n", buffer);
        return false;
    }

    if (strstr(buffer, "union z_comp_U") != NULL) {
        printf("FAIL: Found incorrect 'union' declaration for tagged union.\n");
        return false;
    }

    return true;
}

TEST_FUNC(TaggedUnion_Emission_ParamReturn) {
    const char* source =
        "const U = union(enum) { A: i32, B: f64 };\n"
        "fn process(u: U) U {\n"
        "    return u;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("repro2.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTFnDeclNode* fn = unit.extractFunctionDeclaration("process");
    if (!fn) return false;

    const char* temp_path = "temp_test_emission_union_2.c";
    C89Emitter emitter(unit, temp_path);
    emitter.setModule("repro2");

    Symbol* u_sym = unit.getSymbolTable("repro2").lookup("U");
    if (u_sym && u_sym->symbol_type) {
        u_sym->symbol_type->c_name = "z_repro2_U";
    }

    emitter.emitFnDecl(fn);
    emitter.flush();
    emitter.close();

    PlatFile f = plat_open_file(temp_path, false);
    if (f == PLAT_INVALID_FILE) return false;
    char buffer[4096];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer) - 1);
    buffer[bytes] = '\0';
    plat_close_file(f);

    // We expect 'struct U' in parameters and return type
    // Since it's mangled as 'z_repro2_U' in our manual setup
    if (strstr(buffer, "static struct z_repro2_U z_repro2_process(struct z_repro2_U u)") == NULL) {
        printf("FAIL: Could not find expected signature 'static struct z_repro2_U z_repro2_process(struct z_repro2_U u)' in output.\n");
        printf("Actual output:\n%s\n", buffer);
        return false;
    }

    return true;
}

TEST_FUNC(TaggedUnion_Emission_VarDecl) {
    const char* source =
        "const U = union(enum) { A: i32 };\n"
        "fn test_fn() void {\n"
        "    var u: U = undefined;\n"
        "    _ = u;\n"
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

    const ASTFnDeclNode* fn = unit.extractFunctionDeclaration("test_fn");
    if (!fn) return false;

    const char* temp_path = "temp_test_emission_union.c";
    C89Emitter emitter(unit, temp_path);
    emitter.setModule("repro");

    // MetadataPreparationPass normally sets c_name. Since we didn't run it,
    // we'll manually ensure c_name is set for the type to get predictable output.
    Symbol* u_sym = unit.getSymbolTable("repro").lookup("U");
    if (u_sym && u_sym->symbol_type) {
        u_sym->symbol_type->c_name = "z_repro_U";
    }

    emitter.emitFnDecl(fn);
    emitter.flush();
    emitter.close();

    PlatFile f = plat_open_file(temp_path, false);
    if (f == PLAT_INVALID_FILE) return false;
    char buffer[4096];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer) - 1);
    buffer[bytes] = '\0';
    plat_close_file(f);

    // We expect 'struct z_repro_U' for the variable 'u'
    if (strstr(buffer, "struct U u;") == NULL) {
        printf("FAIL: Could not find expected struct declaration 'struct U u;' in output.\n");
        printf("Actual output:\n%s\n", buffer);
        return false;
    }

    if (strstr(buffer, "union U u;") != NULL) {
        printf("FAIL: Found incorrect 'union' declaration for tagged union variable.\n");
        return false;
    }

    return true;
}

TEST_FUNC(TaggedUnion_ExplicitEnumCustomValues) {
    const char* source =
        "const Tag = enum(i32) { a = 100, b = 200 };\n"
        "const U = union(Tag) { a: i32, b: f32 };\n"
        "fn foo(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .a => |val| val,\n"
        "        .b => |_| 0,\n"
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

TEST_FUNC(TaggedUnion_ImplicitEnum) {
    const char* source =
        "const U = union(enum) { a: i32, b: f32 };\n"
        "fn foo(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .a => |val| val,\n"
        "        .b => |_| 0,\n"
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

TEST_FUNC(TaggedUnion_ElseProng) {
    const char* source =
        "const U = union(enum) { a: i32, b: f32, c: bool };\n"
        "fn foo(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .a => |val| val,\n"
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

TEST_FUNC(TaggedUnion_CaptureImmutability) {
    const char* source =
        "const U = union(enum) { a: i32 };\n"
        "fn foo(u: U) void {\n"
        "    switch (u) {\n"
        "        .a => |val| {\n"
        "            val = 42;\n"
        "        },\n"
        "        else => {},\n"
        "    }\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    // This should fail during type checking
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected type error for immutable capture assignment, but succeeded.\n");
        return false;
    }

    // Verify the error message
    bool found_error = false;
    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].hint && strstr(errors[i].hint, "l-value is const")) {
            found_error = true;
            break;
        }
    }

    if (!found_error) {
        printf("FAIL: Did not find expected error message about immutable capture.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}
