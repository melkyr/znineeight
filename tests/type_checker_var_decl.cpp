#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"

TEST_FUNC(TypeChecker_VarDecl_Valid_Simple) {
    ArenaAllocator arena(8192);
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
    ArenaAllocator arena(8192);
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
    ASSERT_TRUE(errors.length() == 2);
    ASSERT_TRUE(strcmp(errors[0].message, "cannot assign type '*const u8' to variable of type 'i32'") == 0);
    ASSERT_TRUE(strcmp(errors[1].message, "cannot assign type 'i8' to variable of type 'f32'") == 0);

    return true;
}

TEST_FUNC(TypeChecker_VarDecl_Invalid_Mismatch) {
    ArenaAllocator arena(8192);
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
    ASSERT_TRUE(errors.length() == 1);
    ASSERT_TRUE(strcmp(errors[0].message, "cannot assign type '*const u8' to variable of type 'i32'") == 0);

    return true;
}

TEST_FUNC(TypeChecker_VarDecl_Valid_Widening) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    const char* source = "const x: i64 = 42;"; // 42 is an i32 literal
    ParserTestContext ctx(source, arena, interner);
    TypeChecker type_checker(ctx.getCompilationUnit());

    ASTNode* root = ctx.getParser()->parse();
    ASSERT_TRUE(root != NULL);

    type_checker.check(root);

    ASSERT_FALSE(ctx.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}
