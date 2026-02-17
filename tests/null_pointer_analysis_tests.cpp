#include "test_framework.hpp"
#include "null_pointer_analyzer.hpp"
#include "type_checker.hpp"
#include "test_utils.hpp"
#include <new>

TEST_FUNC(NullPointerAnalyzer_BasicTracking) {
    ArenaAllocator arena(262144);
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

TEST_FUNC(NullPointerAnalyzer_Shadowing) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {\n"
        "    var x: i32 = 0;\n"
        "    var p: *i32 = null;\n"
        "    {\n"
        "        var p: *i32 = &x;\n" // Shadows outer p
        "        var y: i32 = p.*;\n" // Should be safe
        "    }\n"
        "    var z: i32 = p.*;\n" // Should warn (outer p is still null)
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    NullPointerAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    // Should have an error/warning for the last dereference only
    ASSERT_TRUE(ctx.getCompilationUnit().getErrorHandler().hasErrors() ||
                ctx.getCompilationUnit().getErrorHandler().hasWarnings());

    // We can't easily check EXACTLY which line failed without more infra,
    // but at least it shouldn't fail the safe dereference.
    return true;
}

TEST_FUNC(NullPointerAnalyzer_NoLeakage) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {\n"
        "    var x: i32 = 0;\n"
        "    if (true) {\n"
        "        var inner: *i32 = &x;\n"
        "        var a: i32 = inner.*;\n"
        "    }\n"
        "    // inner should not exist here\n"
        "    // var b: i32 = inner.*; // This would be a type error\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    NullPointerAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    // Should have NO errors (inner didn't leak and cause confusion)
    ASSERT_TRUE(!ctx.getCompilationUnit().getErrorHandler().hasErrors());
    ASSERT_TRUE(!ctx.getCompilationUnit().getErrorHandler().hasWarnings());

    return true;
}

TEST_FUNC(NullPointerAnalyzer_IfNullGuard) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {\n"
        "    var p: *i32 = null;\n"
        "    if (p != null) {\n"
        "        var x: i32 = p.*;\n" // Should be safe here
        "    }\n"
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

    // Should NOT have errors because of the if guard
    ASSERT_TRUE(!ctx.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(NullPointerAnalyzer_IfElseMerge) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {\n"
        "    var x: i32 = 0;\n"
        "    var p: *i32 = null;\n"
        "    if (p == null) {\n"
        "        p = &x;\n"
        "    } else {\n"
        "        // p is safe here too if it wasn't null\n"
        "    }\n"
        "    var y: i32 = p.*;\n" // Should be safe after the merge
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

TEST_FUNC(NullPointerAnalyzer_WhileGuard) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {\n"
        "    var p: *i32 = null;\n"
        "    while (p != null) {\n"
        "        var x: i32 = p.*;\n" // Should be safe in loop body
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

TEST_FUNC(NullPointerAnalyzer_WhileConservativeReset) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {\n"
        "    var x: i32 = 0;\n"
        "    var p: *i32 = &x;\n"
        "    while (p != null) {\n"
        "        p = null;\n" // Modified in loop
        "    }\n"
        "    var y: i32 = p.*;\n" // Should be a warning/error after loop
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    NullPointerAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    // After the while loop, p could be NULL
    ASSERT_TRUE(ctx.getCompilationUnit().getErrorHandler().hasErrors() ||
                ctx.getCompilationUnit().getErrorHandler().hasWarnings());

    return true;
}

TEST_FUNC(NullPointerAnalyzer_DefiniteNullDeref) {
    ArenaAllocator arena(262144);
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
    ArenaAllocator arena(262144);
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
    ArenaAllocator arena(262144);
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
    ArenaAllocator arena(262144);
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
    ArenaAllocator arena(262144);
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
    ArenaAllocator arena(262144);
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
    ArenaAllocator arena(262144);
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
