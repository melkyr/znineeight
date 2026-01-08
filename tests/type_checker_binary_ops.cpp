#include "test_framework.hpp"
#include "test_utils.hpp"
#include "ast.hpp"
#include "lexer.hpp"
#include "parser.hpp"
#include "type_checker.hpp"
#include "error_handler.hpp"
#include <cstdio>

// Helper to get the type of the first binary expression in a test function.
static Type* get_binary_op_type(const char* source_code, ArenaAllocator& arena, const char* inner_expr) {
    char source_buffer[1024];
    snprintf(source_buffer, sizeof(source_buffer), source_code, inner_expr);

    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source_buffer);
    Parser* parser = comp_unit.createParser(file_id);
    ASTNode* root = parser.parse();

    TypeChecker checker(comp_unit);
    checker.check(root);

    if (comp_unit.getErrorHandler().hasErrors()) {
        fprintf(stderr, "Type checking failed unexpectedly for expression: %s\n", inner_expr);
        comp_unit.getErrorHandler().printErrors();
        return NULL;
    }

    // AST Path: Root (Block) -> FnDecl -> Body (Block) -> last statement (ExpressionStmt) -> Expression
    ASTNode* fn_decl = (*root->as.block_stmt.statements)[0];
    ASTNode* fn_body = fn_decl->as.fn_decl->body;
    DynamicArray<ASTNode*>* stmts = fn_body->as.block_stmt.statements;
    ASTNode* expr_stmt = (*stmts)[stmts->length() - 1];
    if (expr_stmt->type != NODE_EXPRESSION_STMT) {
        fprintf(stderr, "Test helper expected last statement to be an expression statement.\n");
        return NULL;
    }
    ASTNode* binary_op = expr_stmt->as.expression_stmt.expression;

    return binary_op->resolved_type;
}

// Helper to check that a binary expression causes a specific type error.
static bool check_binary_op_error(const char* source_code, const char* inner_expr, ErrorCode expected_error, ArenaAllocator& arena) {
    char source_buffer[1024];
    snprintf(source_buffer, sizeof(source_buffer), source_code, inner_expr);

    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source_buffer);
    Parser* parser = comp_unit.createParser(file_id);
    ASTNode* root = parser.parse();

    TypeChecker checker(comp_unit);
    checker.check(root);

    if (!comp_unit.getErrorHandler().hasErrors()) {
        fprintf(stderr, "Expected error for expression '%s', but none was reported.\n", inner_expr);
        return false;
    }

    DynamicArray<ErrorReport> errors = comp_unit.getErrorHandler().getErrors();
    if (errors[0].code == expected_error) {
        return true;
    }

    fprintf(stderr, "For expression '%s':\n", inner_expr);
    fprintf(stderr, "  Expected error code %d, but got %d.\n", expected_error, errors[0].code);
    return false;
}


