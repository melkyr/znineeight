#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"

TEST_FUNC(TypeChecker_ConstAssignment) {
    const char* source =
        "fn test_fn() {\n"
        "    const x: i32 = 10;\n"
        "    x = 20;\n"
        "}\n";

    ArenaAllocator arena(1024 * 4);
    StringInterner interner(arena);
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();

    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());
    const DynamicArray<ErrorReport>& errors = context.getCompilationUnit().getErrorHandler().getErrors();
    ASSERT_EQ(errors.length(), 1);
    ASSERT_EQ(errors[0].code, ERR_CANNOT_ASSIGN_TO_CONST);

    return true;
}

TEST_FUNC(TypeChecker_ConstAssignmentUndeclared) {
    const char* source =
        "fn test_fn() {\n"
        "    y = 20;\n"
        "}\n";

    ArenaAllocator arena(1024 * 4);
    StringInterner interner(arena);
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();

    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());
    const DynamicArray<ErrorReport>& errors = context.getCompilationUnit().getErrorHandler().getErrors();
    ASSERT_EQ(errors.length(), 1);
    ASSERT_EQ(errors[0].code, ERR_UNDEFINED_VARIABLE);

    return true;
}
