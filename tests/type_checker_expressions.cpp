#include "../src/include/test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "type_system.hpp"

TEST_FUNC(TypeChecker_BoolLiteral) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    // Test 'true'
    {
        // NOTE: The test pattern has been updated.
        // 1. A single CompilationUnit now owns all resources (arena, interner).
        // 2. The TypeChecker is initialized with a reference to the CompilationUnit.
        // 3. The Parser is retrieved as a pointer (Parser*) via getParser().
        //    Therefore, method calls must use the '->' operator.
        ParserTestContext ctx("true", arena, interner);
        ASTNode* expr = ctx.getParser()->parseExpression();
        Type* type = checker.visit(expr);
        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_BOOL);
    }

    // Test 'false'
    {
        ParserTestContext ctx("false", arena, interner);
        ASTNode* expr = ctx.getParser()->parseExpression();
        Type* type = checker.visit(expr);
        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_BOOL);
    }

    return true;
}

TEST_FUNC(TypeChecker_Identifier) {
    // Test a valid variable access by manually inserting a symbol
    {
        ArenaAllocator arena(262144);
        ArenaLifetimeGuard guard(arena);
        StringInterner interner(arena);
        CompilationUnit unit(arena, interner);
        TypeChecker checker(unit);

        SymbolTable& sym_table = unit.getSymbolTable();
        const char* var_name = interner.intern("x");
        Type* var_type = resolvePrimitiveTypeName("i32");
        Symbol symbol = SymbolBuilder(arena)
            .withName(var_name)
            .ofType(SYMBOL_VARIABLE)
            .withType(var_type)
            .build();
        sym_table.insert(symbol);

        ParserTestContext ctx("x", arena, interner);
        ASTNode* expr = ctx.getParser()->parseExpression();
        Type* type = checker.visit(expr);

        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_I32);
        ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    }

    // Test an invalid variable access
    {
        ArenaAllocator arena(262144);
        ArenaLifetimeGuard guard(arena);
        StringInterner interner(arena);
        CompilationUnit unit(arena, interner);
        TypeChecker checker(unit);

        ParserTestContext ctx("y", arena, interner);
        ASTNode* expr = ctx.getParser()->parseExpression();
        Type* type = checker.visit(expr);

        ASSERT_TRUE(type == NULL);
        ASSERT_TRUE(unit.getErrorHandler().hasErrors());
        ASSERT_EQ(unit.getErrorHandler().getErrors()[0].code, ERR_UNDEFINED_VARIABLE);
    }

    return true;
}

TEST_FUNC(TypeChecker_CharLiteral) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    ParserTestContext ctx("'a'", arena, interner);
    ASTNode* expr = ctx.getParser()->parseExpression();
    Type* type = checker.visit(expr);
    ASSERT_TRUE(type != NULL);
    ASSERT_EQ(type->kind, TYPE_U8);

    return true;
}

TEST_FUNC(TypeChecker_StringLiteral) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    ParserTestContext ctx("\"hello\"", arena, interner);
    ASTNode* expr = ctx.getParser()->parseExpression();
    Type* type = checker.visit(expr);
    ASSERT_TRUE(type != NULL);
    ASSERT_EQ(type->kind, TYPE_POINTER);
    ASSERT_TRUE(type->as.pointer.is_const);
    ASSERT_EQ(type->as.pointer.base->kind, TYPE_U8);

    return true;
}

TEST_FUNC(TypeChecker_IntegerLiteral) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    // Test i32
    {
        ParserTestContext ctx("123", arena, interner);
        ASTNode* expr = ctx.getParser()->parseExpression();
        Type* type = checker.visit(expr);
        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_I32);
    }

    // Test i64
    {
        ParserTestContext ctx("3000000000", arena, interner);
        ASTNode* expr = ctx.getParser()->parseExpression();
        Type* type = checker.visit(expr);
        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_I64);
    }

    return true;
}

TEST_FUNC(TypeChecker_BinaryOp) {
    // Test valid i32 addition
    {
        ArenaAllocator arena(262144);
        ArenaLifetimeGuard guard(arena);
        StringInterner interner(arena);
        CompilationUnit unit(arena, interner);
        TypeChecker checker(unit);
        ParserTestContext ctx("1 + 2", arena, interner);
        ASTNode* expr = ctx.getParser()->parseExpression();
        Type* type = checker.visit(expr);
        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_I32);
        ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    }

    // Test valid i32 comparison
    {
        ArenaAllocator arena(262144);
        ArenaLifetimeGuard guard(arena);
        StringInterner interner(arena);
        CompilationUnit unit(arena, interner);
        TypeChecker checker(unit);
        ParserTestContext ctx("1 == 2", arena, interner);
        ASTNode* expr = ctx.getParser()->parseExpression();
        Type* type = checker.visit(expr);
        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_BOOL);
        ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    }

    // Test invalid addition (i32 + bool)
    {
        ArenaAllocator arena(262144);
        ArenaLifetimeGuard guard(arena);
        StringInterner interner(arena);
        CompilationUnit unit(arena, interner);
        TypeChecker checker(unit);
        ParserTestContext ctx("1 + true", arena, interner);
        ASTNode* expr = ctx.getParser()->parseExpression();
        Type* type = checker.visit(expr);
        ASSERT_TRUE(type == NULL);
        ASSERT_TRUE(unit.getErrorHandler().hasErrors());
        ASSERT_EQ(unit.getErrorHandler().getErrors()[0].code, ERR_TYPE_MISMATCH);
    }

    // Test invalid comparison (i32 > bool)
    {
        ArenaAllocator arena(262144);
        ArenaLifetimeGuard guard(arena);
        StringInterner interner(arena);
        CompilationUnit unit(arena, interner);
        TypeChecker checker(unit);
        ParserTestContext ctx("1 > true", arena, interner);
        ASTNode* expr = ctx.getParser()->parseExpression();
        Type* type = checker.visit(expr);
        ASSERT_TRUE(type == NULL);
        ASSERT_TRUE(unit.getErrorHandler().hasErrors());
        ASSERT_EQ(unit.getErrorHandler().getErrors()[0].code, ERR_TYPE_MISMATCH);
    }

    // Test invalid addition (i32 + f64)
    {
        ArenaAllocator arena(262144);
        ArenaLifetimeGuard guard(arena);
        StringInterner interner(arena);
        CompilationUnit unit(arena, interner);
        TypeChecker checker(unit);
        ParserTestContext ctx("1 + 1.0", arena, interner);
        ASTNode* expr = ctx.getParser()->parseExpression();
        Type* type = checker.visit(expr);
        ASSERT_TRUE(type == NULL);
        ASSERT_TRUE(unit.getErrorHandler().hasErrors());
        ASSERT_EQ(unit.getErrorHandler().getErrors()[0].code, ERR_TYPE_MISMATCH);
    }

    // Test null operand (undeclared variable) to prevent crash
    {
        ArenaAllocator arena(262144);
        ArenaLifetimeGuard guard(arena);
        StringInterner interner(arena);
        CompilationUnit unit(arena, interner);
        TypeChecker checker(unit);
        ParserTestContext ctx("undeclared + 1", arena, interner);
        ASTNode* expr = ctx.getParser()->parseExpression();
        Type* type = checker.visit(expr);
        ASSERT_TRUE(type == NULL);
        ASSERT_TRUE(unit.getErrorHandler().hasErrors());
        ASSERT_EQ(unit.getErrorHandler().getErrors()[0].code, ERR_UNDEFINED_VARIABLE);
    }

    return true;
}