TEST_FUNC(TypeCheckerBinaryOps_PointerArithmetic) {
    ArenaAllocator arena(16384);

    const char* base_source =
        "fn test_fn() {\n"
        "    var p_i32: *i32;\n"
        "    var p_const_i32: *const i32;\n"
        "    var p2_i32: *i32;\n"
        "    var p_u8: *u8;\n"
        "    var p_void: *void;\n"
        "    var i: i32 = 0;\n"
        "    %s;\n"
        "}";

    // --- Valid Pointer Arithmetic ---

    // pointer + integer
    {
        Type* result_type = get_binary_op_type(base_source, arena, "p_i32 + i");
        ASSERT_TRUE(result_type != NULL);
        ASSERT_EQ(result_type->kind, TYPE_POINTER);
        ASSERT_EQ(result_type->as.pointer.base->kind, TYPE_I32);
        ASSERT_FALSE(result_type->as.pointer.is_const);
    }

    // integer + pointer
    {
        Type* result_type = get_binary_op_type(base_source, arena, "i + p_i32");
        ASSERT_TRUE(result_type != NULL);
        ASSERT_EQ(result_type->kind, TYPE_POINTER);
        ASSERT_EQ(result_type->as.pointer.base->kind, TYPE_I32);
        ASSERT_FALSE(result_type->as.pointer.is_const);
    }

    // pointer - integer
    {
        Type* result_type = get_binary_op_type(base_source, arena, "p_i32 - i");
        ASSERT_TRUE(result_type != NULL);
        ASSERT_EQ(result_type->kind, TYPE_POINTER);
        ASSERT_EQ(result_type->as.pointer.base->kind, TYPE_I32);
        ASSERT_FALSE(result_type->as.pointer.is_const);
    }

    // pointer - pointer (same type) -> isize
    {
        Type* result_type = get_binary_op_type(base_source, arena, "p_i32 - p2_i32");
        ASSERT_TRUE(result_type != NULL);
        ASSERT_EQ(result_type->kind, TYPE_ISIZE);
    }

    // pointer - pointer (const compatible) -> isize
    {
        Type* result_type = get_binary_op_type(base_source, arena, "p_const_i32 - p_i32");
        ASSERT_TRUE(result_type != NULL);
        ASSERT_EQ(result_type->kind, TYPE_ISIZE);
    }

    // --- Invalid Pointer Arithmetic ---

    // void* pointer arithmetic is forbidden
    {
        ASSERT_TRUE(check_binary_op_error(base_source, "p_void + i", ERR_INVALID_VOID_POINTER_ARITHMETIC, arena));
        ASSERT_TRUE(check_binary_op_error(base_source, "i + p_void", ERR_INVALID_VOID_POINTER_ARITHMETIC, arena));
        ASSERT_TRUE(check_binary_op_error(base_source, "p_void - i", ERR_INVALID_VOID_POINTER_ARITHMETIC, arena));
    }

    // Subtracting incompatible pointer types
    {
        ASSERT_TRUE(check_binary_op_error(base_source, "p_i32 - p_u8", ERR_TYPE_MISMATCH, arena));
    }

    // pointer + pointer is forbidden
    {
        ASSERT_TRUE(check_binary_op_error(base_source, "p_i32 + p2_i32", ERR_TYPE_MISMATCH, arena));
    }

    return true;
}

TEST_FUNC(TypeCheckerBinaryOps_NumericArithmetic) {
    ArenaAllocator arena(16384);

    const char* base_source =
        "fn test_fn() {\n"
        "    var a_i32: i32 = 1;\n"
        "    var b_i32: i32 = 2;\n"
        "    var a_i16: i16 = 3;\n"
        "    var a_f64: f64 = 4.0;\n"
        "    var b_f64: f64 = 5.0;\n"
        "    %s;\n"
        "}";

    // --- Valid Numeric Arithmetic (Same Types) ---
    {
        Type* result_type = get_binary_op_type(base_source, arena, "a_i32 + b_i32");
        ASSERT_TRUE(result_type != NULL);
        ASSERT_EQ(result_type->kind, TYPE_I32);
    }
    {
        Type* result_type = get_binary_op_type(base_source, arena, "a_f64 * b_f64");
        ASSERT_TRUE(result_type != NULL);
        ASSERT_EQ(result_type->kind, TYPE_F64);
    }

    // --- Invalid Numeric Arithmetic (Different Types) ---
    {
        ASSERT_TRUE(check_binary_op_error(base_source, "a_i32 + a_i16", ERR_TYPE_MISMATCH, arena));
        ASSERT_TRUE(check_binary_op_error(base_source, "a_i32 / a_f64", ERR_TYPE_MISMATCH, arena));
    }

    return true;
}

