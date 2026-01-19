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
