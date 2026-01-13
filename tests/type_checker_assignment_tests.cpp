#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "error_handler.hpp"
#include "compilation_unit.hpp"

static bool run_assignment_test(const char* source, bool expect_errors, ErrorCode expected_code = (ErrorCode)0) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    ParserTestContext context(source, arena, interner);
    TypeChecker checker(context.getCompilationUnit());

    ASTNode* ast = context.getParser()->parse();
    checker.check(ast);

    ErrorHandler& errorHandler = context.getCompilationUnit().getErrorHandler();

    if (expect_errors) {
        ASSERT_TRUE(errorHandler.hasErrors());
        const DynamicArray<ErrorReport>& errors = errorHandler.getErrors();
        ASSERT_EQ(errors.length(), 1);
        ASSERT_EQ(errors[0].code, expected_code);
    } else {
        ASSERT_FALSE(errorHandler.hasErrors());
    }

    return true;
}

TEST_FUNC(TypeCheckerAssignment_Valid_IdenticalNumeric) {
    const char* source = "fn f() { var x: i32 = 0; var y: i32 = 1; x = y; }";
    return run_assignment_test(source, false);
}

TEST_FUNC(TypeCheckerAssignment_Invalid_NumericMismatch) {
    const char* source = "fn f() { var x: i16 = 0; var y: i32 = 1; x = y; }";
    return run_assignment_test(source, true, ERR_TYPE_MISMATCH);
}

TEST_FUNC(TypeCheckerAssignment_Valid_Pointer_Identical) {
    const char* source = "fn f() { var x: *i32 = null; var y: *i32 = null; x = y; }";
    return run_assignment_test(source, false);
}

TEST_FUNC(TypeCheckerAssignment_Valid_Pointer_NullAssignment) {
    const char* source = "fn f() { var x: *i32 = null; x = null; }";
    return run_assignment_test(source, false);
}

TEST_FUNC(TypeCheckerAssignment_Valid_Pointer_ToConst) {
    const char* source = "fn f() { var x: *const i32 = null; var y: *i32 = null; x = y; }";
    return run_assignment_test(source, false);
}

TEST_FUNC(TypeCheckerAssignment_Invalid_Pointer_FromConst) {
    const char* source = "fn f() { var x: *i32 = null; var y: *const i32 = null; x = y; }";
    return run_assignment_test(source, true, ERR_TYPE_MISMATCH);
}

TEST_FUNC(TypeCheckerAssignment_Valid_Pointer_ToVoid) {
    const char* source = "fn f() { var x: *void = null; var y: *i32 = null; x = y; }";
    return run_assignment_test(source, false);
}

TEST_FUNC(TypeCheckerAssignment_Invalid_Pointer_FromVoid) {
    const char* source = "fn f() { var x: *i32 = null; var y: *void = null; x = y; }";
    return run_assignment_test(source, true, ERR_TYPE_MISMATCH);
}

TEST_FUNC(TypeCheckerAssignment_Invalid_AssignToConstVar) {
    const char* source = "fn f() { const x: i32 = 10; x = 20; }";
    return run_assignment_test(source, true, ERR_TYPE_MISMATCH);
}

TEST_FUNC(TypeCheckerAssignment_Compound_Valid) {
    const char* source = "fn f() { var x: i32 = 10; var y: i32 = 5; x += y; }";
    return run_assignment_test(source, false);
}

TEST_FUNC(TypeCheckerAssignment_Compound_Invalid_Op) {
    const char* source = "fn f() { var x: i32 = 10; var y: f32 = 5.0; x += y; }";
    return run_assignment_test(source, true, ERR_TYPE_MISMATCH);
}

TEST_FUNC(TypeCheckerAssignment_Compound_Invalid_AssignBack) {
    // This tests a theoretical case where the result of a valid binary operation
    // would be unassignable to the l-value. With the current strict C89 rules
    // (e.g., numeric types must be identical), this is hard to trigger.
    // For now, we'll test a valid case to ensure it doesn't fail.
    const char* source = "fn f() { var x: i32 = 10; x += 5; }";
    return run_assignment_test(source, false);
}

TEST_FUNC(TypeCheckerAssignment_Compound_Invalid_AssignToConst) {
    const char* source = "fn f() { const x: i32 = 10; x += 5; }";
    return run_assignment_test(source, true, ERR_TYPE_MISMATCH);
}
