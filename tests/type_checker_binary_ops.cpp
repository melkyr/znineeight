#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "error_handler.hpp"
#include "compilation_unit.hpp"
#include <cstdio>

// Forward declarations for tests
TEST_FUNC(BinaryOps_Arithmetic);
TEST_FUNC(BinaryOps_Comparison);
TEST_FUNC(BinaryOps_Bitwise);
TEST_FUNC(BinaryOps_Logical);

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

static bool expect_no_type_errors(const char* source_code) {
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
    if (handler.hasErrors()) {
        printf("    --> Test failed: Expected no errors, but got %lu.\n", (unsigned long)handler.getErrors().length());
        handler.printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(BinaryOps_Arithmetic) {
    // Valid cases
    ASSERT_TRUE(expect_no_type_errors("fn test() { var x: i32 = 1 + 2; }"));
    ASSERT_TRUE(expect_no_type_errors("fn test() { var y: f64 = 3.0 - 1.5; }"));
    ASSERT_TRUE(expect_no_type_errors("fn test() { var z: u16 = 10 * 2; }"));
    ASSERT_TRUE(expect_no_type_errors("fn test() { var a: i8 = 10 / 2; }"));
    ASSERT_TRUE(expect_no_type_errors("fn test() { var b: u32 = 10 % 3; }"));

    // Invalid cases
    ASSERT_TRUE(expect_type_error("fn test() { var x = 1 + 1.0; }", ERR_TYPE_MISMATCH));
    ASSERT_TRUE(expect_type_error("fn test() { var y = 1 - true; }", ERR_TYPE_MISMATCH));
    ASSERT_TRUE(expect_type_error("fn test() { var z = 1 * 'a'; }", ERR_TYPE_MISMATCH));
    return true;
}

TEST_FUNC(BinaryOps_Comparison) {
    // Valid cases
    ASSERT_TRUE(expect_no_type_errors("fn test() { var x = 1 == 2; }"));
    ASSERT_TRUE(expect_no_type_errors("fn test() { var y = 3.0 != 1.5; }"));
    ASSERT_TRUE(expect_no_type_errors("fn test() { var z = 10 < 2; }"));
    ASSERT_TRUE(expect_no_type_errors("fn test() { var a = 10 > 2; }"));
    ASSERT_TRUE(expect_no_type_errors("fn test() { var b = 10 <= 3; }"));
    ASSERT_TRUE(expect_no_type_errors("fn test() { var c = 10 >= 3; }"));

    // Invalid cases
    ASSERT_TRUE(expect_type_error("fn test() { var x = 1 == 1.0; }", ERR_TYPE_MISMATCH));
    ASSERT_TRUE(expect_type_error("fn test() { var y = 1 != true; }", ERR_TYPE_MISMATCH));
    ASSERT_TRUE(expect_type_error("fn test() { var z = 1 < 'a'; }", ERR_TYPE_MISMATCH));
    return true;
}

TEST_FUNC(BinaryOps_Bitwise) {
    // Valid cases
    ASSERT_TRUE(expect_no_type_errors("fn test() { var x: i32 = 1 & 2; }"));
    ASSERT_TRUE(expect_no_type_errors("fn test() { var y: u8 = 3 | 1; }"));
    ASSERT_TRUE(expect_no_type_errors("fn test() { var z: i16 = 10 ^ 2; }"));
    ASSERT_TRUE(expect_no_type_errors("fn test() { var a: u64 = 10 << 2; }"));
    ASSERT_TRUE(expect_no_type_errors("fn test() { var b: i32 = 10 >> 1; }"));

    // Invalid cases
    ASSERT_TRUE(expect_type_error("fn test() { var x = 1 & 1.0; }", ERR_TYPE_MISMATCH));
    ASSERT_TRUE(expect_type_error("fn test() { var y = 1 | true; }", ERR_TYPE_MISMATCH));
    ASSERT_TRUE(expect_type_error("fn test() { var z = 1 ^ 'a'; }", ERR_TYPE_MISMATCH));
    return true;
}

TEST_FUNC(BinaryOps_Logical) {
    // Valid cases
    ASSERT_TRUE(expect_no_type_errors("fn test() { var x = true && false; }"));
    ASSERT_TRUE(expect_no_type_errors("fn test() { var y = true || false; }"));

    // Invalid cases
    ASSERT_TRUE(expect_type_error("fn test() { var x = 1 && true; }", ERR_TYPE_MISMATCH));
    ASSERT_TRUE(expect_type_error("fn test() { var y = false || 0; }", ERR_TYPE_MISMATCH));
    ASSERT_TRUE(expect_type_error("fn test() { var z = 1.0 || 2.0; }", ERR_TYPE_MISMATCH));
    return true;
}
