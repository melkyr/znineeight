#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"

TEST_FUNC(TypeChecker_VarDecl_Inferred_Crash) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    // Inferred type inside a function to ensure it's not global
    const char* source = "fn myTest() void { var x = 42; }";
    ParserTestContext ctx(source, arena, interner);
    TypeChecker type_checker(ctx.getCompilationUnit());

    ASTNode* root = ctx.getParser()->parse();
    ASSERT_TRUE(root != NULL);

    // This is expected to crash if node->type->loc is accessed without a NULL check
    type_checker.check(root);

    ASSERT_FALSE(ctx.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeChecker_VarDecl_Inferred_Loop) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    const char* source = "fn myTest() void { var i = 0; while (i < 10) { i = i + 1; } }";
    ParserTestContext ctx(source, arena, interner);
    TypeChecker type_checker(ctx.getCompilationUnit());

    ASTNode* root = ctx.getParser()->parse();
    ASSERT_TRUE(root != NULL);
    type_checker.check(root);
    ASSERT_FALSE(ctx.getCompilationUnit().getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(TypeChecker_VarDecl_Inferred_Multiple) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    const char* source = "fn myTest() void { var x = 1; var y = 2.0; var z = true; }";
    ParserTestContext ctx(source, arena, interner);
    TypeChecker type_checker(ctx.getCompilationUnit());

    ASTNode* root = ctx.getParser()->parse();
    ASSERT_TRUE(root != NULL);
    type_checker.check(root);
    ASSERT_FALSE(ctx.getCompilationUnit().getErrorHandler().hasErrors());
    return true;
}
