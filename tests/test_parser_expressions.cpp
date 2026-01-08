#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include <cstring> // For strcmp

// This test depends on the `expect_parser_abort` helper function,
// which is defined in `test_parser_errors.cpp`. We need to declare it here.
bool expect_parser_abort(const char* source_code);

TEST_FUNC(Parser_ParsePrimaryExpr_IntegerLiteral) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("123", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(node->as.integer_literal.value, 123);

    return true;
}

TEST_FUNC(Parser_BinaryExpr_SimplePrecedence) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("2 + 3 * 4", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* expr = parser.parseExpression();

    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_BINARY_OP);

    ASTBinaryOpNode* root = expr->as.binary_op;
    ASSERT_EQ(root->op, TOKEN_PLUS);

    // Left should be '2'
    ASTNode* left = root->left;
    ASSERT_EQ(left->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(left->as.integer_literal.value, 2);

    // Right should be '3 * 4'
    ASTNode* right = root->right;
    ASSERT_EQ(right->type, NODE_BINARY_OP);
    ASTBinaryOpNode* right_op = right->as.binary_op;
    ASSERT_EQ(right_op->op, TOKEN_STAR);
    ASSERT_EQ(right_op->left->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(right_op->left->as.integer_literal.value, 3);
    ASSERT_EQ(right_op->right->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(right_op->right->as.integer_literal.value, 4);

    return true;
}

TEST_FUNC(Parser_BinaryExpr_LeftAssociativity) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("10 - 4 - 2", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* expr = parser.parseExpression();

    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_BINARY_OP);

    // Root should be the second '-'
    ASTBinaryOpNode* root = expr->as.binary_op;
    ASSERT_EQ(root->op, TOKEN_MINUS);

    // Right should be '2'
    ASSERT_EQ(root->right->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(root->right->as.integer_literal.value, 2);

    // Left should be '10 - 4'
    ASTNode* left = root->left;
    ASSERT_EQ(left->type, NODE_BINARY_OP);
    ASTBinaryOpNode* left_op = left->as.binary_op;
    ASSERT_EQ(left_op->op, TOKEN_MINUS);
    ASSERT_EQ(left_op->left->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(left_op->left->as.integer_literal.value, 10);
    ASSERT_EQ(left_op->right->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(left_op->right->as.integer_literal.value, 4);

    return true;
}

TEST_FUNC(Parser_BinaryExpr_Error_MissingRHS) {
    return expect_parser_abort("10 +");
}

TEST_FUNC(Parser_ParsePrimaryExpr_FloatLiteral) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("3.14", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_FLOAT_LITERAL);
    ASSERT_EQ(node->as.float_literal.value, 3.14);

    return true;
}

TEST_FUNC(Parser_ParsePrimaryExpr_CharLiteral) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("'a'", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_CHAR_LITERAL);
    ASSERT_EQ(node->as.char_literal.value, 'a');

    return true;
}

TEST_FUNC(Parser_ParsePrimaryExpr_StringLiteral) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("\"hello\"", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_STRING_LITERAL);
    ASSERT_STREQ(node->as.string_literal.value, "hello");

    return true;
}

TEST_FUNC(Parser_ParsePrimaryExpr_Identifier) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("my_var", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_IDENTIFIER);
    ASSERT_STREQ(node->as.identifier.name, "my_var");

    return true;
}

TEST_FUNC(Parser_ParsePrimaryExpr_ParenthesizedExpression) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("(42)", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parsePrimaryExpr();

    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(node->as.integer_literal.value, 42);

    return true;
}

TEST_FUNC(Parser_Error_OnUnexpectedToken) {
    const char* source = ";"; // Semicolon is not a primary expression
    ASSERT_TRUE(expect_parser_abort(source));
    return true;
}

TEST_FUNC(Parser_FunctionCall_NoArgs) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("my_func()", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parseExpression();

    ASSERT_EQ(node->type, NODE_FUNCTION_CALL);
    ASSERT_EQ(node->as.function_call->callee->type, NODE_IDENTIFIER);
    ASSERT_STREQ(node->as.function_call->callee->as.identifier.name, "my_func");
    ASSERT_EQ(node->as.function_call->args->length(), 0);

    return true;
}

TEST_FUNC(Parser_FunctionCall_WithArgs) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("add(1, 2)", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parseExpression();

    ASSERT_EQ(node->type, NODE_FUNCTION_CALL);
    ASSERT_EQ(node->as.function_call->callee->type, NODE_IDENTIFIER);
    ASSERT_STREQ(node->as.function_call->callee->as.identifier.name, "add");
    ASSERT_EQ(node->as.function_call->args->length(), 2);
    ASSERT_EQ((*node->as.function_call->args)[0]->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ((*node->as.function_call->args)[0]->as.integer_literal.value, 1);
    ASSERT_EQ((*node->as.function_call->args)[1]->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ((*node->as.function_call->args)[1]->as.integer_literal.value, 2);

    return true;
}

TEST_FUNC(Parser_FunctionCall_WithTrailingComma) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("add(1, 2,)", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parseExpression();

    ASSERT_EQ(node->type, NODE_FUNCTION_CALL);
    ASSERT_EQ(node->as.function_call->args->length(), 2);
    ASSERT_EQ((*node->as.function_call->args)[0]->as.integer_literal.value, 1);
    ASSERT_EQ((*node->as.function_call->args)[1]->as.integer_literal.value, 2);

    return true;
}

TEST_FUNC(Parser_ArrayAccess) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("my_array[0]", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parseExpression();

    ASSERT_EQ(node->type, NODE_ARRAY_ACCESS);
    ASSERT_EQ(node->as.array_access->array->type, NODE_IDENTIFIER);
    ASSERT_STREQ(node->as.array_access->array->as.identifier.name, "my_array");
    ASSERT_EQ(node->as.array_access->index->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(node->as.array_access->index->as.integer_literal.value, 0);

    return true;
}

TEST_FUNC(Parser_ChainedPostfixOps) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("get_func()[0]", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser.parseExpression();

    ASSERT_EQ(node->type, NODE_ARRAY_ACCESS);
    ASTNode* callee = node->as.array_access->array;
    ASSERT_EQ(callee->type, NODE_FUNCTION_CALL);
    ASSERT_EQ(callee->as.function_call->callee->type, NODE_IDENTIFIER);
    ASSERT_STREQ(callee->as.function_call->callee->as.identifier.name, "get_func");

    return true;
}
