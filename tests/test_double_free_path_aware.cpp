#include "test_framework.hpp"
#include "test_utils.hpp"
#include "double_free_analyzer.hpp"
#include "error_handler.hpp"
#include "type_checker.hpp"

TEST_FUNC(DoubleFree_IfElseBranching) {
    ArenaAllocator arena(131072);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func(x: i32) -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    if (x > 0) {\n"
        "        arena_free(p);\n"
        "    } else {\n"
        "        // p NOT freed\n"
        "    }\n"
        "    // After if/else, p should be AS_UNKNOWN\n"
        "    arena_free(p);\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    ctx.getCompilationUnit().injectRuntimeSymbols();
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);
    if (ctx.getCompilationUnit().getErrorHandler().hasErrors()) {
        ctx.getCompilationUnit().getErrorHandler().printErrors();
        return false;
    }

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

    // Path-aware analysis should avoid a definite double free error when it's only possible on one path.
    // AS_UNKNOWN state currently does not report an error on free.
    ASSERT_FALSE(has_double_free);

    return true;
}

TEST_FUNC(DoubleFree_IfElseBothFree) {
    ArenaAllocator arena(131072);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func(x: i32) -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    if (x > 0) {\n"
        "        arena_free(p);\n"
        "    } else {\n"
        "        arena_free(p);\n"
        "    }\n"
        "    // After if/else, p should be AS_FREED\n"
        "    arena_free(p);\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    ctx.getCompilationUnit().injectRuntimeSymbols();
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);
    if (ctx.getCompilationUnit().getErrorHandler().hasErrors()) {
        ctx.getCompilationUnit().getErrorHandler().printErrors();
        return false;
    }

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
    ASSERT_TRUE(has_double_free);

    return true;
}

TEST_FUNC(DoubleFree_WhileConservative) {
    ArenaAllocator arena(131072);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func(x: i32) -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    while (x > 0) {\n"
        "        arena_free(p);\n"
        "        p = arena_alloc_default(200u);\n"
        "    }\n"
        "    // p is AS_UNKNOWN here\n"
        "    arena_free(p);\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    ctx.getCompilationUnit().injectRuntimeSymbols();
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);
    if (ctx.getCompilationUnit().getErrorHandler().hasErrors()) {
        ctx.getCompilationUnit().getErrorHandler().printErrors();
        return false;
    }

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
    // Should NOT have double free because it's AS_UNKNOWN
    ASSERT_FALSE(has_double_free);

    return true;
}
