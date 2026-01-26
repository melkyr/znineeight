#include "test_framework.hpp"
#include "test_utils.hpp"
#include "double_free_analyzer.hpp"
#include "error_handler.hpp"
#include "type_checker.hpp"

TEST_FUNC(DoubleFree_MultipleDefers) {
    ArenaAllocator arena(131072);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc(100u);\n"
        "    defer { arena_free(p); }\n"
        "    defer { arena_free(p); }\n" // Double free via defers
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

TEST_FUNC(DoubleFree_TransferThenFree) {
    ArenaAllocator arena(131072);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn transfer(p: *u8) void {}\n"
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc(100u);\n"
        "    transfer(p);\n" // Ownership transferred
        "    arena_free(p);\n" // Should NOT report double free (conservative)
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
    ASSERT_FALSE(has_double_free);

    return true;
}

TEST_FUNC(DoubleFree_DeferInLoop) {
    ArenaAllocator arena(131072);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func(cond: bool) -> void {\n"
        "    var p: *u8 = arena_alloc(100u);\n"
        "    while (cond) {\n"
        "        defer { arena_free(p); }\n"
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

    // In this conservative model, p becomes AS_UNKNOWN because it's modified in the loop
    // (well, the analyzer conservatively treats any variable in a loop as unknown if modified,
    // but here it's not even modified in the traditional sense, but defers are weird).
    // Actually, DoubleFreeAnalyzer::visitWhileStmt marks all variables modified in loop as AS_UNKNOWN.
    // Here, p is used in a defer.

    // We just verify that it doesn't crash and no error is reported (as it is unknown).
    ASSERT_FALSE(ctx.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(DoubleFree_PointerAliasing) {
    ArenaAllocator arena(131072);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc(100u);\n"
        "    var q: *u8 = p;\n"
        "    arena_free(p);\n"
        "    arena_free(q);\n" // Double free via alias
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
    ASSERT_FALSE(has_double_free);

    return true;
}

TEST_FUNC(DoubleFree_ConditionalAllocUnconditionalFree) {
    ArenaAllocator arena(131072);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func(cond: bool) -> void {\n"
        "    var p: *u8 = null;\n"
        "    if (cond) {\n"
        "        p = arena_alloc(100u);\n"
        "    }\n"
        "    arena_free(p);\n" // Potential uninitialized free if !cond
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

    bool has_uninit_free = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_FREE_UNALLOCATED) {
            has_uninit_free = true;
            break;
        }
    }
    ASSERT_FALSE(has_uninit_free);

    return true;
}
