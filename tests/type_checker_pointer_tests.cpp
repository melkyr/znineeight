#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "compilation_unit.hpp"
#include "error_handler.hpp"

// Helper to run the type checker on a snippet of code placed inside a function.
// Returns true if the type checker reports errors, false otherwise.
static bool has_type_errors(const char* source_snippet) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);

    // Wrap the snippet in a function body to make it a valid program
    char source_buffer[1024];
    sprintf(source_buffer, "fn test_fn() { %s }", source_snippet);

    u32 file_id = comp_unit.addSource("test.zig", source_buffer);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* root = parser.parse();

    if (comp_unit.getErrorHandler().hasErrors() || !root) {
        // This indicates a parser error, which is a problem with the test setup itself.
        // We print a message to make debugging easier.
        fprintf(stderr, "Test setup failed: Parser error.\n");
        return true; // Treat parser errors as test failures
    }

    TypeChecker type_checker(comp_unit);
    type_checker.check(root);

    return comp_unit.getErrorHandler().hasErrors();
}

TEST_FUNC(TypeChecker_PointerArithmetic_PointerPlusInt) {
    const char* source = "var dummy: i32 = 0; var x: *i32 = &dummy; const y: *i32 = x + 1;";
    ASSERT_FALSE(has_type_errors(source));
    return true;
}

TEST_FUNC(TypeChecker_PointerArithmetic_IntPlusPointer) {
    const char* source = "var dummy: i32 = 0; var x: *i32 = &dummy; const y: *i32 = 1 + x;";
    ASSERT_FALSE(has_type_errors(source));
    return true;
}

TEST_FUNC(TypeChecker_PointerArithmetic_PointerMinusInt) {
    const char* source = "var dummy: i32 = 0; var x: *i32 = &dummy; const y: *i32 = x - 1;";
    ASSERT_FALSE(has_type_errors(source));
    return true;
}

TEST_FUNC(TypeChecker_PointerArithmetic_PointerMinusPointer) {
    const char* source = "var d1: i32 = 0; var d2: i32 = 0; var x: *i32 = &d1; var y: *i32 = &d2; const z: isize = x - y;";
    ASSERT_FALSE(has_type_errors(source));
    return true;
}

TEST_FUNC(TypeChecker_PointerArithmetic_Invalid_PointerPlusPointer) {
    const char* source = "var d1: i32 = 0; var d2: i32 = 0; var x: *i32 = &d1; var y: *i32 = &d2; const z: i32 = x + y;";
    ASSERT_TRUE(has_type_errors(source));
    return true;
}

TEST_FUNC(TypeChecker_PointerArithmetic_Invalid_PointerMinusPointer_DifferentTypes) {
    const char* source = "var d1: i32 = 0; var d2: f32 = 0; var x: *i32 = &d1; var y: *f32 = &d2; const z: isize = x - y;";
    ASSERT_TRUE(has_type_errors(source));
    return true;
}
