#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "type_system.hpp" // For TypeKind enum
#include <cstdio>       // For snprintf

// Helper function to get the resolved type of the first expression in a function body.
// This provides an integration test that runs the full pipeline from parsing to type checking.
static Type* get_resolved_type_of_literal(const char* literal_str, ArenaAllocator& arena, StringInterner& interner) {
    char source_buffer[256];
    snprintf(source_buffer, sizeof(source_buffer), "fn test_fn() -> void { %s; }", literal_str);

    // Create a new context for each literal. This creates a new CompilationUnit
    // and SourceManager, ensuring a clean state.
    ParserTestContext context(source_buffer, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();

    // The parser should succeed for this simple structure.
    if (!root || context.getCompilationUnit().getErrorHandler().hasErrors()) {
        return NULL;
    }

    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    if (context.getCompilationUnit().getErrorHandler().hasErrors()) {
        // This shouldn't happen for valid literals.
        return NULL;
    }

    // Navigate the AST to find the literal's ASTNode.
    // root (BLOCK) -> fn_decl -> body (BLOCK) -> expression_stmt -> literal
    ASTNode* fn_decl_node = (*root->as.block_stmt.statements)[0];
    ASTNode* body_node = fn_decl_node->as.fn_decl->body;
    if (!body_node || !body_node->as.block_stmt.statements || body_node->as.block_stmt.statements->length() == 0) {
        return NULL;
    }
    ASTNode* expr_stmt_node = (*body_node->as.block_stmt.statements)[0];
    ASTNode* literal_node = expr_stmt_node->as.expression_stmt.expression;

    return literal_node->resolved_type;
}

TEST_FUNC(TypeChecker_IntegerLiteralInference) {
    // Each literal is tested in its own scope with a fresh arena and interner
    // to prevent state corruption between test cases.
    {
        ArenaAllocator arena(262144);
        StringInterner interner(arena);
        Type* type = get_resolved_type_of_literal("127", arena, interner);
        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_I32);
    }
    {
        ArenaAllocator arena(262144);
        StringInterner interner(arena);
        // The parser sees this as UnaryOp(-) -> Integer(128).
        // 128 is inferred as i32, so the result is i32.
        Type* type = get_resolved_type_of_literal("-128", arena, interner);
        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_I32);
    }
    {
        ArenaAllocator arena(262144);
        StringInterner interner(arena);
        Type* type = get_resolved_type_of_literal("255u", arena, interner);
        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_U32);
    }
    {
        ArenaAllocator arena(262144);
        StringInterner interner(arena);
        Type* type = get_resolved_type_of_literal("128", arena, interner);
        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_I32);
    }
    {
        ArenaAllocator arena(262144);
        StringInterner interner(arena);
        Type* type = get_resolved_type_of_literal("65535u", arena, interner);
        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_U32);
    }
    {
        ArenaAllocator arena(262144);
        StringInterner interner(arena);
        Type* type = get_resolved_type_of_literal("65536", arena, interner);
        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_I32);
    }
    {
        ArenaAllocator arena(262144);
        StringInterner interner(arena);
        Type* type = get_resolved_type_of_literal("4294967295u", arena, interner);
        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_U32);
    }
    {
        ArenaAllocator arena(262144);
        StringInterner interner(arena);
        Type* type = get_resolved_type_of_literal("4294967296", arena, interner);
        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_I64);
    }
    {
        ArenaAllocator arena(262144);
        StringInterner interner(arena);
        Type* type = get_resolved_type_of_literal("9223372036854775808u", arena, interner);
        ASSERT_TRUE(type != NULL);
        ASSERT_EQ(type->kind, TYPE_U64);
    }
    return true;
}

TEST_FUNC(TypeChecker_FloatLiteralInference) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);

    Type* type_f64 = get_resolved_type_of_literal("3.14159", arena, interner);
    ASSERT_TRUE(type_f64 != NULL);
    ASSERT_EQ(type_f64->kind, TYPE_F64);

    return true;
}

TEST_FUNC(TypeChecker_CharLiteralInference) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);

    Type* type_u8 = get_resolved_type_of_literal("'z'", arena, interner);
    ASSERT_TRUE(type_u8 != NULL);
    ASSERT_EQ(type_u8->kind, TYPE_U8);

    return true;
}

TEST_FUNC(TypeChecker_StringLiteralInference) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);

    Type* type_ptr_const_u8 = get_resolved_type_of_literal("\"hello world\"", arena, interner);
    ASSERT_TRUE(type_ptr_const_u8 != NULL);
    ASSERT_EQ(type_ptr_const_u8->kind, TYPE_POINTER);
    // In Z98, string literals are pointers to arrays of u8
    ASSERT_EQ(type_ptr_const_u8->as.pointer.base->kind, TYPE_ARRAY);
    ASSERT_EQ(type_ptr_const_u8->as.pointer.base->as.array.element_type->kind, TYPE_U8);
    ASSERT_TRUE(type_ptr_const_u8->as.pointer.is_const);

    return true;
}
