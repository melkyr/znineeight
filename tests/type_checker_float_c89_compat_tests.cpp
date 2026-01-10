#include "test_framework.hpp"
#include "test_utils.hpp"
#include "ast.hpp"
#include "parser.hpp"
#include "type_checker.hpp"

// Forward declarations for test functions
TEST_FUNC(TypeCheckerC89Compat_FloatWidening);

TEST_FUNC(TypeCheckerC89Compat_FloatWidening) {
    // Test case 1: Safe widening from f32 to f64 should be allowed.
    // We use a function context to get a variable of type f32, since float
    // literals are always inferred as f64.
    {
        ArenaAllocator arena(16384);
        StringInterner interner(arena);
        const char* source =
            "fn test_fn(x: f32) -> void {\n"
            "    var y: f64 = x;\n"
            "}\n";
        ParserTestContext ctx(source, arena, interner);
        TypeChecker type_checker(ctx.getCompilationUnit());
        ASTNode* root = ctx.getParser()->parse();
        type_checker.check(root);
        ASSERT_FALSE(ctx.getCompilationUnit().getErrorHandler().hasErrors());
    }

    // Test case 2: Unsafe narrowing from f64 to f32 should be rejected.
    {
        ArenaAllocator arena(16384);
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
        ASSERT_TRUE(strcmp(errors[0].message, "cannot assign type 'f64' to variable of type 'f32'") == 0);
    }

    return true;
}
