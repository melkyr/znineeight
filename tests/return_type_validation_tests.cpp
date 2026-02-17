#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"

TEST_FUNC(ReturnTypeValidation_Valid) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    const char* source = "fn test_fn() -> i32 { return 10; }";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);
    ASSERT_FALSE(context.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(ReturnTypeValidation_Invalid) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    const char* source = "fn test_fn() -> i32 { return true; }";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);
    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}
