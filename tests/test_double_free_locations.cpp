#include "test_framework.hpp"
#include "test_utils.hpp"
#include "double_free_analyzer.hpp"
#include "error_handler.hpp"
#include "type_checker.hpp"
#include "utils.hpp"

// Helper to check if a string contains a substring
static bool contains(const char* haystack, const char* needle) {
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

TEST_FUNC(DoubleFree_LocationInLeakWarning) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n" // Line 2
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool found_leak_with_loc = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_MEMORY_LEAK) {
            // Check if message contains allocation info.
            // We expect something like "(allocated at test.zig:2:18)"
            if (contains(warnings[i].message, "allocated at") &&
                contains(warnings[i].message, ":2:")) {
                found_leak_with_loc = true;
            }
        }
    }

    // This is expected to FAIL until we implement tracking
    ASSERT_TRUE(found_leak_with_loc);

    return true;
}

TEST_FUNC(DoubleFree_LocationInReassignmentLeak) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n" // Line 2
        "    p = arena_alloc_default(200u);\n"         // Line 3
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

    bool found_leak_with_loc = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_MEMORY_LEAK) {
            if (contains(warnings[i].message, "reassigning") &&
                contains(warnings[i].message, "allocated at") &&
                contains(warnings[i].message, ":2:")) {
                found_leak_with_loc = true;
            }
        }
    }

    ASSERT_TRUE(found_leak_with_loc);

    return true;
}

TEST_FUNC(DoubleFree_LocationInDoubleFreeError) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn my_func() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n" // Line 2
        "    arena_free(p);\n"                  // Line 3
        "    arena_free(p);\n"                  // Line 4
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool found_double_free_with_loc = false;
    const DynamicArray<ErrorReport>& errors = ctx.getCompilationUnit().getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_DOUBLE_FREE) {
            // Check if message contains allocation AND first free info.
            if (contains(errors[i].message, "allocated at") &&
                contains(errors[i].message, ":2:") &&
                contains(errors[i].message, "first freed at") &&
                contains(errors[i].message, ":3:")) {
                found_double_free_with_loc = true;
            }
        }
    }

    // This is expected to FAIL until we implement tracking
    ASSERT_TRUE(found_double_free_with_loc);

    return true;
}
