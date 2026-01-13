#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "error_handler.hpp"
#include "compilation_unit.hpp"
#include "parser.hpp"

// This helper function now returns the error status, so the TEST_FUNC can use the ASSERT macros.
static bool run_assignment_test_and_get_error_status(const char* source) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    TypeChecker type_checker(unit);
    type_checker.check(root);

    return unit.getErrorHandler().hasErrors();
}

TEST_FUNC(TypeChecker_Assignment_Valid) {
    const char* source =
        "fn test_fn() {\n"
        "    var a: i32 = 10;\n"
        "    var b: i32 = a;\n"
        "    var c: *i32 = null;\n"
        "    var d: *const i32 = c;\n"
        "}\n";
    ASSERT_FALSE(run_assignment_test_and_get_error_status(source));
    return true;
}

TEST_FUNC(TypeChecker_Assignment_InvalidNumeric) {
    const char* source =
        "fn test_fn() {\n"
        "    var a: i32 = 10;\n"
        "    var b: i16 = a;\n"
        "}\n";
    ASSERT_TRUE(run_assignment_test_and_get_error_status(source));
    return true;
}

TEST_FUNC(TypeChecker_Assignment_InvalidPointer) {
    const char* source =
        "fn test_fn() {\n"
        "    var a: *i32 = null;\n"
        "    var b: *u8 = a;\n"
        "}\n";
    ASSERT_TRUE(run_assignment_test_and_get_error_status(source));
    return true;
}

TEST_FUNC(TypeChecker_Assignment_InvalidConstPointer) {
    const char* source =
        "fn test_fn() {\n"
        "    var a: *const i32 = null;\n"
        "    var b: *i32 = a;\n"
        "}\n";
    ASSERT_TRUE(run_assignment_test_and_get_error_status(source));
    return true;
}

TEST_FUNC(TypeChecker_Assignment_InvalidVoidPointer) {
    const char* source =
        "fn test_fn() {\n"
        "    var a: *void = null;\n"
        "    var b: *i32 = a;\n"
        "}\n";
    ASSERT_TRUE(run_assignment_test_and_get_error_status(source));
    return true;
}

TEST_FUNC(TypeChecker_CompoundAssignment_Valid) {
    const char* source =
        "fn test_fn() {\n"
        "    var a: i32 = 10;\n"
        "    var b: i32 = 5;\n"
        "    a += b;\n"
        "}\n";
    ASSERT_FALSE(run_assignment_test_and_get_error_status(source));
    return true;
}

TEST_FUNC(TypeChecker_CompoundAssignment_Invalid) {
    const char* source =
        "fn test_fn() {\n"
        "    var a: i32 = 10;\n"
        "    var b: i16 = 5;\n"
        "    a += b;\n"
        "}\n";
    ASSERT_TRUE(run_assignment_test_and_get_error_status(source));
    return true;
}
