#include "test_framework.hpp"
#include "lexer.hpp"
#include "parser.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include <cstring> // For strcmp

#include "symbol_table.hpp"

// Helper function to set up a parser for a given source string
static Parser create_parser_for_test(const char* source, ArenaAllocator& arena, StringInterner& interner) {
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);
    SymbolTable table(arena);

    DynamicArray<Token> tokens(arena);
    Token token;
    do {
        token = lexer.nextToken();
        tokens.append(token);
    } while (token.type != TOKEN_EOF);

    return Parser(tokens.getData(), tokens.length(), &arena, &table);
}

TEST_FUNC(Parser_BitwiseExpr_SimpleAnd) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("a & b", arena, interner);
    ASTNode* expr = parser.parseExpression();

    ASSERT_EQ(expr->type, NODE_BINARY_OP);
    ASTBinaryOpNode* root = expr->as.binary_op;
    ASSERT_EQ(root->op, TOKEN_AMPERSAND);
    ASSERT_EQ(root->left->type, NODE_IDENTIFIER);
    ASSERT_STREQ(root->left->as.identifier.name, "a");
    ASSERT_EQ(root->right->type, NODE_IDENTIFIER);
    ASSERT_STREQ(root->right->as.identifier.name, "b");

    return true;
}

TEST_FUNC(Parser_BitwiseExpr_Precedence_AdditionAndBitwiseAnd) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("a + b & c", arena, interner);
    ASTNode* expr = parser.parseExpression();

    ASSERT_EQ(expr->type, NODE_BINARY_OP);
    ASTBinaryOpNode* root = expr->as.binary_op;
    ASSERT_EQ(root->op, TOKEN_AMPERSAND);

    // Right operand should be 'c'
    ASSERT_EQ(root->right->type, NODE_IDENTIFIER);
    ASSERT_STREQ(root->right->as.identifier.name, "c");

    // Left operand should be 'a + b'
    ASTNode* left = root->left;
    ASSERT_EQ(left->type, NODE_BINARY_OP);
    ASTBinaryOpNode* left_op = left->as.binary_op;
    ASSERT_EQ(left_op->op, TOKEN_PLUS);
    ASSERT_EQ(left_op->left->type, NODE_IDENTIFIER);
    ASSERT_STREQ(left_op->left->as.identifier.name, "a");
    ASSERT_EQ(left_op->right->type, NODE_IDENTIFIER);
    ASSERT_STREQ(left_op->right->as.identifier.name, "b");

    return true;
}

TEST_FUNC(Parser_BitwiseExpr_Precedence_BitwiseAndAndShift) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("a & b << c", arena, interner);
    ASTNode* expr = parser.parseExpression();

    ASSERT_EQ(expr->type, NODE_BINARY_OP);
    ASTBinaryOpNode* root = expr->as.binary_op;
    ASSERT_EQ(root->op, TOKEN_AMPERSAND);

    // Left operand should be 'a'
    ASSERT_EQ(root->left->type, NODE_IDENTIFIER);
    ASSERT_STREQ(root->left->as.identifier.name, "a");

    // Right operand should be 'b << c'
    ASTNode* right = root->right;
    ASSERT_EQ(right->type, NODE_BINARY_OP);
    ASTBinaryOpNode* right_op = right->as.binary_op;
    ASSERT_EQ(right_op->op, TOKEN_LARROW2);
    ASSERT_EQ(right_op->left->type, NODE_IDENTIFIER);
    ASSERT_STREQ(right_op->left->as.identifier.name, "b");
    ASSERT_EQ(right_op->right->type, NODE_IDENTIFIER);
    ASSERT_STREQ(right_op->right->as.identifier.name, "c");

    return true;
}

TEST_FUNC(Parser_BitwiseExpr_Associativity_Xor) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("a ^ b ^ c", arena, interner);
    ASTNode* expr = parser.parseExpression();

    ASSERT_EQ(expr->type, NODE_BINARY_OP);
    ASTBinaryOpNode* root = expr->as.binary_op;
    ASSERT_EQ(root->op, TOKEN_CARET);

    // Right should be 'c'
    ASSERT_EQ(root->right->type, NODE_IDENTIFIER);
    ASSERT_STREQ(root->right->as.identifier.name, "c");

    // Left should be 'a ^ b'
    ASTNode* left = root->left;
    ASSERT_EQ(left->type, NODE_BINARY_OP);
    ASTBinaryOpNode* left_op = left->as.binary_op;
    ASSERT_EQ(left_op->op, TOKEN_CARET);
    ASSERT_EQ(left_op->left->type, NODE_IDENTIFIER);
    ASSERT_STREQ(left_op->left->as.identifier.name, "a");
    ASSERT_EQ(left_op->right->type, NODE_IDENTIFIER);
    ASSERT_STREQ(left_op->right->as.identifier.name, "b");

    return true;
}

TEST_FUNC(Parser_BitwiseExpr_ComplexExpression) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("a | b & c ^ d << 1", arena, interner);
    ASTNode* expr = parser.parseExpression();

    // Expected structure: (a | (b & (c ^ (d << 1))))

    ASSERT_EQ(expr->type, NODE_BINARY_OP);
    ASTBinaryOpNode* root = expr->as.binary_op; // |
    ASSERT_EQ(root->op, TOKEN_PIPE);
    ASSERT_STREQ(root->left->as.identifier.name, "a");

    ASTNode* r1 = root->right; // &
    ASSERT_EQ(r1->type, NODE_BINARY_OP);
    ASTBinaryOpNode* r1_op = r1->as.binary_op;
    ASSERT_EQ(r1_op->op, TOKEN_AMPERSAND);
    ASSERT_STREQ(r1_op->left->as.identifier.name, "b");

    ASTNode* r2 = r1_op->right; // ^
    ASSERT_EQ(r2->type, NODE_BINARY_OP);
    ASTBinaryOpNode* r2_op = r2->as.binary_op;
    ASSERT_EQ(r2_op->op, TOKEN_CARET);
    ASSERT_STREQ(r2_op->left->as.identifier.name, "c");

    ASTNode* r3 = r2_op->right; // <<
    ASSERT_EQ(r3->type, NODE_BINARY_OP);
    ASTBinaryOpNode* r3_op = r3->as.binary_op;
    ASSERT_EQ(r3_op->op, TOKEN_LARROW2);
    ASSERT_STREQ(r3_op->left->as.identifier.name, "d");
    ASSERT_EQ(r3_op->right->as.integer_literal.value, 1);

    return true;
}

TEST_FUNC(Parser_BitwiseExpr_ComparisonPrecedence) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("a & b == 0", arena, interner);
    ASTNode* expr = parser.parseExpression();

    // Expected structure: ((a & b) == 0)

    ASSERT_EQ(expr->type, NODE_BINARY_OP);
    ASTBinaryOpNode* root = expr->as.binary_op; // ==
    ASSERT_EQ(root->op, TOKEN_EQUAL_EQUAL);
    ASSERT_EQ(root->right->as.integer_literal.value, 0);

    ASTNode* left = root->left; // &
    ASSERT_EQ(left->type, NODE_BINARY_OP);
    ASTBinaryOpNode* left_op = left->as.binary_op;
    ASSERT_EQ(left_op->op, TOKEN_AMPERSAND);
    ASSERT_STREQ(left_op->left->as.identifier.name, "a");
    ASSERT_STREQ(left_op->right->as.identifier.name, "b");

    return true;
}
