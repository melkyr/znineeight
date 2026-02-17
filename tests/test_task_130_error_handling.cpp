#include "test_framework.hpp"
#include "test_utils.hpp"
#include "double_free_analyzer.hpp"
#include "type_checker.hpp"

TEST_FUNC(DoubleFree_TryPathAware) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn mightFail() -> i32 {}\n"
        "fn my_func(x: i32) -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    try mightFail();\n"
        "    // After try, p should be AS_UNKNOWN\n"
        "    arena_free(p); // Should NOT be a definite double free error\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    ctx.getCompilationUnit().injectRuntimeSymbols();
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    // We skip TypeChecker because our bootstrap TypeChecker doesn't support error unions yet
    // and C89FeatureValidator would reject 'try'.
    // But DoubleFreeAnalyzer can still analyze the AST.

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool has_double_free = false;
    const DynamicArray<ErrorReport>& errors = ctx.getCompilationUnit().getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_DOUBLE_FREE) {
            has_double_free = true;
            break;
        }
    }
    ASSERT_FALSE(has_double_free);

    return true;
}

TEST_FUNC(DoubleFree_CatchPathAware) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn mightFail() -> i32 {}\n"
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    // Use a simple expression for catch body\n"
        "    mightFail() catch arena_free(p);\n"
        "    // On success path, p is still AS_ALLOCATED\n"
        "    // On failure path, p is AS_FREED\n"
        "    // Merged state should be AS_UNKNOWN\n"
        "    arena_free(p); // Should NOT be a definite double free error\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    ctx.getCompilationUnit().injectRuntimeSymbols();
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool has_double_free = false;
    const DynamicArray<ErrorReport>& errors = ctx.getCompilationUnit().getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_DOUBLE_FREE) {
            has_double_free = true;
            break;
        }
    }
    ASSERT_FALSE(has_double_free);

    return true;
}

TEST_FUNC(DoubleFree_OrelsePathAware) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn maybeAlloc() -> *u8 { return null; }\n"
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    // Use a simple expression for orelse body\n"
        "    var q: *u8 = maybeAlloc() orelse arena_alloc_default(10u);\n"
        "    // In both paths p is still AS_ALLOCATED\n"
        "    arena_free(p);\n"
        "    arena_free(q);\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    ctx.getCompilationUnit().injectRuntimeSymbols();
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool has_double_free = false;
    const DynamicArray<ErrorReport>& errors = ctx.getCompilationUnit().getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_DOUBLE_FREE) {
            has_double_free = true;
            break;
        }
    }
    ASSERT_FALSE(has_double_free);

    return true;
}
