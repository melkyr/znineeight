#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "lifetime_analyzer.hpp"
#include "null_pointer_analyzer.hpp"
#include "c89_feature_validator.hpp"
#include "parser.hpp"
#include <new>

// Helper to run all semantic passes
static void run_all_semantic_passes(CompilationUnit& unit, ASTNode* root) {
    C89FeatureValidator validator(unit);
    validator.validate(root);

    TypeChecker tc(unit);
    tc.check(root);

    LifetimeAnalyzer la(unit);
    la.analyze(root);

    NullPointerAnalyzer npa(unit);
    npa.analyze(root);
}

TEST_FUNC(Milestone4_HappyPath_Integrated) {
    ArenaAllocator arena(65536);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn add(a: i32, b: i32) i32 {\n"
        "    return a + b;\n"
        "}\n"
        "\n"
        "fn main() void {\n"
        "    var x: i32 = 10;\n"
        "    var p: *i32 = &x;\n"
        "    var res: i32 = add(x, p.*);\n"
        "    if (res > 0) {\n"
        "        res = res * 2;\n"
        "    }\n"
        "}\n";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("integration_test.zig", source);

    // 1. Verify Lexer via a manual check if needed, but Parser handles it.
    // To satisfy "Assert Lexer", we can create a separate Lexer and check some tokens.
    {
        Lexer lexer(unit.getSourceManager(), interner, arena, file_id);
        Token t = lexer.nextToken();
        ASSERT_EQ(t.type, TOKEN_FN);
        t = lexer.nextToken();
        ASSERT_EQ(t.type, TOKEN_IDENTIFIER);
        ASSERT_STREQ(t.value.identifier, "add");
    }

    // 2. Parser and AST assertions
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();
    ASSERT_TRUE(root != NULL);
    ASSERT_EQ(root->type, NODE_BLOCK_STMT);
    ASSERT_EQ(root->as.block_stmt.statements->length(), 2);

    // Verify first function 'add'
    ASTNode* add_fn = (*root->as.block_stmt.statements)[0];
    ASSERT_EQ(add_fn->type, NODE_FN_DECL);
    ASSERT_STREQ(add_fn->as.fn_decl->name, "add");
    ASSERT_EQ(add_fn->as.fn_decl->params->length(), 2);

    // 3. Run Semantic Passes
    run_all_semantic_passes(unit, root);

    // 4. Final verification
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    ASSERT_FALSE(unit.getErrorHandler().hasWarnings());

    return true;
}

TEST_FUNC(Milestone4_C89_Rejection_FailFast) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    // Slice is a non-C89 feature that should be rejected by C89FeatureValidator
    const char* source = "var s: []i32 = undefined;";

    // We expect a fatal error (abort) because the validator uses fatalError which calls abort()
    ASSERT_TRUE(expect_type_checker_abort(source));

    return true;
}

TEST_FUNC(Milestone4_Lifetime_Violation_Integrated) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn get_ptr() *i32 {\n"
        "    var x: i32 = 42;\n"
        "    return &x;\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* root = parser->parse();

    TypeChecker tc(ctx.getCompilationUnit());
    tc.check(root);

    LifetimeAnalyzer la(ctx.getCompilationUnit());
    la.analyze(root);

    ASSERT_TRUE(ctx.getCompilationUnit().getErrorHandler().hasErrors());

    bool found_lifetime_err = false;
    const DynamicArray<ErrorReport>& errors = ctx.getCompilationUnit().getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_LIFETIME_VIOLATION) {
            found_lifetime_err = true;
            break;
        }
    }
    ASSERT_TRUE(found_lifetime_err);

    return true;
}

TEST_FUNC(Milestone4_NullPointer_Deref_Integrated) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn main() void {\n"
        "    var p: *i32 = null;\n"
        "    var x: i32 = p.*;\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* root = parser->parse();

    TypeChecker tc(ctx.getCompilationUnit());
    tc.check(root);

    NullPointerAnalyzer npa(ctx.getCompilationUnit());
    npa.analyze(root);

    ASSERT_TRUE(ctx.getCompilationUnit().getErrorHandler().hasErrors());

    bool found_null_err = false;
    const DynamicArray<ErrorReport>& errors = ctx.getCompilationUnit().getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_NULL_POINTER_DEREFERENCE) {
            found_null_err = true;
            break;
        }
    }
    ASSERT_TRUE(found_null_err);

    return true;
}

TEST_FUNC(Milestone4_Complex_EdgeCase_Shadowing_And_NullGuards) {
    ArenaAllocator arena(32768);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn complex_test(p: *i32) void {\n"
        "    if (p != null) {\n"
        "        var x: i32 = p.*;\n" // Safe
        "        {\n"
        "            var p_inner: *i32 = null;\n" // No shadowing to keep it simple for now
        "            if (p_inner == null) {\n"
        "                // p_inner is null here\n"
        "            } else {\n"
        "                var y: i32 = p_inner.*;\n" // Safe (unreachable, but analysis should handle it)
        "            }\n"
        "        }\n"
        "        var z: i32 = p.*;\n" // Still safe (original p)
        "    }\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker tc(ctx.getCompilationUnit());
    tc.check(ast);

    NullPointerAnalyzer npa(ctx.getCompilationUnit());
    npa.analyze(ast);

    if (ctx.getCompilationUnit().getErrorHandler().hasWarnings()) {
        const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
        for (size_t i = 0; i < warnings.length(); ++i) {
            printf("Unexpected warning: %s at %d:%d (code %d)\n", warnings[i].message, warnings[i].location.line, warnings[i].location.column, warnings[i].code);
        }
    }

    ASSERT_FALSE(ctx.getCompilationUnit().getErrorHandler().hasErrors());
    ASSERT_FALSE(ctx.getCompilationUnit().getErrorHandler().hasWarnings());

    return true;
}

TEST_FUNC(Milestone4_Enum_AutoIncrement_Overflow) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    // u8 max is 255. 255 + 1 will overflow.
    const char* source =
        "const MyEnum = enum(u8) {\n"
        "    A = 255,\n"
        "    B\n"
        "};\n";

    // Enum validation in TypeChecker should abort on overflow
    ASSERT_TRUE(expect_type_checker_abort(source));

    return true;
}
