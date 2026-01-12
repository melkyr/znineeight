#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "error_handler.hpp"

TEST_FUNC(TypeChecker_Assignment_ValidCases) {
    {
        ArenaAllocator arena(4096);
        StringInterner interner(arena);
        ParserTestContext ctx("fn test() { var x: i32 = 10; var y: i32 = 0; y = x; }", arena, interner);
        TypeChecker checker(ctx.getCompilationUnit());
        checker.check(ctx.getParser()->parse());
        ASSERT_FALSE(ctx.getCompilationUnit().getErrorHandler().hasErrors());
    }
    {
        ArenaAllocator arena(4096);
        StringInterner interner(arena);
        ParserTestContext ctx("fn test() { var x: *const u8 = null; var y: *const u8 = null; y = x; }", arena, interner);
        TypeChecker checker(ctx.getCompilationUnit());
        checker.check(ctx.getParser()->parse());
        ASSERT_FALSE(ctx.getCompilationUnit().getErrorHandler().hasErrors());
    }
    {
        ArenaAllocator arena(4096);
        StringInterner interner(arena);
        ParserTestContext ctx("fn test() { var x: *u8 = null; var y: *const u8 = null; y = x; }", arena, interner);
        TypeChecker checker(ctx.getCompilationUnit());
        checker.check(ctx.getParser()->parse());
        ASSERT_FALSE(ctx.getCompilationUnit().getErrorHandler().hasErrors());
    }
    return true;
}

TEST_FUNC(TypeChecker_Assignment_InvalidNumericAssignment) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    ParserTestContext ctx("fn test() { var x: i16 = 10; var y: i32 = 0; y = x; }", arena, interner);
    TypeChecker checker(ctx.getCompilationUnit());
    checker.check(ctx.getParser()->parse());
    ASSERT_TRUE(ctx.getCompilationUnit().getErrorHandler().hasErrors());
    const ErrorReport* error = &ctx.getCompilationUnit().getErrorHandler().getErrors()[0];
    ASSERT_EQ(ERR_TYPE_MISMATCH, error->code);
    ASSERT_TRUE(strstr(error->message, "Cannot assign 'i16' to 'i32'") != NULL);
    return true;
}

TEST_FUNC(TypeChecker_Assignment_InvalidPointerAssignment) {
    {
        ArenaAllocator arena(4096);
        StringInterner interner(arena);
        ParserTestContext ctx("fn test() { var x: *const u8 = null; var y: *u8 = null; y = x; }", arena, interner);
        TypeChecker checker(ctx.getCompilationUnit());
        checker.check(ctx.getParser()->parse());
        ASSERT_TRUE(ctx.getCompilationUnit().getErrorHandler().hasErrors());
        const ErrorReport* error = &ctx.getCompilationUnit().getErrorHandler().getErrors()[0];
        ASSERT_EQ(ERR_TYPE_MISMATCH, error->code);
        ASSERT_TRUE(strstr(error->message, "Cannot assign const pointer to mutable pointer") != NULL);
    }
    {
        ArenaAllocator arena(4096);
        StringInterner interner(arena);
        ParserTestContext ctx("fn test() { var x: *i32 = null; var y: *u8 = null; y = x; }", arena, interner);
        TypeChecker checker(ctx.getCompilationUnit());
        checker.check(ctx.getParser()->parse());
        ASSERT_TRUE(ctx.getCompilationUnit().getErrorHandler().hasErrors());
        const ErrorReport* error = &ctx.getCompilationUnit().getErrorHandler().getErrors()[0];
        ASSERT_EQ(ERR_TYPE_MISMATCH, error->code);
        ASSERT_TRUE(strstr(error->message, "Cannot assign pointer to 'i32' to pointer to 'u8'") != NULL);
    }
    return true;
}

TEST_FUNC(TypeChecker_Assignment_AssignToConstError) {
    const char* source = "fn test() { const x: i32 = 10; x = 20; }";
    expect_type_checker_abort(source);
    return true;
}

TEST_FUNC(TypeChecker_CompoundAssignment_ValidCases) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    ParserTestContext ctx("fn test() { var x: i32 = 10; x += 5; }", arena, interner);
    TypeChecker checker(ctx.getCompilationUnit());
    checker.check(ctx.getParser()->parse());
    ASSERT_FALSE(ctx.getCompilationUnit().getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(TypeChecker_CompoundAssignment_InvalidCases) {
    {
        ArenaAllocator arena(4096);
        StringInterner interner(arena);
        ParserTestContext ctx("fn test() { var x: i32 = 10; x += 5.0; }", arena, interner);
        TypeChecker checker(ctx.getCompilationUnit());
        checker.check(ctx.getParser()->parse());
        ASSERT_TRUE(ctx.getCompilationUnit().getErrorHandler().hasErrors());
        const ErrorReport* error = &ctx.getCompilationUnit().getErrorHandler().getErrors()[0];
        ASSERT_EQ(ERR_TYPE_MISMATCH, error->code);
        ASSERT_TRUE(strstr(error->message, "requires operands of the same type. Got 'i32' and 'f64'") != NULL);
    }
    {
        const char* source = "fn test() { const x: i32 = 10; x += 20; }";
        expect_type_checker_abort(source);
    }
    return true;
}
