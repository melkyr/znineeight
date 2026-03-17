#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "codegen.hpp"
#include <cstdio>
#include <cstring>

/**
 * @file string_split_tests.cpp
 * @brief Integration tests for string literal splitting.
 */

TEST_FUNC(Codegen_StringSplit) {
    const char* source = "pub const long_string = \"1234567890123456789012345\";\n";
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTVarDeclNode* decl = unit.extractVariableDeclaration("long_string");
    if (!decl) return false;

    // Use actual C89Emitter with a low threshold
    const char* temp_path = "temp_string_split_test.c";
    C89Emitter emitter(unit, temp_path);
    if (!emitter.isValid()) return false;

    emitter.setMaxStringLiteralChunk(20);
    emitter.emitGlobalVarDecl((*unit.last_ast->as.block_stmt.statements)[0], true);
    emitter.flush();
    emitter.close();

    PlatFile f = plat_open_file(temp_path, false);
    if (f == PLAT_INVALID_FILE) return false;
    char buffer[4096];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer) - 1);
    buffer[bytes] = '\0';
    plat_close_file(f);

    // With threshold 20, "1234567890123456789012345" should be split
    if (strstr(buffer, "\" \"") == NULL) {
        printf("FAIL: String literal was not split as expected. Emission:\n%s\n", buffer);
        return false;
    }

    return true;
}
