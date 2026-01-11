#include "../src/include/test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "type_system.hpp"

static void setup_pointer_arithmetic_test(
    ArenaAllocator& arena,
    StringInterner& interner,
    CompilationUnit& unit,
    const char* ptr_name,
    Type* base_type) {

    Type* ptr_type = createPointerType(arena, base_type, false);
    Symbol ptr_symbol = SymbolBuilder(arena)
        .withName(interner.intern(ptr_name))
        .ofType(SYMBOL_VARIABLE)
        .withType(ptr_type)
        .build();
    unit.getSymbolTable().insert(ptr_symbol);
}

TEST_FUNC(TypeChecker_PointerIntegerAddition) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    setup_pointer_arithmetic_test(arena, interner, unit, "p", resolvePrimitiveTypeName("i32"));

    ParserTestContext ctx("p + 1", arena, interner);
    ASTNode* expr = ctx.getParser()->parseExpression();
    Type* type = checker.visit(expr);

    ASSERT_TRUE(type != NULL);
    ASSERT_EQ(type->kind, TYPE_POINTER);
    ASSERT_EQ(type->as.pointer.base->kind, TYPE_I32);
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeChecker_IntegerPointerAddition) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    setup_pointer_arithmetic_test(arena, interner, unit, "p", resolvePrimitiveTypeName("i32"));

    ParserTestContext ctx("1 + p", arena, interner);
    ASTNode* expr = ctx.getParser()->parseExpression();
    Type* type = checker.visit(expr);

    ASSERT_TRUE(type != NULL);
    ASSERT_EQ(type->kind, TYPE_POINTER);
    ASSERT_EQ(type->as.pointer.base->kind, TYPE_I32);
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeChecker_PointerIntegerSubtraction) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    setup_pointer_arithmetic_test(arena, interner, unit, "p", resolvePrimitiveTypeName("i32"));

    ParserTestContext ctx("p - 1", arena, interner);
    ASTNode* expr = ctx.getParser()->parseExpression();
    Type* type = checker.visit(expr);

    ASSERT_TRUE(type != NULL);
    ASSERT_EQ(type->kind, TYPE_POINTER);
    ASSERT_EQ(type->as.pointer.base->kind, TYPE_I32);
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeChecker_PointerPointerSubtraction) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    setup_pointer_arithmetic_test(arena, interner, unit, "p1", resolvePrimitiveTypeName("i32"));
    setup_pointer_arithmetic_test(arena, interner, unit, "p2", resolvePrimitiveTypeName("i32"));

    ParserTestContext ctx("p1 - p2", arena, interner);
    ASTNode* expr = ctx.getParser()->parseExpression();
    Type* type = checker.visit(expr);

    ASSERT_TRUE(type != NULL);
    ASSERT_EQ(type->kind, TYPE_ISIZE);
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeChecker_Invalid_PointerPointerAddition) {
    const char* source =
        "fn test_fn() {\n"
        "    var x: i32 = 0;\n"
        "    var y: i32 = 0;\n"
        "    var p1: *i32 = &x;\n"
        "    var p2: *i32 = &y;\n"
        "    var result = p1 + p2;\n"
        "}\n";
    expect_type_checker_abort(source);
    return true;
}

TEST_FUNC(TypeChecker_Invalid_PointerPointerSubtraction_DifferentTypes) {
    const char* source =
        "fn test_fn() {\n"
        "    var x: i32 = 0;\n"
        "    var y: f64 = 0.0;\n"
        "    var p1: *i32 = &x;\n"
        "    var p2: *f64 = &y;\n"
        "    var result = p1 - p2;\n"
        "}\n";
    expect_type_checker_abort(source);
    return true;
}

TEST_FUNC(TypeChecker_Invalid_PointerMultiplication) {
    const char* source =
        "fn test_fn() {\n"
        "    var x: i32 = 0;\n"
        "    var p: *i32 = &x;\n"
        "    var result = p * 2;\n"
        "}\n";
    expect_type_checker_abort(source);
    return true;
}
