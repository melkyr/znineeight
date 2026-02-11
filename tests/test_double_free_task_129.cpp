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
    ArenaAllocator arena(131072);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn arena_alloc(size: usize) -> *void { return null; }\n"
        "fn unknown_func(p: *u8) -> void {}\n"
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc(100u);\n"
        "    unknown_func(p);\n" // Ownership transferred
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
    ArenaAllocator arena(131072);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn arena_alloc(size: usize) -> *void { return null; }\n"
        "fn arena_free(p: *void) -> void {}\n"
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc(100u);\n"
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
            // Message should contain "via defer at" and the location of the FIRST free (line 6)
            if (contains_substring(errors[i].message, "via defer at") &&
                contains_substring(errors[i].message, ":6:")) {
                found_double_free_with_defer = true;
            }
        }
    }

    ASSERT_TRUE(found_double_free_with_defer);

    return true;
}

TEST_FUNC(DoubleFree_ErrdeferContextInError) {
    ArenaAllocator arena(131072);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn arena_alloc(size: usize) -> *void { return null; }\n"
        "fn arena_free(p: *void) -> void {}\n"
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc(100u);\n"   // Line 4
        "    errdefer { arena_free(p); }\n"      // Line 5 (executes 2nd)
        "    errdefer { arena_free(p); }\n"      // Line 6 (executes 1st)
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
            // Message should contain "via errdefer at" and the location of the FIRST free (line 6)
            if (contains_substring(errors[i].message, "via errdefer at") &&
                contains_substring(errors[i].message, ":6:")) {
                found_double_free_with_errdefer = true;
            }
        }
    }

    ASSERT_TRUE(found_double_free_with_errdefer);

    return true;
}
