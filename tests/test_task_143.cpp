#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "parser.hpp"
#include "type_checker.hpp"
#include "c89_feature_validator.hpp"
#include "try_expression_catalogue.hpp"
#include <cstring>
#include <cstdio>

TEST_FUNC(Task143_TryExpressionDetection_Contexts) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "fn mightFail() !i32 { return 42; }\n"
        "fn doTest() void {\n"
        "    var x: i32 = try mightFail();\n"
        "    x = try mightFail();\n"
        "}\n"
        "fn returnTry() !i32 {\n"
        "    return try mightFail();\n"
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

    TryExpressionCatalogue& cat = unit.getTryExpressionCatalogue();
    ASSERT_EQ(3, cat.count());

    const DynamicArray<TryExpressionInfo>* tries = cat.getTryExpressions();

    ASSERT_STREQ("variable_decl", (*tries)[0].context_type);
    ASSERT_STREQ("assignment", (*tries)[1].context_type);
    ASSERT_STREQ("return", (*tries)[2].context_type);

    return true;
}

TEST_FUNC(Task143_TryExpressionDetection_Nested) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "fn inner() !i32 { return 1; }\n"
        "fn doTest() void {\n"
        "    var x: i32 = try (try inner());\n"
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

    TryExpressionCatalogue& cat = unit.getTryExpressionCatalogue();
    ASSERT_EQ(2, cat.count());

    const DynamicArray<TryExpressionInfo>* tries = cat.getTryExpressions();

    ASSERT_STREQ("variable_decl", (*tries)[0].context_type);
    ASSERT_EQ(0, (*tries)[0].depth);

    ASSERT_STREQ("nested_try", (*tries)[1].context_type);
    ASSERT_EQ(1, (*tries)[1].depth);

    return true;
}

TEST_FUNC(Task143_TryExpressionDetection_MultipleInStatement) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "fn a() !i32 { return 1; }\n"
        "fn b() !i32 { return 2; }\n"
        "fn doTest() void {\n"
        "    var x: i32 = try a() + try b();\n"
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

    TryExpressionCatalogue& cat = unit.getTryExpressionCatalogue();
    ASSERT_EQ(2, cat.count());

    const DynamicArray<TryExpressionInfo>* tries = cat.getTryExpressions();

    ASSERT_STREQ("binary_op", (*tries)[0].context_type);
    ASSERT_STREQ("binary_op", (*tries)[1].context_type);

    return true;
}
