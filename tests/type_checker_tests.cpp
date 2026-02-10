#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"

TEST_FUNC(TypeCheckerValidDeclarations) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);

    // i32 declaration
    const char* source_i32 = "var x: i32 = 10;";
    ParserTestContext context_i32(source_i32, arena, interner);
    Parser* parser_i32 = context_i32.getParser();
    ASTNode* root_i32 = parser_i32->parse();
    TypeChecker checker_i32(context_i32.getCompilationUnit());
    checker_i32.check(root_i32);
    ASSERT_FALSE(context_i32.getCompilationUnit().getErrorHandler().hasErrors());

    // i64 declaration
    const char* source_i64 = "var y: i64 = 3000000000;";
    ParserTestContext context_i64(source_i64, arena, interner);
    Parser* parser_i64 = context_i64.getParser();
    ASTNode* root_i64 = parser_i64->parse();
    TypeChecker checker_i64(context_i64.getCompilationUnit());
    checker_i64.check(root_i64);
    ASSERT_FALSE(context_i64.getCompilationUnit().getErrorHandler().hasErrors());

    // bool declaration
    const char* source_bool = "var z: bool = true;";
    ParserTestContext context_bool(source_bool, arena, interner);
    Parser* parser_bool = context_bool.getParser();
    ASTNode* root_bool = parser_bool->parse();
    TypeChecker checker_bool(context_bool.getCompilationUnit());
    checker_bool.check(root_bool);
    ASSERT_FALSE(context_bool.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeChecker_C89IntegerCompatibility) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    ParserTestContext context("", arena, interner);
    TypeChecker checker(context.getCompilationUnit());

    // Test cases for signed integers
    ASTIntegerLiteralNode node1;
    plat_memset(&node1, 0, sizeof(node1));
    node1.value = 127;
    node1.is_unsigned = false;
    ASSERT_EQ(checker.visitIntegerLiteral(NULL, &node1)->kind, TYPE_I32);

    ASTIntegerLiteralNode node2;
    plat_memset(&node2, 0, sizeof(node2));
    node2.value = 32767;
    node2.is_unsigned = false;
    ASSERT_EQ(checker.visitIntegerLiteral(NULL, &node2)->kind, TYPE_I32);

    ASTIntegerLiteralNode node3;
    plat_memset(&node3, 0, sizeof(node3));
    node3.value = 2147483647;
    node3.is_unsigned = false;
    ASSERT_EQ(checker.visitIntegerLiteral(NULL, &node3)->kind, TYPE_I32);

    // Test cases for unsigned integers
    ASTIntegerLiteralNode node4;
    plat_memset(&node4, 0, sizeof(node4));
    node4.value = 255;
    node4.is_unsigned = true;
    ASSERT_EQ(checker.visitIntegerLiteral(NULL, &node4)->kind, TYPE_U32);

    ASTIntegerLiteralNode node5;
    plat_memset(&node5, 0, sizeof(node5));
    node5.value = 65535;
    node5.is_unsigned = true;
    ASSERT_EQ(checker.visitIntegerLiteral(NULL, &node5)->kind, TYPE_U32);

    ASTIntegerLiteralNode node6;
    plat_memset(&node6, 0, sizeof(node6));
    node6.value = 4294967295;
    node6.is_unsigned = true;
    ASSERT_EQ(checker.visitIntegerLiteral(NULL, &node6)->kind, TYPE_U32);

    return true;
}

TEST_FUNC(TypeCheckerInvalidDeclarations) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    const char* source = "var x: i32 = \"hello\";";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);
    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeCheckerStringLiteralType) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    const char* source = "fn my_func() -> void { \"hello world\"; }";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();

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
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    // Create a dummy context to initialize the CompilationUnit for the TypeChecker
    ParserTestContext context("", arena, interner);
    TypeChecker checker(context.getCompilationUnit());

    // Test case for i32 max
    ASTIntegerLiteralNode node_i32_max;
    plat_memset(&node_i32_max, 0, sizeof(node_i32_max));
    node_i32_max.value = 2147483647;
    node_i32_max.is_unsigned = false;
    node_i32_max.is_long = false;
    Type* type_i32_max = checker.visitIntegerLiteral(NULL, &node_i32_max);
    ASSERT_EQ(type_i32_max->kind, TYPE_I32);

    // Test case for i32 min
    ASTIntegerLiteralNode node_i32_min;
    plat_memset(&node_i32_min, 0, sizeof(node_i32_min));
    node_i32_min.value = -2147483648;
    node_i32_min.is_unsigned = false;
    node_i32_min.is_long = false;
    Type* type_i32_min = checker.visitIntegerLiteral(NULL, &node_i32_min);
    ASSERT_EQ(type_i32_min->kind, TYPE_I32);

    // Test case for value just over i32 max
    ASTIntegerLiteralNode node_i64_over;
    plat_memset(&node_i64_over, 0, sizeof(node_i64_over));
    node_i64_over.value = 2147483648;
    node_i64_over.is_unsigned = false;
    node_i64_over.is_long = false;
    Type* type_i64_over = checker.visitIntegerLiteral(NULL, &node_i64_over);
    ASSERT_EQ(type_i64_over->kind, TYPE_I64);

    // Test case for value just under i32 min
    ASTIntegerLiteralNode node_i64_under;
    plat_memset(&node_i64_under, 0, sizeof(node_i64_under));
    node_i64_under.value = -2147483649LL; // Use LL for long long
    node_i64_under.is_unsigned = false;
    node_i64_under.is_long = false;
    Type* type_i64_under = checker.visitIntegerLiteral(NULL, &node_i64_under);
    ASSERT_EQ(type_i64_under->kind, TYPE_I64);

    return true;
}


TEST_FUNC(TypeCheckerUndeclaredVariable) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    const char* source = "var x: i32 = y;";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);
    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}
