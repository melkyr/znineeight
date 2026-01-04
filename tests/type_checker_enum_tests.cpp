#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "ast.hpp"
#include "type_system.hpp"

TEST_FUNC(TypeChecker_ValidEnumDeclaration) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);

    const char* source = "fn test_fn() { var my_enum: enum { A, B, C }; }";
    ParserTestContext context(source, arena, interner);
    Parser parser = context.getParser();
    ASTNode* root = parser.parse();

    // Ensure parsing itself doesn't fail
    ASSERT_FALSE(context.getCompilationUnit().getErrorHandler().hasErrors());
    ASSERT_TRUE(root != NULL);

    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    // This is the main assertion for the initial test.
    // It will fail until the TypeChecker can handle NODE_ENUM_DECL.
    ASSERT_FALSE(context.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeChecker_EnumAutoIncrement) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);

    const char* source = "fn test_fn() { var my_enum: enum { A = 10, B, C }; }";
    ParserTestContext context(source, arena, interner);
    Parser parser = context.getParser();
    ASTNode* root = parser.parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    ASSERT_FALSE(context.getCompilationUnit().getErrorHandler().hasErrors());

    // Manually traverse the AST to find the enum type
    ASTNode* fn_decl = (*root->as.block_stmt.statements)[0];
    ASTNode* body = fn_decl->as.fn_decl->body;
    ASTNode* var_decl_node = (*body->as.block_stmt.statements)[0];
    ASTNode* enum_decl_node = var_decl_node->as.var_decl->type;

    Type* enum_type = enum_decl_node->resolved_type;
    ASSERT_TRUE(enum_type != NULL);
    ASSERT_EQ(enum_type->kind, TYPE_ENUM);

    DynamicArray<EnumMember>* members = enum_type->as.enum_details.members;
    ASSERT_TRUE(members != NULL);
    ASSERT_EQ(members->length(), 3);

    ASSERT_EQ(strcmp((*members)[0].name, "A"), 0);
    ASSERT_EQ((*members)[0].value, 10);

    ASSERT_EQ(strcmp((*members)[1].name, "B"), 0);
    ASSERT_EQ((*members)[1].value, 11);

    ASSERT_EQ(strcmp((*members)[2].name, "C"), 0);
    ASSERT_EQ((*members)[2].value, 12);

    return true;
}

TEST_FUNC(TypeChecker_EnumValidation) {
    // Test 1: Invalid backing type (float)
    ASSERT_TRUE(expect_type_checker_abort("fn test() { var my_enum: enum(f32) { A, B }; }"));

    // Test 2: Member value overflows backing type (u8)
    ASSERT_TRUE(expect_type_checker_abort("fn test() { var my_enum: enum(u8) { A = 255, B }; }"));

    // Test 3: Member value underflows backing type (i8)
    ASSERT_TRUE(expect_type_checker_abort("fn test() { var my_enum: enum(i8) { A = -129 }; }"));

    // Test 4: Non-constant initializer
    ASSERT_TRUE(expect_type_checker_abort("fn test() { var x = 10; var my_enum: enum { A = x }; }"));

    return true;
}
