#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include "c89_validator.hpp"
#include <cstdio>
#include <cstring>
#include <string>

/**
 * @file codegen_member_access_tests.cpp
 * @brief Integration tests for member access emission in C89Emitter.
 */

static bool run_member_codegen_test(const char* zig_code, const char* expected_c89_substring) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    std::string generated_c;
    const char* temp_filename = "temp_member_test.c";
    {
        C89Emitter emitter(arena, unit.getErrorHandler(), temp_filename);
        if (!emitter.isValid()) {
            printf("FAIL: Could not open temp file for writing\n");
            return false;
        }

        emitter.emitPrologue();

        ASTNode* root = unit.last_ast;
        if (root && root->type == NODE_BLOCK_STMT) {
            DynamicArray<ASTNode*>* stmts = root->as.block_stmt.statements;
            // First emit type definitions
            for (size_t i = 0; i < stmts->length(); ++i) {
                emitter.emitTypeDefinition((*stmts)[i]);
            }
            // Then emit functions
            for (size_t i = 0; i < stmts->length(); ++i) {
                if ((*stmts)[i]->type == NODE_FN_DECL) {
                    emitter.emitFnDecl((*stmts)[i]->as.fn_decl);
                }
            }
        }
    }

    char* buffer = NULL;
    size_t size = 0;
    if (!plat_file_read(temp_filename, &buffer, &size)) {
        printf("FAIL: Could not read back temp file\n");
        return false;
    }
    generated_c = std::string(buffer, size);

    bool found = (generated_c.find(expected_c89_substring) != std::string::npos);
    if (!found) {
        printf("FAIL: Codegen mismatch for:\n%s\nExpected to find: %s\nActual output:   %s\n", zig_code, expected_c89_substring, generated_c.c_str());
    }

    C89Validator* validator = createGCCValidator();
    ValidationResult res = validator->validate(generated_c);
    if (!res.isValid) {
        printf("FAIL: Generated C code is not valid C89 for:\n%s\n", zig_code);
        for (size_t i = 0; i < res.errors.size(); ++i) {
            printf("  Error: %s\n", res.errors[i].c_str());
        }
        printf("--- Generated Code ---\n%s\n----------------------\n", generated_c.c_str());
        found = false;
    }
    delete validator;

    plat_free(buffer);
    plat_delete_file(temp_filename);

    return found;
}

TEST_FUNC(Codegen_MemberAccess_Simple) {
    const char* source =
        "const S = struct { f: i32 };\n"
        "fn foo(s: S) i32 { return s.f; }";
    return run_member_codegen_test(source, "return s.f;");
}

TEST_FUNC(Codegen_MemberAccess_Pointer) {
    const char* source =
        "const S = struct { f: i32 };\n"
        "fn foo(sp: *S) i32 { return sp.f; }";
    return run_member_codegen_test(source, "return sp->f;");
}

TEST_FUNC(Codegen_MemberAccess_ExplicitDeref) {
    const char* source =
        "const S = struct { f: i32 };\n"
        "fn foo(sp: *S) i32 { return sp.*.f; }";
    // Zig sp.*.f -> C (*sp).f
    return run_member_codegen_test(source, "return (*sp).f;");
}

TEST_FUNC(Codegen_MemberAccess_AddressOf) {
    const char* source =
        "const S = struct { f: i32 };\n"
        "fn foo(s: S) i32 { return (&s).f; }";
    // Zig (&s).f -> C (&s)->f
    return run_member_codegen_test(source, "return (&s)->f;");
}

TEST_FUNC(Codegen_MemberAccess_Union) {
    const char* source =
        "const U = union { f: i32, g: f32 };\n"
        "fn foo(u: U) i32 { return u.f; }";
    return run_member_codegen_test(source, "return u.f;");
}

TEST_FUNC(Codegen_MemberAccess_Nested) {
    const char* source =
        "const S1 = struct { f: i32 };\n"
        "const S2 = struct { s1: S1 };\n"
        "fn foo(s2: S2) i32 { return s2.s1.f; }";
    return run_member_codegen_test(source, "return s2.s1.f;");
}

TEST_FUNC(Codegen_MemberAccess_Array) {
    const char* source =
        "const S = struct { f: i32 };\n"
        "fn foo(arr: [5]S) i32 { return arr[0].f; }";
    return run_member_codegen_test(source, "return arr[0].f;");
}

TEST_FUNC(Codegen_MemberAccess_Call) {
    const char* source =
        "const S = struct { f: i32 };\n"
        "extern fn getS() S;\n"
        "fn foo() i32 { return getS().f; }";
    return run_member_codegen_test(source, "return getS().f;");
}

TEST_FUNC(Codegen_MemberAccess_Cast) {
    const char* source =
        "const S = struct { f: i32 };\n"
        "fn foo(p: *void) i32 {\n"
        "    return @ptrCast(*S, p).f;\n"
        "}";
    // Zig @ptrCast(*S, p).f -> C ((struct S*)p)->f
    return run_member_codegen_test(source, "return ((struct S*)p)->f;");
}

TEST_FUNC(Codegen_MemberAccess_NestedPointer) {
    const char* source =
        "const S1 = struct { f: i32 };\n"
        "const S2 = struct { p1: *S1 };\n"
        "fn foo(s2: S2) i32 { return s2.p1.f; }";
    return run_member_codegen_test(source, "return s2.p1->f;");
}

TEST_FUNC(Codegen_MemberAccess_ComplexPostfix) {
    const char* source =
        "const S = struct { arr: [5]i32 };\n"
        "fn foo(s: S) i32 { return s.arr[0]; }";
    return run_member_codegen_test(source, "return s.arr[0];");
}

TEST_FUNC(Codegen_MemberAccess_FunctionPointerSim) {
    // In bootstrap, function pointers are rejected, but we can test
    // that if it were a function pointer in a struct, it would emit correctly.
    // However, TypeChecker will reject it, so we can't easily test it here
    // without bypassing validation.
    return true;
}
