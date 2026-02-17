#include "test_framework.hpp"
#include "test_utils.hpp"
#include "parser.hpp"
#include "ast.hpp"

TEST_FUNC(IntegerLiteralParsing_UnsignedSuffix) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    const char* source = "const x: u32 = 123u;";
    ParserTestContext context(source, arena, interner);
    ASTNode* node = context.getParser()->parseVarDecl();

    ASSERT_TRUE(node != (ASTNode*)NULL);
    ASSERT_EQ(node->type, NODE_VAR_DECL);

    ASTVarDeclNode* var_decl = node->as.var_decl;
    ASSERT_TRUE(var_decl->initializer != (ASTNode*)NULL);
    ASSERT_EQ(var_decl->initializer->type, NODE_INTEGER_LITERAL);

    ASTIntegerLiteralNode* int_literal = &var_decl->initializer->as.integer_literal;
    ASSERT_EQ(int_literal->value, 123);
    ASSERT_TRUE(int_literal->is_unsigned);
    ASSERT_FALSE(int_literal->is_long);

    return true;
}

TEST_FUNC(IntegerLiteralParsing_LongSuffix) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    const char* source = "const x: i64 = 456L;";
    ParserTestContext context(source, arena, interner);
    ASTNode* node = context.getParser()->parseVarDecl();

    ASSERT_TRUE(node != (ASTNode*)NULL);
    ASSERT_EQ(node->type, NODE_VAR_DECL);

    ASTVarDeclNode* var_decl = node->as.var_decl;
    ASSERT_TRUE(var_decl->initializer != (ASTNode*)NULL);
    ASSERT_EQ(var_decl->initializer->type, NODE_INTEGER_LITERAL);

    ASTIntegerLiteralNode* int_literal = &var_decl->initializer->as.integer_literal;
    ASSERT_EQ(int_literal->value, 456);
    ASSERT_FALSE(int_literal->is_unsigned);
    ASSERT_TRUE(int_literal->is_long);

    return true;
}

TEST_FUNC(IntegerLiteralParsing_UnsignedLongSuffix) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    const char* source = "const x: u64 = 789UL;";
    ParserTestContext context(source, arena, interner);
    ASTNode* node = context.getParser()->parseVarDecl();

    ASSERT_TRUE(node != (ASTNode*)NULL);
    ASSERT_EQ(node->type, NODE_VAR_DECL);

    ASTVarDeclNode* var_decl = node->as.var_decl;
    ASSERT_TRUE(var_decl->initializer != (ASTNode*)NULL);
    ASSERT_EQ(var_decl->initializer->type, NODE_INTEGER_LITERAL);

    ASTIntegerLiteralNode* int_literal = &var_decl->initializer->as.integer_literal;
    ASSERT_EQ(int_literal->value, 789);
    ASSERT_TRUE(int_literal->is_unsigned);
    ASSERT_TRUE(int_literal->is_long);

    return true;
}
