#include "test_framework.hpp"
#include "test_utils.hpp"
#include "double_free_analyzer.hpp"
#include "type_checker.hpp"

TEST_FUNC(DoubleFree_SwitchPathAware) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func(x: i32) -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    switch (x) {\n"
        "        1 => arena_free(p),\n"
        "        else => {}\n"
        "    };\n"
        "    // After switch, p should be AS_UNKNOWN\n"
        "    arena_free(p); // Should NOT be a definite double free error\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    ctx.getCompilationUnit().injectRuntimeSymbols();
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);
    ASSERT_FALSE(ctx.getCompilationUnit().getErrorHandler().hasErrors());

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

TEST_FUNC(DoubleFree_SwitchBothFree) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func(x: i32) -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    switch (x) {\n"
        "        1 => arena_free(p),\n"
        "        else => arena_free(p)\n"
        "    };\n"
        "    // After switch, p should be AS_FREED\n"
        "    arena_free(p); // Should be a double free error\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    ctx.getCompilationUnit().injectRuntimeSymbols();
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);
    ASSERT_FALSE(ctx.getCompilationUnit().getErrorHandler().hasErrors());

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
