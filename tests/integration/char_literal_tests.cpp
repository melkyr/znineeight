#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include "c89_validator.hpp"
#include <cstdio>
#include <cstring>
#include <string>

/**
 * @file char_literal_tests.cpp
 * @brief Integration tests for character literal constant evaluation.
 */

static bool run_char_literal_codegen_test(const char* zig_code, const char* expected_c89_substring) {
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
    const char* temp_filename = "temp_char_test.c";
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
            for (size_t i = 0; i < stmts->length(); ++i) {
                emitter.emitTypeDefinition((*stmts)[i]);
            }
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

TEST_FUNC(CharLiteralRange_Basic) {
    const char* source =
        "export fn isDigit(c: u8) bool {\n"
        "    return switch (c) {\n"
        "        '0'...'9' => true,\n"
        "        else => false,\n"
        "    };\n"
        "}\n";

    /* Expect case labels 48 through 57 (ASCII for '0' through '9') */
    return run_char_literal_codegen_test(source, "case 48:");
}

TEST_FUNC(CharLiteral_ConstantVar) {
    const char* source =
        "const zero = '0';\n"
        "const nine = '9';\n"
        "export fn isDigit(c: u8) bool {\n"
        "    return switch (c) {\n"
        "        zero...nine => true,\n"
        "        else => false,\n"
        "    };\n"
        "}\n";

    return run_char_literal_codegen_test(source, "case 48:");
}
