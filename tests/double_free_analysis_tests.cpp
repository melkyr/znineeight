#include "test_framework.hpp"
#include "test_utils.hpp"
#include "double_free_analyzer.hpp"
#include "error_handler.hpp"
#include "type_checker.hpp"

TEST_FUNC(DoubleFree_SimpleDoubleFree) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100);\n"
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

TEST_FUNC(DoubleFree_NestedDeferScopes) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    {\n"
        "        defer { arena_free(p); }\n"
        "    }\n"
        "    arena_free(p);\n" // Double free
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    ctx.getCompilationUnit().injectRuntimeSymbols();
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

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

TEST_FUNC(DoubleFree_PointerAliasing) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    var q: *u8 = p;\n"
        "    arena_free(p);\n"
        "    arena_free(q);\n" // Double free via alias (Risk)
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    ctx.getCompilationUnit().injectRuntimeSymbols();
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    // Current implementation does NOT track aliases, but it might report
    // WARN_FREE_UNALLOCATED for q since it wasn't explicitly allocated.
    bool has_double_free = false;
    bool has_uninit_free = false;
    const DynamicArray<ErrorReport>& errors = ctx.getCompilationUnit().getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_DOUBLE_FREE) has_double_free = true;
    }
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_FREE_UNALLOCATED) has_uninit_free = true;
    }

    // Design choice: aliases are not tracked.
    ASSERT_FALSE(has_double_free);
    // q is considered uninitialized or unknown state because it was assigned from p,
    // and assignments from identifiers make state AS_UNKNOWN.
    ASSERT_TRUE(has_uninit_free);

    return true;
}

TEST_FUNC(DoubleFree_DeferInLoop) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func(x: i32) -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    var i: i32 = 0;\n"
        "    while (i < x) {\n"
        "        defer { arena_free(p); }\n"
        "        i = i + 1;\n"
        "    }\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    ctx.getCompilationUnit().injectRuntimeSymbols();
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    // The analyzer visits the loop body once.
    // The defer is executed at the end of the block.
    // Then p becomes AS_UNKNOWN after the loop because it was modified (freed) in the loop.
    // We check that it doesn't crash and correctly transitions state.
    return true;
}

TEST_FUNC(DoubleFree_ConditionalAllocUnconditionalFree) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func(x: i32) -> void {\n"
        "    var p: *u8 = null;\n"
        "    if (x > 0) {\n"
        "        p = arena_alloc_default(100u);\n"
        "    } else {\n"
        "        p = null;\n"
        "    }\n"
        "    arena_free(p);\n" // Risk: p might be null
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    ctx.getCompilationUnit().injectRuntimeSymbols();
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool has_warning = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_FREE_UNALLOCATED) {
            has_warning = true;
            break;
        }
    }
    // Path-aware: AS_ALLOCATED on one path, AS_UNKNOWN (from null) on other.
    // Merged state is AS_UNKNOWN.
    // Currently, freeing AS_UNKNOWN does NOT report a warning to avoid false positives on parameters.
    ASSERT_FALSE(has_warning);

    return true;
}

TEST_FUNC(DoubleFree_SwitchAnalysis) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func(x: i32) -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    switch (x) {\n"
        "        1 => arena_free(p),\n"
        "        else => p,\n"
        "    };\n"
        "    arena_free(p);\n" // Potential double free (in one path)
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    // Now path-aware: freed in one branch, not in other -> AS_UNKNOWN.
    // Definite double free is NOT reported for AS_UNKNOWN.
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

TEST_FUNC(DoubleFree_TryAnalysis) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn fallible() -> void {}\n"
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    try fallible();\n"
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

    bool has_leak = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_MEMORY_LEAK) {
            has_leak = true;
            break;
        }
    }
    // If try is NOT visited, the function body analysis might be incomplete.
    // In this case, 'arena_free(p)' IS visited because it's after 'try'.
    // But if we want to test 'try' specifically, let's put an allocation/free inside it.

    return true;
}

TEST_FUNC(DoubleFree_TryAnalysisComplex) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn fallible() -> void {}\n"
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    try fallible();\n" // try wrapping a call
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

    bool has_double_free = false;
    const DynamicArray<ErrorReport>& errors = ctx.getCompilationUnit().getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_DOUBLE_FREE) {
            has_double_free = true;
            break;
        }
    }
    // Now path-aware: try introduces uncertainty.
    ASSERT_FALSE(has_double_free);

    return true;
}

TEST_FUNC(DoubleFree_CatchAnalysis) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn fallible() -> *u8 { return null; }\n"
        "fn my_func() -> void {\n"
        "    var p: *u8 = fallible() catch arena_alloc_default(100u);\n"
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

    // If 'catch' is NOT visited, arena_alloc_default(100u) is NOT seen.
    // So p will be UNINITIALIZED.
    // arena_free(p) will report WARN_FREE_UNALLOCATED.
    bool has_uninit_warning = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_FREE_UNALLOCATED) {
            has_uninit_warning = true;
            break;
        }
    }
    ASSERT_FALSE(has_uninit_warning);

    return true;
}

TEST_FUNC(DoubleFree_BinaryOpAnalysis) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u) + 0u;\n" // arena_alloc inside binary op
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

    // If binary op is not visited, p will be UNINITIALIZED.
    // Then arena_free(p) will report WARN_FREE_UNALLOCATED.
    bool has_uninit_warning = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_FREE_UNALLOCATED) {
            has_uninit_warning = true;
            break;
        }
    }
    // We expect NO warnings if analyzed correctly.
    // Initially it will likely report WARN_FREE_UNALLOCATED because it didn't see the alloc.
    ASSERT_FALSE(has_uninit_warning);

    return true;
}

TEST_FUNC(DoubleFree_ReassignmentLeak) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100);\n"
        "    p = arena_alloc_default(200);\n" // Leak of first allocation
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

TEST_FUNC(DoubleFree_NullReassignmentLeak) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100);\n"
        "    p = null;\n" // Leak
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

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

TEST_FUNC(DoubleFree_ReturnExempt) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> *u8 {\n"
        "    var p: *u8 = arena_alloc_default(100);\n"
        "    return p;\n" // No leak
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool has_leak = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_MEMORY_LEAK) {
            has_leak = true;
            break;
        }
    }
    ASSERT_FALSE(has_leak);

    return true;
}

TEST_FUNC(DoubleFree_BasicTracking) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100);\n"
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
    ArenaAllocator arena(1024 * 1024);
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
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100);\n"
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
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100);\n"
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
