#include "test_framework.hpp"
#include "test_utils.hpp"
#include "double_free_analyzer.hpp"
#include "error_handler.hpp"
#include "type_checker.hpp"

TEST_FUNC(DoubleFree_SimpleDoubleFree) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc(100);\n"
        "    arena_free(p);\n"
        "    arena_free(p);\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    // Expected to FAIL in Phase 1 as no errors are reported yet
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

TEST_FUNC(DoubleFree_BasicTracking) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc(100);\n"
        "    arena_free(p);\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    // This should PASS even in Phase 1 because no errors should be reported
    // We check specifically for ERR_DOUBLE_FREE and WARN_FREE_UNALLOCATED
    bool has_relevant_diagnostics = false;
    const DynamicArray<ErrorReport>& errors = ctx.getCompilationUnit().getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_DOUBLE_FREE) {
            has_relevant_diagnostics = true;
            break;
        }
    }
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_FREE_UNALLOCATED) {
            has_relevant_diagnostics = true;
            break;
        }
    }
    ASSERT_FALSE(has_relevant_diagnostics);

    return true;
}

TEST_FUNC(DoubleFree_UninitializedFree) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8;\n"
        "    arena_free(p);\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    // Expected to FAIL in Phase 1
    bool has_warning = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_FREE_UNALLOCATED) {
            has_warning = true;
            break;
        }
    }
    ASSERT_TRUE(has_warning);

    return true;
}

TEST_FUNC(DoubleFree_MemoryLeak) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc(100);\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    // Expected to FAIL in Phase 1
    bool has_leak = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_MEMORY_LEAK) {
            has_leak = true;
            break;
        }
    }
    ASSERT_TRUE(has_leak);

    return true;
}

TEST_FUNC(DoubleFree_DeferDoubleFree) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc(100);\n"
        "    defer { arena_free(p); }\n"
        "    arena_free(p);\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    // Expected to FAIL in Phase 1
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
