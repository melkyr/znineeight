#include "test_framework.hpp"
#include "test_utils.hpp"
#include "parser.hpp"
#include "type_checker.hpp"
#include "lifetime_analyzer.hpp"
#include "null_pointer_analyzer.hpp"
#include "double_free_analyzer.hpp"
#include "type_system.hpp"
#include "symbol_table.hpp"

TEST_FUNC(Integration_FullPipeline) {
    ArenaAllocator arena(262144); // 128KB
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn main() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    arena_free(p);\n"
        "    arena_free(p);  // Double free\n"
        "    var q: *i32 = null;\n"
        "    q.* = 10;       // Null dereference\n"
        "}\n"
        "fn leak_test() -> *i32 {\n"
        "    var x: i32 = 42;\n"
        "    return &x;      // Lifetime violation\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    CompilationUnit& unit = ctx.getCompilationUnit();

    unit.injectRuntimeSymbols();

    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(unit);
    type_checker.check(ast);

    // Run all analyzers
    LifetimeAnalyzer lifetime_analyzer(unit);
    lifetime_analyzer.analyze(ast);

    NullPointerAnalyzer null_analyzer(unit);
    null_analyzer.analyze(ast);

    DoubleFreeAnalyzer double_free_analyzer(unit);
    double_free_analyzer.analyze(ast);

    // Verify errors
    bool has_double_free = false;
    bool has_null_deref = false;
    bool has_lifetime_violation = false;

    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_DOUBLE_FREE) has_double_free = true;
        if (errors[i].code == ERR_NULL_POINTER_DEREFERENCE) has_null_deref = true;
        if (errors[i].code == ERR_LIFETIME_VIOLATION) has_lifetime_violation = true;
    }

    ASSERT_TRUE(has_double_free);
    ASSERT_TRUE(has_null_deref);
    ASSERT_TRUE(has_lifetime_violation);

    return true;
}

TEST_FUNC(Integration_CorrectUsage) {
    ArenaAllocator arena(262144); // 128KB
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn main() -> void {\n"
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    arena_free(p);  // Correct usage\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    CompilationUnit& unit = ctx.getCompilationUnit();

    unit.injectRuntimeSymbols();

    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(unit);
    type_checker.check(ast);

    // Run all analyzers
    LifetimeAnalyzer lifetime_analyzer(unit);
    lifetime_analyzer.analyze(ast);

    NullPointerAnalyzer null_analyzer(unit);
    null_analyzer.analyze(ast);

    DoubleFreeAnalyzer double_free_analyzer(unit);
    double_free_analyzer.analyze(ast);

    // Verify no errors
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    ASSERT_FALSE(unit.getErrorHandler().hasWarnings());

    return true;
}
