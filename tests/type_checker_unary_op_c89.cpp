#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "error_handler.hpp"
#include "ast.hpp"

TEST_FUNC(TypeCheckerUnaryOp_BitwiseNotOnFloat_ShouldFail) {
    // C89 requires that the bitwise NOT operator (~) only be applied to integer types.
    // Applying it to a float should be a fatal type error.
    const char* source = "fn test_fn() { var x = ~1.23; }";
    expect_type_checker_abort(source);
    return true;
}

TEST_FUNC(TypeCheckerUnaryOp_BitwiseNotOnBool_ShouldFail) {
    // Applying bitwise NOT to a boolean is not a valid C89 operation.
    const char* source = "fn test_fn() { var x = ~true; }";
    expect_type_checker_abort(source);
    return true;
}

TEST_FUNC(TypeCheckerUnaryOp_NegatePointer_ShouldFail) {
    // Negating a pointer is not a valid C89 operation.
    // NOTE: Parser does not support `null` yet. We need to get a pointer another way.
    const char* source_workaround = "fn test_fn() { var y: i32 = 10; var p: *i32 = &y; var x = -p; }";
    expect_type_checker_abort(source_workaround);
    return true;
}

TEST_FUNC(TypeCheckerUnaryOp_NegateBool_ShouldFail) {
    // Negating a boolean is not a valid C89 operation.
    const char* source = "fn test_fn() { var x = -true; }";
    expect_type_checker_abort(source);
    return true;
}

TEST_FUNC(TypeCheckerUnaryOp_LogicalNotResultType_ShouldBeBool) {
    // The logical NOT operator (!) should always produce a result of type bool.
    const char* source = "fn test_fn() { var x = !10; }"; // ! applied to an integer
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    TypeChecker checker(unit);
    checker.check(root);

    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    // Find the ASTNode for the variable declaration.
    ASTNode* fn_body = (*root->as.block_stmt.statements)[0]->as.fn_decl->body;
    ASTNode* var_decl_node = (*fn_body->as.block_stmt.statements)[0];
    ASTNode* unary_op_node = var_decl_node->as.var_decl->initializer;

    // The resolved type of `!10` must be bool.
    ASSERT_TRUE(unary_op_node->resolved_type != NULL);
    ASSERT_EQ(TYPE_BOOL, unary_op_node->resolved_type->kind);

    return true;
}
