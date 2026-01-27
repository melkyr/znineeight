#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "parser.hpp"
#include "type_checker.hpp"
#include "c89_feature_validator.hpp"
#include "catch_expression_catalogue.hpp"
#include "orelse_expression_catalogue.hpp"
#include <cstring>

TEST_FUNC(Task144_CatchExpressionDetection_Basic) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "fn mightFail() !i32 { return 42; }\n"
        "fn doTest() void {\n"
        "    var x: i32 = mightFail() catch 0;\n"
        "    x = mightFail() catch |err| 1;\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    unit.injectRuntimeSymbols();

    Parser* parser = unit.createParser(file_id);
    ASTNode* program = parser->parse();
    ASSERT_TRUE(program != NULL);

    TypeChecker checker(unit);
    checker.check(program);

    C89FeatureValidator validator(unit);
    validator.visitAll(program);

    CatchExpressionCatalogue& cat = unit.getCatchExpressionCatalogue();
    ASSERT_EQ(2, cat.count());

    const DynamicArray<CatchExpressionInfo>* exprs = cat.getCatchExpressions();

    // First catch: mightFail() catch 0
    ASSERT_STREQ("variable_decl", (*exprs)[0].context_type);
    ASSERT_EQ(NULL, (*exprs)[0].error_param_name);
    ASSERT_FALSE((*exprs)[0].is_chained);

    // Second catch: mightFail() catch |err| 1
    ASSERT_STREQ("assignment", (*exprs)[1].context_type);
    ASSERT_STREQ("err", (*exprs)[1].error_param_name);
    ASSERT_FALSE((*exprs)[1].is_chained);

    return true;
}

TEST_FUNC(Task144_CatchExpressionDetection_Chained) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "fn mightFail() !i32 { return 42; }\n"
        "fn doTest() void {\n"
        "    var x: i32 = mightFail() catch mightFail() catch 0;\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    unit.injectRuntimeSymbols();

    Parser* parser = unit.createParser(file_id);
    ASTNode* program = parser->parse();
    ASSERT_TRUE(program != NULL);

    TypeChecker checker(unit);
    checker.check(program);

    C89FeatureValidator validator(unit);
    validator.visitAll(program);

    CatchExpressionCatalogue& cat = unit.getCatchExpressionCatalogue();
    // mightFail() catch (mightFail() catch 0)
    // Actually Zig catch is left-associative?
    // Lexer says: (a catch b) catch c
    // Wait, let's check AST_parser.md or parser.cpp
    // get_token_precedence returns 1 for catch.
    // parsePrecedenceExpr(1) -> while (precedence >= min_precedence) { ... parsePrecedenceExpr(precedence + 1) }
    // This is standard Pratt which results in left-associativity for same precedence if not handled otherwise.
    // (a catch b) catch c.

    ASSERT_EQ(2, cat.count());

    const DynamicArray<CatchExpressionInfo>* exprs = cat.getCatchExpressions();

    // In (a catch b) catch c:
    // Outer catch is 'catch c', inner is 'a catch b'.
    // If we visit recursively, we might see them in different orders depending on visitor.
    // C89FeatureValidator::visitAll uses a standard visitor.

    // For NODE_CATCH_EXPR, we should visit payload then else_expr.
    // In (a catch b) catch c: payload is (a catch b), else_expr is c.
    // So we should see 'a catch b' first, then 'catch c'.

    ASSERT_TRUE((*exprs)[0].is_chained);
    ASSERT_EQ(0, (*exprs)[0].chain_index);

    ASSERT_TRUE((*exprs)[1].is_chained);
    ASSERT_EQ(1, (*exprs)[1].chain_index);

    return true;
}

TEST_FUNC(Task144_OrelseExpressionDetection) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "fn maybeInt() ?i32 { return 42; }\n"
        "fn doTest() void {\n"
        "    var x: i32 = maybeInt() orelse 0;\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    unit.injectRuntimeSymbols();

    Parser* parser = unit.createParser(file_id);
    ASTNode* program = parser->parse();
    ASSERT_TRUE(program != NULL);

    TypeChecker checker(unit);
    checker.check(program);

    C89FeatureValidator validator(unit);
    validator.visitAll(program);

    OrelseExpressionCatalogue& cat = unit.getOrelseExpressionCatalogue();
    ASSERT_EQ(1, cat.count());

    const DynamicArray<OrelseExpressionInfo>* exprs = cat.getOrelseExpressions();
    ASSERT_STREQ("variable_decl", (*exprs)[0].context_type);

    return true;
}
