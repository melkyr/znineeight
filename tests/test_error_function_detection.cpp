#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "c89_feature_validator.hpp"
#include "parser.hpp"
#include <string.h>

TEST_FUNC(ErrorFunction_DetectBasicErrorUnion) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source = "fn f() !void {}";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    C89FeatureValidator validator(unit);
    validator.checkOnly(root);

    ASSERT_EQ(1u, unit.getErrorFunctionCatalogue().getCount());
    ASSERT_EQ(0, strcmp("f", unit.getErrorFunctionCatalogue().getFunction(0).name));
    ASSERT_FALSE(unit.getErrorFunctionCatalogue().getFunction(0).is_generic);

    return true;
}

TEST_FUNC(ErrorFunction_DetectExplicitErrorSet) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source = "const E = error { A }; fn f() E {}";
    u32 file_id = unit.addSource("test.zig", source);

    // Register E as an error set type manually for the validator to see it
    Type* err_set = createErrorSetType(arena);
    Symbol sym = SymbolBuilder(arena).withName(interner.intern("E")).ofType(SYMBOL_TYPE).withType(err_set).build();
    unit.getSymbolTable().insert(sym);

    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    C89FeatureValidator validator(unit);
    validator.checkOnly(root);

    ASSERT_EQ(1u, unit.getErrorFunctionCatalogue().getCount());
    ASSERT_EQ(0, strcmp("f", unit.getErrorFunctionCatalogue().getFunction(0).name));

    return true;
}

TEST_FUNC(ErrorFunction_DetectGenericWithError) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source = "fn f(comptime T: type) !T { return error.A; }";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    C89FeatureValidator validator(unit);
    validator.checkOnly(root);

    ASSERT_EQ(1u, unit.getErrorFunctionCatalogue().getCount());
    ASSERT_EQ(0, strcmp("f", unit.getErrorFunctionCatalogue().getFunction(0).name));
    ASSERT_TRUE(unit.getErrorFunctionCatalogue().getFunction(0).is_generic);

    return true;
}
