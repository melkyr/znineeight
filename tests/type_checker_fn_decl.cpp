#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "error_handler.hpp"

TEST_FUNC(TypeCheckerFnDecl_ValidSimpleParams) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    const char* source = "fn add(a: i32, b: i32) -> i32 { return a + b; }";
    ParserTestContext context(source, arena, interner);

    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    ASSERT_TRUE(root != NULL);

    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    ASSERT_FALSE(context.getCompilationUnit().getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(TypeCheckerFnDecl_InvalidParamType) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    const char* source = "fn sub(a: NotARealType, b: i32) -> i32 { return a - b; }";
    ParserTestContext context(source, arena, interner);

    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    ASSERT_TRUE(root != NULL);

    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());
    // Optionally, check for the specific error
    // ErrorReport err = context.unit.getErrorHandler().getErrors()[0];
    // ASSERT_EQ(ERR_UNDECLARED_TYPE, err.code);

    return true;
}
