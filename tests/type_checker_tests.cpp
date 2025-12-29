#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"

TEST_FUNC(TypeCheckerValidDeclarations) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);

    // i32 declaration
    const char* source_i32 = "var x: i32 = 10;";
    ParserTestContext context_i32(source_i32, arena, interner);
    Parser parser_i32 = context_i32.getParser();
    ASTNode* root_i32 = parser_i32.parse();
    TypeChecker checker_i32(context_i32.getCompilationUnit());
    checker_i32.check(root_i32);
    ASSERT_FALSE(context_i32.getCompilationUnit().getErrorHandler().hasErrors());

    // i64 declaration
    const char* source_i64 = "var y: i64 = 3000000000;";
    ParserTestContext context_i64(source_i64, arena, interner);
    Parser parser_i64 = context_i64.getParser();
    ASTNode* root_i64 = parser_i64.parse();
    TypeChecker checker_i64(context_i64.getCompilationUnit());
    checker_i64.check(root_i64);
    ASSERT_FALSE(context_i64.getCompilationUnit().getErrorHandler().hasErrors());

    // bool declaration
    const char* source_bool = "var z: bool = true;";
    ParserTestContext context_bool(source_bool, arena, interner);
    Parser parser_bool = context_bool.getParser();
    ASTNode* root_bool = parser_bool.parse();
    TypeChecker checker_bool(context_bool.getCompilationUnit());
    checker_bool.check(root_bool);
    ASSERT_FALSE(context_bool.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeCheckerInvalidDeclarations) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    const char* source = "var x: i32 = \"hello\";";
    ParserTestContext context(source, arena, interner);
    Parser parser = context.getParser();
    ASTNode* root = parser.parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);
    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeCheckerStringLiteralType) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    const char* source = "fn my_func() -> void { \"hello world\"; }";
    ParserTestContext context(source, arena, interner);
    Parser parser = context.getParser();
    ASTNode* root = parser.parse();

    // Traverse the AST to find the string literal
    ASTNode* fn_decl_node = (*root->as.block_stmt.statements)[0];
    ASTNode* body_node = fn_decl_node->as.fn_decl->body;
    ASTNode* expr_stmt_node = (*body_node->as.block_stmt.statements)[0];
    ASTNode* string_literal_node = expr_stmt_node->as.expression_stmt.expression;

    ASSERT_EQ(string_literal_node->type, NODE_STRING_LITERAL);

    TypeChecker checker(context.getCompilationUnit());
    Type* result_type = checker.visit(string_literal_node);

    ASSERT_TRUE(result_type != NULL);
    ASSERT_EQ(result_type->kind, TYPE_POINTER);
    ASSERT_TRUE(result_type->as.pointer.base != NULL);
    ASSERT_EQ(result_type->as.pointer.base->kind, TYPE_U8);

    return true;
}

TEST_FUNC(TypeCheckerIntegerLiteralType) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    // Create a dummy context to initialize the CompilationUnit for the TypeChecker
    ParserTestContext context("", arena, interner);
    TypeChecker checker(context.getCompilationUnit());

    // Test case for i32 max
    ASTIntegerLiteralNode node_i32_max;
    node_i32_max.value = 2147483647;
    Type* type_i32_max = checker.visitIntegerLiteral(&node_i32_max);
    ASSERT_EQ(type_i32_max->kind, TYPE_I32);

    // Test case for i32 min
    ASTIntegerLiteralNode node_i32_min;
    node_i32_min.value = -2147483648;
    Type* type_i32_min = checker.visitIntegerLiteral(&node_i32_min);
    ASSERT_EQ(type_i32_min->kind, TYPE_I32);

    // Test case for value just over i32 max
    ASTIntegerLiteralNode node_i64_over;
    node_i64_over.value = 2147483648;
    Type* type_i64_over = checker.visitIntegerLiteral(&node_i64_over);
    ASSERT_EQ(type_i64_over->kind, TYPE_I64);

    // Test case for value just under i32 min
    ASTIntegerLiteralNode node_i64_under;
    node_i64_under.value = -2147483649LL; // Use LL for long long
    Type* type_i64_under = checker.visitIntegerLiteral(&node_i64_under);
    ASSERT_EQ(type_i64_under->kind, TYPE_I64);

    return true;
}


TEST_FUNC(TypeCheckerUndeclaredVariable) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    const char* source = "var x: i32 = y;";
    ParserTestContext context(source, arena, interner);
    Parser parser = context.getParser();
    ASTNode* root = parser.parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);
    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}
