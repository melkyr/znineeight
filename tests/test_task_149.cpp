#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include "c89_feature_validator.hpp"
#include <cstdio>

TEST_FUNC(Task149_ErrorHandlingFeaturesCatalogued) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn my_test() !i32 {\n"
        "    errdefer {}\n"
        "    const x = try foo();\n"
        "    const y = bar() catch 0;\n"
        "    const z = maybe() orelse 0;\n"
        "    return 0;\n"
        "}\n"
        "fn foo() !i32 { return 0; }\n"
        "fn bar() !i32 { return 0; }\n"
        "fn maybe() ?i32 { return 0; }\n";

    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker checker(unit);
    checker.check(ast);

    C89FeatureValidator validator(unit);
    validator.visitAll(ast);

    ASSERT_TRUE(unit.getTryExpressionCatalogue().count() > 0);
    ASSERT_TRUE(unit.getCatchExpressionCatalogue().count() > 0);
    ASSERT_TRUE(unit.getOrelseExpressionCatalogue().count() > 0);
    ASSERT_TRUE(unit.getErrDeferCatalogue().count() > 0);

    unit.validateErrorHandlingRules();
    ASSERT_TRUE(unit.getErrorHandler().hasInfos());

    return true;
}
