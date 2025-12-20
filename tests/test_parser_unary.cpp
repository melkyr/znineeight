#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"

#include "symbol_table.hpp"

// Helper to set up parser for a single test case
static Parser create_parser_for_test(const char* source, ArenaAllocator& arena, StringInterner& interner) {
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", source, strlen(source));

    Lexer lexer(sm, interner, arena, file_id);
    SymbolTable table(arena);
    DynamicArray<Token> tokens(arena);
    while (true) {
        Token token = lexer.nextToken();
        tokens.append(token);
        if (token.type == TOKEN_EOF) {
            break;
        }
    }
    return ParserBuilder(tokens.getData(), tokens.length(), &arena, &table).build();
}

TEST_FUNC(Parser_UnaryOp_SimpleNegation) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);

    Parser parser = create_parser_for_test("-123", arena, interner);
    ASTNode* expr = parser.parseExpression();

    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_UNARY_OP);

    ASTUnaryOpNode unary_op = expr->as.unary_op;
    ASSERT_EQ(unary_op.op, TOKEN_MINUS);

    ASTNode* operand = unary_op.operand;
    ASSERT_TRUE(operand != NULL);
    ASSERT_EQ(operand->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(operand->as.integer_literal.value, 123);

    return true;
}

TEST_FUNC(Parser_UnaryOp_ChainedNegation) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);

    Parser parser = create_parser_for_test("--123", arena, interner);
    ASTNode* expr = parser.parseExpression();

    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_UNARY_OP);

    ASTUnaryOpNode outer_unary_op = expr->as.unary_op;
    ASSERT_EQ(outer_unary_op.op, TOKEN_MINUS);

    ASTNode* inner_expr = outer_unary_op.operand;
    ASSERT_TRUE(inner_expr != NULL);
    ASSERT_EQ(inner_expr->type, NODE_UNARY_OP);

    ASTUnaryOpNode inner_unary_op = inner_expr->as.unary_op;
    ASSERT_EQ(inner_unary_op.op, TOKEN_MINUS);

    ASTNode* operand = inner_unary_op.operand;
    ASSERT_TRUE(operand != NULL);
    ASSERT_EQ(operand->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(operand->as.integer_literal.value, 123);

    return true;
}

TEST_FUNC(Parser_UnaryOp_MixedOperators) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);

    Parser parser = create_parser_for_test("!~-&foo", arena, interner);
    ASTNode* expr = parser.parseExpression();

    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_UNARY_OP); // !
    ASSERT_EQ(expr->as.unary_op.op, TOKEN_BANG);

    expr = expr->as.unary_op.operand;
    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_UNARY_OP); // ~
    ASSERT_EQ(expr->as.unary_op.op, TOKEN_TILDE);

    expr = expr->as.unary_op.operand;
    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_UNARY_OP); // -
    ASSERT_EQ(expr->as.unary_op.op, TOKEN_MINUS);

    expr = expr->as.unary_op.operand;
    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_UNARY_OP); // &
    ASSERT_EQ(expr->as.unary_op.op, TOKEN_AMPERSAND);

    ASTNode* operand = expr->as.unary_op.operand;
    ASSERT_TRUE(operand != NULL);
    ASSERT_EQ(operand->type, NODE_IDENTIFIER);
    ASSERT_STREQ(operand->as.identifier.name, "foo");

    return true;
}

TEST_FUNC(Parser_UnaryOp_WithPostfix) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);

    Parser parser = create_parser_for_test("-foo()", arena, interner);
    ASTNode* expr = parser.parseExpression();

    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_UNARY_OP);

    ASTUnaryOpNode unary_op = expr->as.unary_op;
    ASSERT_EQ(unary_op.op, TOKEN_MINUS);

    ASTNode* operand = unary_op.operand;
    ASSERT_TRUE(operand != NULL);
    ASSERT_EQ(operand->type, NODE_FUNCTION_CALL);

    ASTFunctionCallNode* call_node = operand->as.function_call;
    ASSERT_EQ(call_node->callee->type, NODE_IDENTIFIER);
    ASSERT_STREQ(call_node->callee->as.identifier.name, "foo");

    return true;
}
