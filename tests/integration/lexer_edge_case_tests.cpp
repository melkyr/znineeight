#include <cstring>
#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"

TEST_FUNC(Integration_InvalidLeadingDotFloat) {
    // Floating-point literals MUST have a leading digit (e.g., 0.123, not .123).
    // A leading dot is lexed as TOKEN_DOT.
    const char* source = "fn foo() void { var x: f32 = .123; }";
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performTestPipeline(file_id);

    // Should fail with an ambiguous naked tag error.
    ASSERT_FALSE(success);
    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    bool found_error = false;
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].hint && strstr(errors[i].hint, "Ambiguous naked tag '.123'")) {
            found_error = true;
            break;
        }
    }
    return found_error;
}

TEST_FUNC(Integration_IdentifierAsFloatLeadingDot) {
    // Regression test for assigning a naked tag to a float variable.
    const char* source = "fn foo() void { var x: f32 = 0.0; x = .123; }";
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performTestPipeline(file_id);

    ASSERT_FALSE(success);
    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    bool found_error = false;
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].hint && strstr(errors[i].hint, "Ambiguous naked tag '.123'")) {
            found_error = true;
            break;
        }
    }
    return found_error;
}

TEST_FUNC(Integration_InferenceLeadingDot) {
    // Regression test for type inference from a naked tag.
    const char* source = "fn foo() void { var x = .123; }";
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performTestPipeline(file_id);

    ASSERT_FALSE(success);
    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    bool found_error = false;
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].hint && strstr(errors[i].hint, "Ambiguous naked tag '.123'")) {
            found_error = true;
            break;
        }
    }
    return found_error;
}
