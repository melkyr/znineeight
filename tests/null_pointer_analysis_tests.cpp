#include "test_framework.hpp"
#include "null_pointer_analyzer.hpp"
#include "type_checker.hpp"
#include "test_utils.hpp"
#include <new>

TEST_FUNC(NullPointerAnalyzer_BasicTracking) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {\n"
        "    var x: i32 = 0;\n"
        "    var p: *i32 = &x;\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);
    ASSERT_TRUE(!ctx.getCompilationUnit().getErrorHandler().hasErrors());

    NullPointerAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    ASSERT_TRUE(!ctx.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(NullPointerAnalyzer_DefiniteNullDeref) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {\n"
        "    var p: *i32 = null;\n"
        "    var x: i32 = p.*;\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    NullPointerAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    ASSERT_TRUE(ctx.getCompilationUnit().getErrorHandler().hasErrors());
    bool found_error = false;
    const DynamicArray<ErrorReport>& errors = ctx.getCompilationUnit().getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_NULL_POINTER_DEREFERENCE) {
            found_error = true;
            break;
        }
    }
    ASSERT_TRUE(found_error);

    return true;
}

TEST_FUNC(NullPointerAnalyzer_UninitPointer) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {\n"
        "    var p: *i32;\n"
        "    var x: i32 = p.*;\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    NullPointerAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    ASSERT_TRUE(ctx.getCompilationUnit().getErrorHandler().hasWarnings());
    bool found_warning = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_UNINITIALIZED_POINTER) {
            found_warning = true;
            break;
        }
    }
    ASSERT_TRUE(found_warning);

    return true;
}

TEST_FUNC(NullPointerAnalyzer_PotentialNullDeref) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    // Function calls are currently conservative and return PS_MAYBE
    const char* source =
        "fn bar() *i32 { return null; }\n"
        "fn foo() void {\n"
        "    var p: *i32 = bar();\n"
        "    var x: i32 = p.*;\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    NullPointerAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    ASSERT_TRUE(ctx.getCompilationUnit().getErrorHandler().hasWarnings());
    bool found_warning = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_POTENTIAL_NULL_DEREFERENCE) {
            found_warning = true;
            break;
        }
    }
    ASSERT_TRUE(found_warning);

    return true;
}

TEST_FUNC(NullPointerAnalyzer_AddressOfSafe) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {\n"
        "    var x: i32 = 42;\n"
        "    var p: *i32 = &x;\n"
        "    var y: i32 = p.*;\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    NullPointerAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    ASSERT_TRUE(!ctx.getCompilationUnit().getErrorHandler().hasErrors());
    ASSERT_TRUE(!ctx.getCompilationUnit().getErrorHandler().hasWarnings());

    return true;
}

TEST_FUNC(NullPointerAnalyzer_ArrayAccessDeref) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    // This test uses an array access on an array type, which the TypeChecker allows.
    const char* source =
        "fn foo() void {\n"
        "    var arr: [8]i32 = undefined;\n"
        "    var x: i32 = arr[0];\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    NullPointerAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    // This should be safe
    ASSERT_TRUE(!ctx.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(NullPointerAnalyzer_PersistentStateTracking) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {\n"
        "    var x: i32 = 0;\n"
        "    var p: *i32 = null;\n"
        "    {\n"
        "        p = &x;\n"
        "    }\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    NullPointerAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    ASSERT_TRUE(!ctx.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(NullPointerAnalyzer_AssignmentTracking) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {\n"
        "    var p: *i32 = null;\n"
        "    p = null;\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    NullPointerAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    ASSERT_TRUE(!ctx.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}
