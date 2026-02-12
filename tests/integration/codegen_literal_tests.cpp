#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include <cstdio>
#include <cstring>
#include <string>

/**
 * @file codegen_literal_tests.cpp
 * @brief Integration tests for C89 emission of string and character literals.
 */

static bool run_codegen_test(const char* zig_code, const char* expected_c89) {
    ArenaAllocator arena(1024 * 1024); // 1MB for tests
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for: %s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTNode* expr = unit.extractTestExpression();
    if (!expr) {
        printf("FAIL: Could not extract test expression from: %s\n", zig_code);
        return false;
    }

    const char* temp_filename = "temp_codegen_test.c";
    {
        C89Emitter emitter(arena, temp_filename);
        if (!emitter.isValid()) {
            printf("FAIL: Could not open temp file for writing\n");
            return false;
        }
        emitter.emitExpression(expr);
        // Destructor flushes and closes
    }

    char* buffer = NULL;
    size_t size = 0;
    if (!plat_file_read(temp_filename, &buffer, &size)) {
        printf("FAIL: Could not read back temp file\n");
        return false;
    }

    bool match = (size == strlen(expected_c89)) && (memcmp(buffer, expected_c89, size) == 0);
    if (!match) {
        printf("FAIL: Codegen mismatch for '%s'.\nExpected: %s\nActual:   %.*s\n", zig_code, expected_c89, (int)size, buffer);
    }

    plat_free(buffer);
    plat_delete_file(temp_filename);

    return match;
}

TEST_FUNC(Codegen_StringSimple) {
    return run_codegen_test("fn foo() *const u8 { return \"hello\"; }", "\"hello\"");
}

TEST_FUNC(Codegen_StringEscape) {
    return run_codegen_test("fn foo() *const u8 { return \"line1\\nline2\"; }", "\"line1\\nline2\"");
}

TEST_FUNC(Codegen_StringQuotes) {
    return run_codegen_test("fn foo() *const u8 { return \"He said \\\"Hi!\\\"\"; }", "\"He said \\\"Hi!\\\"\"");
}

TEST_FUNC(Codegen_StringOctal) {
    // ESC (0x1B) should be \033
    return run_codegen_test("fn foo() *const u8 { return \"\\x1B\"; }", "\"\\033\"");
}

TEST_FUNC(Codegen_CharSimple) {
    return run_codegen_test("fn foo() u8 { return 'A'; }", "'A'");
}

TEST_FUNC(Codegen_CharEscape) {
    return run_codegen_test("fn foo() u8 { return '\\n'; }", "'\\n'");
}

TEST_FUNC(Codegen_CharSingleQuote) {
    return run_codegen_test("fn foo() u8 { return '\\''; }", "'\\''");
}

TEST_FUNC(Codegen_CharDoubleQuote) {
    return run_codegen_test("fn foo() u8 { return '\"'; }", "'\"'");
}

TEST_FUNC(Codegen_CharOctal) {
    // 0x7F should be \177
    return run_codegen_test("fn foo() u8 { return '\\x7F'; }", "'\\177'");
}

TEST_FUNC(Codegen_StringSymbolicEscapes) {
    // Test Zig-supported symbolic escapes that map to C symbolic escapes
    return run_codegen_test("fn foo() *const u8 { return \"\\n\\r\\t\\\\\\\"\"; }", "\"\\n\\r\\t\\\\\\\"\"");
}

TEST_FUNC(Codegen_StringAllC89Escapes) {
    // Test that non-symbolic-in-Zig escapes map to symbolic-in-C escapes when appropriate
    // Zig \x07 (BEL) -> C \a
    // Zig \x08 (BS)  -> C \b
    // Zig \x0C (FF)  -> C \f
    // Zig \x0B (VT)  -> C \v
    return run_codegen_test("fn foo() *const u8 { return \"\\x07\\x08\\x0C\\x0B\"; }", "\"\\a\\b\\f\\v\"");
}