TEST_FUNC(TypeCheckerBinaryOps_Comparison) {
    ArenaAllocator arena(16384);

    const char* base_source =
        "fn test_fn() {\n"
        "    var a_i32: i32 = 1;\n"
        "    var b_i32: i32 = 2;\n"
        "    var a_i16: i16 = 3;\n"
        "    var p_i32: *i32;\n"
        "    var p_u8: *u8;\n"
        "    var a_bool: bool = true;\n"
        "    var b_bool: bool = false;\n"
        "    %s;\n"
        "}";

    // --- Valid Comparisons (Same Types) ---
    {
        Type* result_type = get_binary_op_type(base_source, arena, "a_i32 == b_i32");
        ASSERT_TRUE(result_type != NULL);
        ASSERT_EQ(result_type->kind, TYPE_BOOL);
    }
    {
        Type* result_type = get_binary_op_type(base_source, arena, "a_bool != b_bool");
        ASSERT_TRUE(result_type != NULL);
        ASSERT_EQ(result_type->kind, TYPE_BOOL);
    }

    // --- Invalid Comparisons (Different Types) ---
    {
        ASSERT_TRUE(check_binary_op_error(base_source, "a_i32 > a_i16", ERR_TYPE_MISMATCH, arena));
        ASSERT_TRUE(check_binary_op_error(base_source, "p_i32 == p_u8", ERR_TYPE_MISMATCH, arena));
        ASSERT_TRUE(check_binary_op_error(base_source, "a_i32 <= a_bool", ERR_TYPE_MISMATCH, arena));
    }

    return true;
}

TEST_FUNC(TypeCheckerBinaryOps_Bitwise) {
    ArenaAllocator arena(16384);

    const char* base_source =
        "fn test_fn() {\n"
        "    var a_u32: u32 = 3000000000u;\n"
        "    var b_u32: u32 = 3000000001u;\n"
        "    var a_i32: i32 = 3;\n"
        "    var a_bool: bool = true;\n"
        "    %s;\n"
        "}";

    // --- Valid Bitwise (Same Integer Types) ---
    {
        Type* result_type = get_binary_op_type(base_source, arena, "a_u32 & b_u32");
        ASSERT_TRUE(result_type != NULL);
        ASSERT_EQ(result_type->kind, TYPE_U32);
    }
    {
        Type* result_type = get_binary_op_type(base_source, arena, "a_u32 << b_u32");
        ASSERT_TRUE(result_type != NULL);
        ASSERT_EQ(result_type->kind, TYPE_U32);
    }

    // --- Invalid Bitwise (Different Types or Non-Integer) ---
    {
        ASSERT_TRUE(check_binary_op_error(base_source, "a_u32 | a_i32", ERR_TYPE_MISMATCH, arena));
        ASSERT_TRUE(check_binary_op_error(base_source, "a_u32 ^ a_bool", ERR_TYPE_MISMATCH, arena));
    }

    return true;
}

TEST_FUNC(TypeCheckerBinaryOps_Logical) {
    ArenaAllocator arena(16384);

    const char* base_source =
        "fn test_fn() {\n"
        "    var a_bool: bool = true;\n"
        "    var b_bool: bool = false;\n"
        "    var a_i32: i32 = 1;\n"
        "    %s;\n"
        "}";

    // --- Valid Logical (Bool types) ---
    {
        Type* result_type = get_binary_op_type(base_source, arena, "a_bool and b_bool");
        ASSERT_TRUE(result_type != NULL);
        ASSERT_EQ(result_type->kind, TYPE_BOOL);
    }
     {
        Type* result_type = get_binary_op_type(base_source, arena, "a_bool or b_bool");
        ASSERT_TRUE(result_type != NULL);
        ASSERT_EQ(result_type->kind, TYPE_BOOL);
    }

    // --- Invalid Logical (Non-Bool types) ---
    {
        ASSERT_TRUE(check_binary_op_error(base_source, "a_bool and a_i32", ERR_TYPE_MISMATCH, arena));
        ASSERT_TRUE(check_binary_op_error(base_source, "a_i32 or b_bool", ERR_TYPE_MISMATCH, arena));
    }

    return true;
}
