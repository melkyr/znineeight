#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "codegen.hpp"
#include <cstdio>
#include <cstring>

/**
 * @file for_ptr_array_tests.cpp
 * @brief Integration tests for for loops over pointers to arrays.
 */

TEST_FUNC(Codegen_ForPtrToArray) {
    const char* source =
        "fn foo(ptr: *[5]i32) void {\n"
        "    for (ptr) |item| {\n"
        "        _ = item;\n"
        "    }\n"
        "}\n";
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTFnDeclNode* fn = unit.extractFunctionDeclaration("foo");
    if (!fn) return false;

    const char* temp_path = "temp_for_ptr_array_test.c";
    C89Emitter emitter(unit, temp_path);
    if (!emitter.isValid()) return false;

    emitter.emitFnDecl(fn);
    emitter.flush();
    emitter.close();

    PlatFile f = plat_open_file(temp_path, false);
    if (f == PLAT_INVALID_FILE) return false;
    char buffer[4096];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer) - 1);
    buffer[bytes] = '\0';
    plat_close_file(f);

    if (strstr(buffer, "__for_len_1 = 5;") == NULL) {
        printf("FAIL: Loop length 5 not found in emission for pointer-to-array. Emission:\n%s\n", buffer);
        return false;
    }

    return true;
}
