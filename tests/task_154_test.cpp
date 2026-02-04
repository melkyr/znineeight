#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include "generic_catalogue.hpp"

// Test that functions with 'anytype' parameters are detected and rejected.
TEST_FUNC(Task154_RejectAnytypeParam) {
    const char* source = "fn printAny(anytype value) void { }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

// Test that functions with 'type' parameters are detected and rejected.
TEST_FUNC(Task154_RejectTypeParam) {
    const char* source = "fn foo(T: type) void { }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

// Test that 'comptime' parameters are catalogued as definitions.
TEST_FUNC(Task154_CatalogueComptimeDefinition) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source = "fn generic(comptime x: i32) void { }";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    TypeChecker checker(unit);
    checker.check(ast);

    // We expect it to be in the catalogue as a definition.
    ASSERT_TRUE(unit.getGenericCatalogue().isFunctionGeneric("generic"));
    return true;
}

// Test that 'anytype' parameters are catalogued as definitions.
TEST_FUNC(Task154_CatalogueAnytypeDefinition) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source = "fn generic(anytype x) void { }";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    TypeChecker checker(unit);
    checker.check(ast);

    ASSERT_TRUE(unit.getGenericCatalogue().isFunctionGeneric("generic"));
    return true;
}

// Test that 'type' parameters are catalogued as definitions.
TEST_FUNC(Task154_CatalogueTypeParamDefinition) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source = "fn generic(T: type) void { }";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    TypeChecker checker(unit);
    checker.check(ast);

    ASSERT_TRUE(unit.getGenericCatalogue().isFunctionGeneric("generic"));
    return true;
}
