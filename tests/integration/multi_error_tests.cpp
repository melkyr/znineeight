#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include <cstdio>
#include <cstring>

/**
 * @file multi_error_tests.cpp
 * @brief Integration tests for recoverable multi-error reporting.
 */

TEST_FUNC(MultiError_Reporting) {
    const char* source =
        "fn func1() void {\n"
        "    var x: i32 = \"hello\"; // Error 1: Type mismatch\n"
        "}\n"
        "fn func2() void {\n"
        "    y = 10;               // Error 2: Undefined variable\n"
        "}\n"
        "fn func3() void {\n"
        "    var p: *i32 = 100;    // Error 3: Integer to pointer mismatch\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    /* performTestPipeline returns false if any errors are reported */
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline should have failed due to multiple errors.\n");
        return false;
    }

    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();

    /* We expect at least 3 errors */
    if (errors.length() < 3) {
        printf("FAIL: Expected at least 3 errors, got %d.\n", (int)errors.length());
        unit.getErrorHandler().printErrors();
        return false;
    }

    bool found_type_mismatch = false;
    bool found_undefined_var = false;
    bool found_ptr_mismatch = false;

    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_TYPE_MISMATCH) {
             if (errors[i].hint && strstr(errors[i].hint, "'*const u8' to 'i32'")) found_type_mismatch = true;
             if (errors[i].hint && strstr(errors[i].hint, "'i32' to '*i32'")) found_ptr_mismatch = true;
        }
        if (errors[i].code == ERR_UNDEFINED_VARIABLE) found_undefined_var = true;
    }

    if (!found_type_mismatch) {
        printf("FAIL: ERR_TYPE_MISMATCH (string) not found.\n");
    }
    if (!found_undefined_var) {
        printf("FAIL: ERR_UNDEFINED_VARIABLE ('y') not found.\n");
    }
    if (!found_ptr_mismatch) {
        printf("FAIL: ERR_TYPE_MISMATCH (pointer) not found.\n");
    }

    if (!(found_type_mismatch && found_undefined_var && found_ptr_mismatch)) {
        unit.getErrorHandler().printErrors();
    }

    return found_type_mismatch && found_undefined_var && found_ptr_mismatch;
}
