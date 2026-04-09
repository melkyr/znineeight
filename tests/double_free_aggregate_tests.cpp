#include "test_framework.hpp"
#include "test_utils.hpp"
#include "double_free_analyzer.hpp"
#include "type_checker.hpp"

TEST_FUNC(DoubleFree_StructFieldTracking) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "const S = struct { ptr: *u8 };\n"
        "fn my_func() -> void {\n"
        "    var s: S = undefined;\n"
        "    s.ptr = arena_alloc_default(100u);\n"
        "    arena_free(s.ptr);\n"
        "    arena_free(s.ptr);\n" // Double free of field
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

TEST_FUNC(DoubleFree_StructFieldLeak) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "const S = struct { ptr: *u8 };\n"
        "fn my_func() -> void {\n"
        "    var s: S = undefined;\n"
        "    s.ptr = arena_alloc_default(100u);\n"
        "}\n"; // Leak of s.ptr

    ParserTestContext ctx(source, arena, interner);
    ctx.getCompilationUnit().injectRuntimeSymbols();
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

TEST_FUNC(DoubleFree_ArrayCollapseTracking) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var arr: [2]*u8 = undefined;\n"
        "    arr[0] = arena_alloc_default(100u);\n"
        "    arena_free(arr[0]);\n"
        "    arena_free(arr[1]);\n" // Double free due to collapse to "arr[]"
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

TEST_FUNC(DoubleFree_ErrorUnionAllocation) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn alloc() -> !*u8 { return error.Fail; }\n"
        "fn my_func() -> void {\n"
        "    var p: *u8 = alloc() catch return;\n"
        "    // p is now tracked as AS_ALLOCATED because alloc() returns !*u8\n"
        "    arena_free(p);\n"
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

TEST_FUNC(DoubleFree_LoopMergingPreservesUnmodified) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    // q is NOT modified in loop, so it should stay AS_ALLOCATED.
    // If it stays AS_ALLOCATED, it should report a LEAK at end of scope.
    const char* source =
        "fn my_func(cond: bool) -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    var q: *u8 = arena_alloc_default(100u);\n"
        "    while (cond) {\n"
        "        arena_free(p);\n"
        "    }\n"
        "    arena_free(p); // Should be a double free risk\n"
        "}\n"; // q leaked here

    ParserTestContext ctx(source, arena, interner);
    ctx.getCompilationUnit().injectRuntimeSymbols();
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool q_leaked = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_MEMORY_LEAK) {
            // Check if 'q' is in the message
            const char* msg = warnings[i].message;
            if (msg) {
                bool found_q = false;
                for (size_t j = 0; msg[j]; ++j) {
                    if (msg[j] == 'q' && (j == 0 || msg[j-1] == ' ' || msg[j-1] == '\'') && (msg[j+1] == '\0' || msg[j+1] == ' ' || msg[j+1] == '\'')) {
                        found_q = true;
                        break;
                    }
                }
                if (found_q) q_leaked = true;
            }
        }
    }
    ASSERT_TRUE(q_leaked);

    return true;
}
