#include "test_framework.hpp"
#include "test_utils.hpp"
#include "ast.hpp"
#include "parser.hpp"
#include "type_checker.hpp"

// Forward declarations for test functions
TEST_FUNC(TypeCheckerC89Compat_FloatWidening_Fails);

TEST_FUNC(TypeCheckerC89Compat_FloatWidening_Fails) {
    // Test case 1: Widening from f32 to f64 should be rejected under strict C89 rules.
    {
        ArenaAllocator arena(262144);
        StringInterner interner(arena);
        const char* source =
            "fn test_fn(x: f32) -> void {\n"
            "    var y: f64 = x;\n"
            "}\n";
        ParserTestContext ctx(source, arena, interner);
        TypeChecker type_checker(ctx.getCompilationUnit());
        ASTNode* root = ctx.getParser()->parse();
        type_checker.check(root);
        ErrorHandler& eh = ctx.getCompilationUnit().getErrorHandler();
        ASSERT_TRUE(eh.hasErrors());
        const DynamicArray<ErrorReport>& errors = eh.getErrors();
        ASSERT_EQ(errors.length(), 1);
        ASSERT_STREQ(errors[0].message, "type mismatch");
        ASSERT_TRUE(errors[0].hint != NULL && strstr(errors[0].hint, "C89 assignment requires identical types: 'f32' to 'f64'") != NULL);
    }

    // Test case 2: Unsafe narrowing from f64 to f32 should be rejected.
    {
        ArenaAllocator arena(262144);
        StringInterner interner(arena);
        const char* source =
            "fn test_fn(x: f64) -> void {\n"
            "    var y: f32 = x;\n"
            "}\n";
        ParserTestContext ctx(source, arena, interner);
        TypeChecker type_checker(ctx.getCompilationUnit());
        ASTNode* root = ctx.getParser()->parse();
        type_checker.check(root);
        ErrorHandler& eh = ctx.getCompilationUnit().getErrorHandler();
        ASSERT_TRUE(eh.hasErrors());
        const DynamicArray<ErrorReport>& errors = eh.getErrors();
        ASSERT_EQ(errors.length(), 1);
        ASSERT_STREQ(errors[0].message, "type mismatch");
        ASSERT_TRUE(errors[0].hint != NULL && strstr(errors[0].hint, "C89 assignment requires identical types: 'f64' to 'f32'") != NULL);
    }

    return true;
}
