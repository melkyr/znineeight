#include "test_framework.hpp"
#include "test_utils.hpp"
#include "ast.hpp"
#include "parser.hpp"
#include "type_checker.hpp"

// Forward declarations for test functions
TEST_FUNC(TypeCheckerC89Compat_AllowFunctionWithManyArgs);
TEST_FUNC(TypeCheckerC89Compat_AllowFunctionPointerCall);
TEST_FUNC(TypeChecker_Call_WrongArgumentCount);
TEST_FUNC(TypeChecker_Call_IncompatibleArgumentType);

TEST_FUNC(TypeCheckerC89Compat_AllowFunctionWithManyArgs) {
    const char* source =
        "fn five_args(a: i32, b: i32, c: i32, d: i32, e: i32) void {}\n"
        "fn main_func() void {\n"
        "    five_args(1, 2, 3, 4, 5);\n"
        "}\n";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(TypeCheckerC89Compat_AllowFunctionPointerCall) {
    const char* source =
        "fn my_func() void {}\n"
        "fn main_func() void {\n"
        "    var func_ptr = my_func;\n"
        "    func_ptr();\n"
        "}\n";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(TypeChecker_Call_WrongArgumentCount) {
    const char* source =
        "fn two_args(a: i32, b: i32) void {}\n"
        "fn main_func() void {\n"
        "    two_args(1);\n"
        "}\n";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeChecker_Call_IncompatibleArgumentType) {
    const char* source =
        "fn needs_i32(a: i32) void {}\n"
        "fn main_func() void {\n"
        "    needs_i32(\"hello\");\n"
        "}\n";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeChecker_C89_StructFieldValidation_Slice) {
    const char* source = "const S = struct { field: []u8 };";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeChecker_C89_UnionFieldValidation_MultiLevelPointer) {
    const char* source = "const U = union { field: **i32 };";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(TypeChecker_C89_StructFieldValidation_ValidArray) {
    const char* source = "const S = struct { field: [8]u8 };";
    // This should not abort
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();
    TypeChecker checker(unit);
    checker.check(root);
    ASSERT_FALSE(unit.getErrorHandler().hasErrors()); // Ensure no non-fatal errors either
    return true;
}

TEST_FUNC(TypeChecker_C89_UnionFieldValidation_ValidFields) {
    const char* source = "const U = struct { a: i32, b: *u8, c: [4]f64 };";
    // This should not abort
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();
    TypeChecker checker(unit);
    checker.check(root);
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    return true;
}
