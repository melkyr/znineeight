#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "error_handler.hpp"
#include "compilation_unit.hpp"
#include "parser.hpp"

TEST_FUNC(binary_op_arithmetic_valid_cases) {
    const char* source = "fn test_fn() { var a: i32 = 1; var b: i32 = 2; var c: i32 = a + b; }";
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser.parse();
    ASSERT_TRUE(ast != NULL);
    TypeChecker checker(comp_unit);
    checker.check(ast);
    ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(binary_op_arithmetic_invalid_cases) {
    const char* source = "fn test_fn() { var a: i32 = 1; var b: i16 = 2; var c: i32 = a + b; }";
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser.parse();
    ASSERT_TRUE(ast != NULL);
    TypeChecker checker(comp_unit);
    checker.check(ast);
    ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
    const ErrorReport* error = &comp_unit.getErrorHandler().getErrors()[0];
    ASSERT_EQ(ERR_TYPE_MISMATCH, error->code);
    ASSERT_TRUE(strstr(error->message, "arithmetic operation '+' requires operands of the same type. Got 'i32' and 'i16'.") != NULL);
    return true;
}

TEST_FUNC(binary_op_bitwise_invalid_non_integer) {
    const char* source = "fn test_fn() { var a: bool = true; var b: bool = false; var c: bool = a & b; }";
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser.parse();
    ASSERT_TRUE(ast != NULL);
    TypeChecker checker(comp_unit);
    checker.check(ast);
    ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
    const ErrorReport* error = &comp_unit.getErrorHandler().getErrors()[0];
    ASSERT_EQ(ERR_TYPE_MISMATCH, error->code);
    ASSERT_TRUE(strstr(error->message, "invalid operands for bitwise operator '&'. Operands must be integer types. Got 'bool' and 'bool'") != NULL);
    return true;
}

TEST_FUNC(binary_op_bitwise_invalid_mismatched_integers) {
    const char* source = "fn test_fn() { var a: u8 = 1u; var b: u16 = 2u; var c: u16 = a | b; }";
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser.parse();
    ASSERT_TRUE(ast != NULL);
    TypeChecker checker(comp_unit);
    checker.check(ast);
    ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
    const ErrorReport* error = &comp_unit.getErrorHandler().getErrors()[0];
    ASSERT_EQ(ERR_TYPE_MISMATCH, error->code);
    ASSERT_TRUE(strstr(error->message, "bitwise operation '|' requires operands of the same type. Got 'u8' and 'u16'.") != NULL);
    return true;
}

TEST_FUNC(binary_op_logical_invalid_non_boolean) {
    const char* source = "fn test_fn() { var a: i32 = 1; var b: i32 = 0; var c: bool = a && b; }";
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser.parse();
    ASSERT_TRUE(ast != NULL);
    TypeChecker checker(comp_unit);
    checker.check(ast);
    ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
    const ErrorReport* error = &comp_unit.getErrorHandler().getErrors()[0];
    ASSERT_EQ(ERR_TYPE_MISMATCH, error->code);
    ASSERT_TRUE(strstr(error->message, "logical operator '&&' requires boolean operands. Got 'i32' and 'i32'") != NULL);
    return true;
}

TEST_FUNC(binary_op_comparison_invalid_mismatched_numerics) {
    const char* source = "fn test_fn() { var a: i32 = 1; var b: f64 = 2.0; var c: bool = a == b; }";
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser.parse();
    ASSERT_TRUE(ast != NULL);
    TypeChecker checker(comp_unit);
    checker.check(ast);
    ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
    const ErrorReport* error = &comp_unit.getErrorHandler().getErrors()[0];
    ASSERT_EQ(ERR_TYPE_MISMATCH, error->code);
    ASSERT_TRUE(strstr(error->message, "comparison requires operands of the same type for operator '=='. Got 'i32' and 'f64'.") != NULL);
    return true;
}
