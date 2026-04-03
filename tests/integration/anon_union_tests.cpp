#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include "c89_validator.hpp"
#include <cstdio>
#include <cstring>
#include <string>

/**
 * @file anon_union_tests.cpp
 * @brief Integration tests for anonymous union emission in C89Emitter.
 */

static bool run_anon_union_codegen_test(const char* zig_code, const char* expected_c89_substring) {
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
    const char* temp_filename = "temp_anon_union_test.c";
    {
        C89Emitter emitter(unit, temp_filename);
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

    bool found = unit.containsPattern(expected_c89_substring, generated_c);
    if (!found) {
        printf("FAIL: Codegen mismatch for:\n%s\nExpected to find pattern: %s\nActual output:   %s\n", zig_code, expected_c89_substring, generated_c.c_str());
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

TEST_FUNC(Codegen_AnonymousUnion_Basic) {
    const char* source =
        "const S = struct {\n"
        "    data: union {\n"
        "        z_int: i32,\n"
        "        z_float: f64,\n"
        "    },\n"
        "    tag: i32,\n"
        "};\n"
        "export fn my_test() void {\n"
        "    var s: S = undefined;\n"
        "    s.data.z_int = 42;\n"
        "}\n";

    return run_anon_union_codegen_test(source, "union zU_#_anon_# data;");
}

TEST_FUNC(Codegen_AnonymousUnion_Nested) {
    const char* source =
        "const S = struct {\n"
        "    data: union {\n"
        "        z_inner: union {\n"
        "            val: i32,\n"
        "        },\n"
        "        z_other: f32,\n"
        "    },\n"
        "};\n"
        "export fn my_test() void {\n"
        "    var s: S = undefined;\n"
        "    s.data.z_inner.val = 10;\n"
        "}\n";

    return run_anon_union_codegen_test(source, "union zU_#_anon_# data;");
}

TEST_FUNC(Codegen_AnonymousStruct_Nested) {
    const char* source =
        "const S = struct {\n"
        "    data: struct {\n"
        "        z_inner: struct {\n"
        "            val: i32,\n"
        "        },\n"
        "        z_other: f32,\n"
        "    },\n"
        "};\n"
        "export fn my_test() void {\n"
        "    var s: S = undefined;\n"
        "    s.data.z_inner.val = 10;\n"
        "}\n";

    return run_anon_union_codegen_test(source, "struct zS_#_anon_# data;");
}
