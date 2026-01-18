#include "null_pointer_analyzer.hpp"
#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"

bool test_null_pointer_analyzer_basic() {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    const char* source = "fn myFunc() void { var p: *i32 = null; }";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker checker(ctx.getCompilationUnit());
    checker.check(ast);
    ASSERT_TRUE(!ctx.getCompilationUnit().getErrorHandler().hasErrors());

    NullPointerAnalyzer analyzer(arena, ctx.getCompilationUnit());
    analyzer.analyze(ast);

    // Phase 1 just builds the framework, so we just check it doesn't crash
    // and correctly traverses a basic AST.
    ASSERT_TRUE(!ctx.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

bool test_null_pointer_analyzer_global_var() {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    const char* source = "var global_p: *i32 = null; fn myFunc() void {}";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker checker(ctx.getCompilationUnit());
    checker.check(ast);
    ASSERT_TRUE(!ctx.getCompilationUnit().getErrorHandler().hasErrors());

    NullPointerAnalyzer analyzer(arena, ctx.getCompilationUnit());
    analyzer.analyze(ast);

    ASSERT_TRUE(!ctx.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}
