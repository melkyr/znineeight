#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"

// Forward declaration for the helper function from test_parser_errors.cpp
bool expect_parser_abort(const char* source_code);

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
    return Parser(tokens.getData(), tokens.length(), &arena, &table);
}

TEST_FUNC(Parser_TryExpr_Simple) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);

    Parser parser = create_parser_for_test("try foo()", arena, interner);
    ASTNode* expr = parser.parseExpression();

    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_TRY_EXPR);

    ASTTryExprNode try_expr = expr->as.try_expr;
    ASSERT_TRUE(try_expr.expression != NULL);
    ASSERT_EQ(try_expr.expression->type, NODE_FUNCTION_CALL);

    ASTFunctionCallNode* call_node = try_expr.expression->as.function_call;
    ASSERT_EQ(call_node->callee->type, NODE_IDENTIFIER);
    ASSERT_STREQ(call_node->callee->as.identifier.name, "foo");

    return true;
}

TEST_FUNC(Parser_TryExpr_Chained) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);

    Parser parser = create_parser_for_test("try !foo()", arena, interner);
    ASTNode* expr = parser.parseExpression();

    ASSERT_TRUE(expr != NULL);
    ASSERT_EQ(expr->type, NODE_TRY_EXPR);

    ASTTryExprNode try_expr = expr->as.try_expr;
    ASSERT_TRUE(try_expr.expression != NULL);
    ASSERT_EQ(try_expr.expression->type, NODE_UNARY_OP);

    ASTUnaryOpNode unary_op = try_expr.expression->as.unary_op;
    ASSERT_EQ(unary_op.op, TOKEN_BANG);

    ASTNode* operand = unary_op.operand;
    ASSERT_TRUE(operand != NULL);
    ASSERT_EQ(operand->type, NODE_FUNCTION_CALL);

    ASTFunctionCallNode* call_node = operand->as.function_call;
    ASSERT_EQ(call_node->callee->type, NODE_IDENTIFIER);
    ASSERT_STREQ(call_node->callee->as.identifier.name, "foo");

    return true;
}

TEST_FUNC(Parser_TryExpr_InvalidSyntax) {
    // `try` must be followed by an expression.
    ASSERT_TRUE(expect_parser_abort("try;"));
    return true;
}
