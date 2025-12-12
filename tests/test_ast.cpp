#include "test_framework.hpp"
#include "ast.hpp"
#include "memory.hpp"

// Test to verify the creation and initialization of an Integer Literal AST node.
TEST_FUNC(ASTNode_IntegerLiteral)
{
    ArenaAllocator arena(1024);
    ASTNode* node = (ASTNode*)arena.alloc(sizeof(ASTNode));

    node->type = NODE_INTEGER_LITERAL;
    node->loc.file_id = 1;
    node->loc.line = 10;
    node->loc.column = 5;
    node->as.integer_literal.value = 42;

    ASSERT_EQ(node->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(node->loc.file_id, 1);
    ASSERT_EQ(node->loc.line, 10);
    ASSERT_EQ(node->loc.column, 5);
    ASSERT_EQ(node->as.integer_literal.value, 42);

    return true;
}

// Test to verify the creation and initialization of a Float Literal AST node.
TEST_FUNC(ASTNode_FloatLiteral)
{
    ArenaAllocator arena(1024);
    ASTNode* node = (ASTNode*)arena.alloc(sizeof(ASTNode));

    node->type = NODE_FLOAT_LITERAL;
    node->loc.line = 1;
    node->as.float_literal.value = 3.14;

    ASSERT_EQ(node->type, NODE_FLOAT_LITERAL);
    ASSERT_EQ(node->loc.line, 1);
    ASSERT_TRUE(node->as.float_literal.value > 3.1 && node->as.float_literal.value < 3.2);

    return true;
}

// Test to verify the creation and initialization of a Character Literal AST node.
TEST_FUNC(ASTNode_CharLiteral)
{
    ArenaAllocator arena(1024);
    ASTNode* node = (ASTNode*)arena.alloc(sizeof(ASTNode));

    node->type = NODE_CHAR_LITERAL;
    node->loc.line = 2;
    node->as.char_literal.value = 'z';

    ASSERT_EQ(node->type, NODE_CHAR_LITERAL);
    ASSERT_EQ(node->loc.line, 2);
    ASSERT_EQ(node->as.char_literal.value, 'z');

    return true;
}

// Test to verify the creation and initialization of a String Literal AST node.
TEST_FUNC(ASTNode_StringLiteral)
{
    ArenaAllocator arena(1024);
    ASTNode* node = (ASTNode*)arena.alloc(sizeof(ASTNode));

    const char* test_string = "hello world";
    node->type = NODE_STRING_LITERAL;
    node->loc.line = 3;
    node->as.string_literal.value = test_string;

    ASSERT_EQ(node->type, NODE_STRING_LITERAL);
    ASSERT_EQ(node->loc.line, 3);
    ASSERT_STREQ(node->as.string_literal.value, "hello world");

    return true;
}

// Test to verify the creation and initialization of an Identifier AST node.
TEST_FUNC(ASTNode_Identifier)
{
    ArenaAllocator arena(1024);
    ASTNode* node = (ASTNode*)arena.alloc(sizeof(ASTNode));

    const char* var_name = "my_variable";
    node->type = NODE_IDENTIFIER;
    node->loc.line = 4;
    node->as.identifier.name = var_name;

    ASSERT_EQ(node->type, NODE_IDENTIFIER);
    ASSERT_EQ(node->loc.line, 4);
    ASSERT_STREQ(node->as.identifier.name, "my_variable");

    return true;
}

// Test to verify the structure of a Unary Operation AST node.
TEST_FUNC(ASTNode_UnaryOp)
{
    ArenaAllocator arena(1024);
    ASTNode* node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    ASTNode* operand = (ASTNode*)arena.alloc(sizeof(ASTNode));

    // Pretend the operand is an integer literal
    operand->type = NODE_INTEGER_LITERAL;
    operand->as.integer_literal.value = 100;

    node->type = NODE_UNARY_OP;
    node->loc.line = 5;
    node->as.unary_op.op = TOKEN_MINUS;
    node->as.unary_op.operand = operand;

    ASSERT_EQ(node->type, NODE_UNARY_OP);
    ASSERT_EQ(node->as.unary_op.op, TOKEN_MINUS);
    ASSERT_TRUE(node->as.unary_op.operand != NULL);
    ASSERT_EQ(node->as.unary_op.operand->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(node->as.unary_op.operand->as.integer_literal.value, 100);

    return true;
}

// Test to verify the structure of a Binary Operation AST node.
TEST_FUNC(ASTNode_BinaryOp)
{
    ArenaAllocator arena(1024);
    ASTNode* node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    ASTNode* left = (ASTNode*)arena.alloc(sizeof(ASTNode));
    ASTNode* right = (ASTNode*)arena.alloc(sizeof(ASTNode));

    // Pretend left and right are identifiers
    left->type = NODE_IDENTIFIER;
    left->as.identifier.name = "a";
    right->type = NODE_IDENTIFIER;
    right->as.identifier.name = "b";

    node->type = NODE_BINARY_OP;
    node->loc.line = 6;
    node->as.binary_op.op = TOKEN_PLUS;
    node->as.binary_op.left = left;
    node->as.binary_op.right = right;

    ASSERT_EQ(node->type, NODE_BINARY_OP);
    ASSERT_EQ(node->as.binary_op.op, TOKEN_PLUS);
    ASSERT_TRUE(node->as.binary_op.left != NULL);
    ASSERT_TRUE(node->as.binary_op.right != NULL);
    ASSERT_STREQ(node->as.binary_op.left->as.identifier.name, "a");
    ASSERT_STREQ(node->as.binary_op.right->as.identifier.name, "b");

    return true;
}
