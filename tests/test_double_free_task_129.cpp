#include "test_framework.hpp"
#include "test_utils.hpp"
#include "double_free_analyzer.hpp"
#include "error_handler.hpp"
#include "type_checker.hpp"
#include "utils.hpp"

// Helper to check if a string contains a substring
static bool contains_substring(const char* haystack, const char* needle) {
    if (!haystack || !needle) return false;
    size_t h_len = 0;
    while (haystack[h_len]) h_len++;
    size_t n_len = 0;
    while (needle[n_len]) n_len++;

    if (n_len > h_len) return false;

    for (size_t i = 0; i <= h_len - n_len; ++i) {
        bool match = true;
        for (size_t j = 0; j < n_len; ++j) {
            if (haystack[i + j] != needle[j]) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

TEST_FUNC(DoubleFree_TransferTracking) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn arena_alloc_default(size: usize) -> *void { return null; }\n"
        "fn arena_create(addr: usize) -> *void { return null; }\n"
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    arena_create(@ptrToInt(p));\n" // @ptrToInt is a read, not a transfer
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    // Should HAVE a leak warning (6005) and NO transfer warning (6007)
    bool has_leak = false;
    bool has_transfer_warning = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_MEMORY_LEAK) {
            has_leak = true;
        }
        if (warnings[i].code == WARN_TRANSFERRED_MEMORY) {
            has_transfer_warning = true;
        }
    }
    ASSERT_TRUE(has_leak);
    ASSERT_FALSE(has_transfer_warning);

    return true;
}

TEST_FUNC(DoubleFree_DirectPointerTransfer) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn arena_alloc_default(size: usize) -> *void { return null; }\n"
        "fn arena_create(p: *u8) -> *void { return null; }\n"
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    arena_create(p);\n" // direct pointer -> transfer occurs
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    // Should NOT have a leak warning (6005) but SHOULD have a transfer warning (6007)
    bool has_leak = false;
    bool has_transfer_warning = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_MEMORY_LEAK) {
            has_leak = true;
        }
        if (warnings[i].code == WARN_TRANSFERRED_MEMORY) {
            has_transfer_warning = true;
        }
    }
    ASSERT_FALSE(has_leak);
    ASSERT_TRUE(has_transfer_warning);

    return true;
}

TEST_FUNC(DoubleFree_DeferContextInError) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn arena_alloc_default(size: usize) -> *void { return null; }\n"
        "fn arena_free(p: *void) -> void {}\n"
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    defer { arena_free(p); }\n"         // Line 5 (executes 2nd)
        "    defer { arena_free(p); }\n"         // Line 6 (executes 1st)
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool found_double_free_with_defer = false;
    const DynamicArray<ErrorReport>& errors = ctx.getCompilationUnit().getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_DOUBLE_FREE) {
            // Check in hint
            if (errors[i].hint &&
                contains_substring(errors[i].hint, "via defer at") &&
                contains_substring(errors[i].hint, ":6:")) {
                found_double_free_with_defer = true;
            }
        }
    }

    ASSERT_TRUE(found_double_free_with_defer);

    return true;
}

TEST_FUNC(DoubleFree_ErrdeferContextInError) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn arena_alloc_default(size: usize) -> *void { return null; }\n"
        "fn arena_free(p: *void) -> void {}\n"
        "const MyErrorSet = error { MyError };\n"
        "fn my_func() -> !void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"   // Line 5
        "    errdefer { arena_free(p); }\n"      // Line 6 (executes 2nd)
        "    errdefer { arena_free(p); }\n"      // Line 7 (executes 1st)
        "    return MyErrorSet.MyError;\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool found_double_free_with_errdefer = false;
    const DynamicArray<ErrorReport>& errors = ctx.getCompilationUnit().getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_DOUBLE_FREE) {
            // Check in hint
            if (errors[i].hint &&
                contains_substring(errors[i].hint, "via errdefer at") &&
                contains_substring(errors[i].hint, ":7:")) {
                found_double_free_with_errdefer = true;
            }
        }
    }

    ASSERT_TRUE(found_double_free_with_errdefer);

    return true;
}

TEST_FUNC(DoubleFree_TransferDiagnostics) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn arena_alloc_default(size: usize) -> *void { return null; }\n"
        "fn my_func() -> void {\n"
        "    var a: *u8 = arena_alloc_default(100u);\n"
        "    var b = a;\n"
        "}\n"; // b leaks, transferred from a

    ParserTestContext ctx(source, arena, interner);
    ctx.getCompilationUnit().getOptions().warn_arena_leaks = true;

    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool found_transfer_msg = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_MEMORY_LEAK) {
            if (warnings[i].message &&
                contains_substring(warnings[i].message, "originally held by 'a'") &&
                contains_substring(warnings[i].message, "transferred at")) {
                found_transfer_msg = true;
            }
        }
    }
    ASSERT_TRUE(found_transfer_msg);

    return true;
}
