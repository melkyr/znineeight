#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"

TEST_FUNC(TypeChecker_VarDecl_Valid_Simple) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    const char* source = "const x: i32 = 42;";
    ParserTestContext ctx(source, arena, interner);
    TypeChecker type_checker(ctx.getCompilationUnit());

    ASTNode* root = ctx.getParser()->parse();
    ASSERT_TRUE(root != NULL);

    type_checker.check(root);

    ASSERT_FALSE(ctx.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeChecker_VarDecl_Multiple_Errors) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    const char* source = "const x: i32 = \"hello\"; const y: f32 = 12;";
    ParserTestContext ctx(source, arena, interner);
    TypeChecker type_checker(ctx.getCompilationUnit());

    ASTNode* root = ctx.getParser()->parse();
    ASSERT_TRUE(root != NULL);

    type_checker.check(root);

    ErrorHandler& eh = ctx.getCompilationUnit().getErrorHandler();
    ASSERT_TRUE(eh.hasErrors());

    const DynamicArray<ErrorReport>& errors = eh.getErrors();
    ASSERT_TRUE(errors.length() >= 1);
    /* We now report multiple errors, so just check the first one and use strstr for robustness */
    ASSERT_STREQ(errors[0].message, "type mismatch");
    ASSERT_TRUE(errors[0].hint != NULL && strstr(errors[0].hint, "Incompatible assignment: '*const u8' to 'i32'") != NULL);

    return true;
}

TEST_FUNC(TypeChecker_VarDecl_Invalid_Mismatch) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    const char* source = "const x: i32 = \"hello\";";
    ParserTestContext ctx(source, arena, interner);
    TypeChecker type_checker(ctx.getCompilationUnit());

    ASTNode* root = ctx.getParser()->parse();
    ASSERT_TRUE(root != NULL);

    type_checker.check(root);

    ErrorHandler& eh = ctx.getCompilationUnit().getErrorHandler();
    ASSERT_TRUE(eh.hasErrors());

    const DynamicArray<ErrorReport>& errors = eh.getErrors();
    ASSERT_TRUE(errors.length() >= 1);
    ASSERT_STREQ(errors[0].message, "type mismatch");
    ASSERT_TRUE(errors[0].hint != NULL && strstr(errors[0].hint, "Incompatible assignment: '*const u8' to 'i32'") != NULL);

    return true;
}

TEST_FUNC(TypeChecker_VarDecl_Invalid_Widening) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    // This test now passes. The type checker's `visitVarDecl` has been updated
    // with a special case for integer literals, which is the correct C89 behavior.
    // An integer literal (like 42, which is inferred as i32) can be assigned to a
    // variable of a wider type (like i64) as long as the value fits.
    const char* source = "const x: i64 = 42;";
    ParserTestContext ctx(source, arena, interner);
    TypeChecker type_checker(ctx.getCompilationUnit());

    ASTNode* root = ctx.getParser()->parse();
    ASSERT_TRUE(root != NULL);

    type_checker.check(root);

    ErrorHandler& eh = ctx.getCompilationUnit().getErrorHandler();
    ASSERT_FALSE(eh.hasErrors());

    return true;
}
