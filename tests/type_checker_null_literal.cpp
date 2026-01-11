#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"

TEST_FUNC(TypeChecker_NullLiteral_ValidAssignment) {
    const char* source =
        "fn test_fn() {\n"
        "    var p: *i32 = null;\n"
        "}\n";

    ArenaAllocator arena(1024 * 4);
    StringInterner interner(arena);
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();

    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    ASSERT_FALSE(context.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeChecker_NullLiteral_InvalidAssignment) {
    const char* source =
        "fn test_fn() {\n"
        "    var x: i32 = null;\n"
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
    ASSERT_EQ(errors[0].code, ERR_TYPE_MISMATCH);

    return true;
}
