#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "error_handler.hpp"
#include "compilation_unit.hpp"
#include <cstdio>

// Forward declarations for tests
TEST_FUNC(Arithmetic_Addition_RequiresSameType);
TEST_FUNC(Arithmetic_Subtraction_RequiresSameType);
TEST_FUNC(Arithmetic_Multiplication_RequiresSameType);
TEST_FUNC(Arithmetic_Division_RequiresSameType);
TEST_FUNC(Arithmetic_Modulus_RequiresSameType);

static bool expect_type_error(const char* source_code, ErrorCode expected_error) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source_code);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser.parse();

    TypeChecker type_checker(comp_unit);
    type_checker.check(ast);

    ErrorHandler& handler = comp_unit.getErrorHandler();
    if (!handler.hasErrors()) {
        printf("    --> Test failed: Expected error code %d, but got no errors.\n", expected_error);
        return false;
    }

    if (handler.getErrors()[0].code != expected_error) {
        printf("    --> Test failed: Expected error code %d, but got %d.\n", expected_error, handler.getErrors()[0].code);
        handler.printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(Arithmetic_Addition_RequiresSameType) {
    const char* source = "fn test() { var x: i32 = 1; var y: i16 = 2; if (x + y) {} }";
    ASSERT_TRUE(expect_type_error(source, ERR_TYPE_MISMATCH));
    return true;
}

TEST_FUNC(Arithmetic_Subtraction_RequiresSameType) {
    const char* source = "fn test() { var x: i32 = 1; var y: i16 = 2; if (x - y) {} }";
    ASSERT_TRUE(expect_type_error(source, ERR_TYPE_MISMATCH));
    return true;
}

TEST_FUNC(Arithmetic_Division_RequiresSameType) {
    const char* source = "fn test() { var x: i32 = 1; var y: i16 = 2; if (x / y) {} }";
    ASSERT_TRUE(expect_type_error(source, ERR_TYPE_MISMATCH));
    return true;
}

TEST_FUNC(Arithmetic_Modulus_RequiresSameType) {
    const char* source = "fn test() { var x: i32 = 1; var y: i16 = 2; if (x % y) {} }";
    ASSERT_TRUE(expect_type_error(source, ERR_TYPE_MISMATCH));
    return true;
}

TEST_FUNC(Arithmetic_Multiplication_RequiresSameType) {
    const char* source = "fn test() { var x: i32 = 1; var y: i16 = 2; if (x * y) {} }";
    ASSERT_TRUE(expect_type_error(source, ERR_TYPE_MISMATCH));
    return true;
}
