#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"

#include <new>

// Helper function to set up the parser for a given source string
static Parser create_parser_for_test(const char* source, ArenaAllocator& arena, StringInterner& interner, SourceManager& sm, DynamicArray<Token>& tokens) {
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);

    while (true) {
        Token token = lexer.nextToken();
        tokens.append(token);
        if (token.type == TOKEN_EOF) {
            break;
        }
    }

    return Parser(tokens.getData(), tokens.length(), &arena);
}

TEST_FUNC(ParserIntegration_VarDeclWithBinaryExpr) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    DynamicArray<Token> tokens(arena);

    const char* source = "var x: i32 = 10 + 20;";
    Parser parser = create_parser_for_test(source, arena, interner, sm, tokens);

    ASTNode* node = parser.parseStatement();

    // 1. Check top-level node
    ASSERT_TRUE(node != NULL);
    ASSERT_TRUE(node->type == NODE_VAR_DECL);

    // 2. Check VarDeclNode details
    ASTVarDeclNode* var_decl = node->as.var_decl;
    ASSERT_TRUE(var_decl != NULL);
    ASSERT_STREQ(var_decl->name, "x");
    ASSERT_TRUE(var_decl->is_mut);
    ASSERT_TRUE(var_decl->type->type == NODE_TYPE_NAME);
    ASSERT_STREQ(var_decl->type->as.type_name.name, "i32");

    // 3. Check initializer is a binary expression
    ASTNode* initializer = var_decl->initializer;
    ASSERT_TRUE(initializer != NULL);
    ASSERT_TRUE(initializer->type == NODE_BINARY_OP);

    // 4. Check the binary expression details
    ASTBinaryOpNode* bin_op = initializer->as.binary_op;
    ASSERT_TRUE(bin_op->op == TOKEN_PLUS);

    // 5. Check the left and right operands
    ASTNode* left = bin_op->left;
    ASTNode* right = bin_op->right;
    ASSERT_TRUE(left != NULL);
    ASSERT_TRUE(right != NULL);
    ASSERT_TRUE(left->type == NODE_INTEGER_LITERAL);
    ASSERT_TRUE(right->type == NODE_INTEGER_LITERAL);
    ASSERT_EQ(left->as.integer_literal.value, 10);
    ASSERT_EQ(right->as.integer_literal.value, 20);

    return true;
}

TEST_FUNC(ParserIntegration_LogicalAndOperatorSymbol) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    DynamicArray<Token> tokens(arena);

    const char* source = "const x: bool = a && b;";
    Parser parser = create_parser_for_test(source, arena, interner, sm, tokens);

    ASTNode* node = parser.parseStatement();
    ASSERT_TRUE(node != NULL);
    ASSERT_TRUE(node->type == NODE_VAR_DECL);

    ASTVarDeclNode* var_decl = node->as.var_decl;
    ASTNode* initializer = var_decl->initializer;
    ASSERT_TRUE(initializer != NULL);
    ASSERT_TRUE(initializer->type == NODE_BINARY_OP);

    ASTBinaryOpNode* bin_op = initializer->as.binary_op;
    ASSERT_TRUE(bin_op->op == TOKEN_AMPERSAND2);

    return true;
}

TEST_FUNC(ParserIntegration_ForLoopOverSlice) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    DynamicArray<Token> tokens(arena);

    const char* source = "for (my_slice[0..4]) |item| {}";
    Parser parser = create_parser_for_test(source, arena, interner, sm, tokens);

    ASTNode* node = parser.parseStatement();

    // 1. Check top-level node
    ASSERT_TRUE(node != NULL);
    ASSERT_TRUE(node->type == NODE_FOR_STMT);

    // 2. Check ForStmtNode details
    ASTForStmtNode* for_stmt = node->as.for_stmt;
    ASSERT_TRUE(for_stmt != NULL);
    ASSERT_STREQ(for_stmt->item_name, "item");
    ASSERT_TRUE(for_stmt->index_name == NULL);
    ASSERT_TRUE(for_stmt->body != NULL);
    ASSERT_TRUE(for_stmt->body->type == NODE_BLOCK_STMT);

    // 3. Check iterable is an array slice expression
    ASTNode* iterable = for_stmt->iterable_expr;
    ASSERT_TRUE(iterable != NULL);
    ASSERT_TRUE(iterable->type == NODE_ARRAY_SLICE);

    // 4. Check array slice details
    ASTArraySliceNode* slice_node = iterable->as.array_slice;
    ASSERT_TRUE(slice_node->array != NULL);
    ASSERT_TRUE(slice_node->array->type == NODE_IDENTIFIER);
    ASSERT_STREQ(slice_node->array->as.identifier.name, "my_slice");

    // 5. Check the start and end of the slice
    ASTNode* start = slice_node->start;
    ASTNode* end = slice_node->end;
    ASSERT_TRUE(start != NULL);
    ASSERT_TRUE(end != NULL);
    ASSERT_TRUE(start->type == NODE_INTEGER_LITERAL);
    ASSERT_TRUE(end->type == NODE_INTEGER_LITERAL);
    ASSERT_EQ(start->as.integer_literal.value, 0);
    ASSERT_EQ(end->as.integer_literal.value, 4);

    return true;
}

TEST_FUNC(ParserIntegration_ComprehensiveFunction) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    DynamicArray<Token> tokens(arena);

    const char* source =
        "fn comprehensive_test() -> i32 {\n"
        "    var i: i32 = 0;\n"
        "    while (i < 10) {\n"
        "        if (i % 2 == 0) {\n"
        "            i = i + 1;\n"
        "        } else {\n"
        "            i = i + 2;\n"
        "        }\n"
        "    }\n"
        "    for (some_iterable) |item| {\n"
        "        // do nothing\n"
        "    }\n"
        "    return i;\n"
        "}\n";

    Parser parser = create_parser_for_test(source, arena, interner, sm, tokens);
    ASTNode* node = parser.parseStatement();

    // High-level checks: Just ensure it parses and has the basic structure.
    ASSERT_TRUE(node != NULL);
    ASSERT_TRUE(node->type == NODE_FN_DECL);

    ASTFnDeclNode* fn_decl = node->as.fn_decl;
    ASSERT_STREQ(fn_decl->name, "comprehensive_test");
    ASSERT_TRUE(fn_decl->return_type != NULL);
    ASSERT_TRUE(fn_decl->body != NULL);
    ASSERT_TRUE(fn_decl->body->type == NODE_BLOCK_STMT);

    // Check for the correct number of statements in the function body
    ASTBlockStmtNode* body = &fn_decl->body->as.block_stmt;
    ASSERT_EQ(body->statements->length(), 4); // var, while, for, return

    return true;
}

TEST_FUNC(ParserIntegration_WhileWithFunctionCall) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    DynamicArray<Token> tokens(arena);

    const char* source = "while (should_continue()) {}";
    Parser parser = create_parser_for_test(source, arena, interner, sm, tokens);

    ASTNode* node = parser.parseWhileStatement();

    // 1. Check top-level node
    ASSERT_TRUE(node != NULL);
    ASSERT_TRUE(node->type == NODE_WHILE_STMT);

    // 2. Check WhileStmtNode details
    ASTWhileStmtNode* while_stmt = &node->as.while_stmt;
    ASSERT_TRUE(while_stmt->body != NULL);
    ASSERT_TRUE(while_stmt->body->type == NODE_BLOCK_STMT);

    // 3. Check condition is a function call
    ASTNode* condition = while_stmt->condition;
    ASSERT_TRUE(condition != NULL);
    ASSERT_TRUE(condition->type == NODE_FUNCTION_CALL);

    // 4. Check the function call details
    ASTFunctionCallNode* call_node = condition->as.function_call;
    ASSERT_TRUE(call_node->callee != NULL);
    ASSERT_TRUE(call_node->callee->type == NODE_IDENTIFIER);
    ASSERT_STREQ(call_node->callee->as.identifier.name, "should_continue");
    ASSERT_TRUE(call_node->args != NULL);
    ASSERT_EQ(call_node->args->length(), 0);

    return true;
}

TEST_FUNC(ParserIntegration_IfWithComplexCondition) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    DynamicArray<Token> tokens(arena);

    const char* source = "if (a && (b || c)) {}";
    Parser parser = create_parser_for_test(source, arena, interner, sm, tokens);

    ASTNode* node = parser.parseIfStatement();

    // 1. Check top-level node
    ASSERT_TRUE(node != NULL);
    ASSERT_TRUE(node->type == NODE_IF_STMT);

    // 2. Check IfStmtNode details
    ASTIfStmtNode* if_stmt = node->as.if_stmt;
    ASSERT_TRUE(if_stmt != NULL);
    ASSERT_TRUE(if_stmt->then_block != NULL);
    ASSERT_TRUE(if_stmt->else_block == NULL);

    // 3. Check condition is a binary expression (&&)
    ASTNode* condition = if_stmt->condition;
    ASSERT_TRUE(condition != NULL);
    ASSERT_TRUE(condition->type == NODE_BINARY_OP);

    // 4. Check the '&&' expression details
    ASTBinaryOpNode* and_op = condition->as.binary_op;
    ASSERT_TRUE(and_op->op == TOKEN_AND);

    // 5. Check left operand of '&&' is identifier 'a'
    ASTNode* and_left = and_op->left;
    ASSERT_TRUE(and_left != NULL);
    ASSERT_TRUE(and_left->type == NODE_IDENTIFIER);
    ASSERT_STREQ(and_left->as.identifier.name, "a");

    // 6. Check right operand of '&&' is another binary op (||)
    ASTNode* and_right = and_op->right;
    ASSERT_TRUE(and_right != NULL);
    ASSERT_TRUE(and_right->type == NODE_BINARY_OP);

    // 7. Check the '||' expression details
    ASTBinaryOpNode* or_op = and_right->as.binary_op;
    ASSERT_TRUE(or_op->op == TOKEN_OR);

    // 8. Check operands of '||' are identifiers 'b' and 'c'
    ASTNode* or_left = or_op->left;
    ASTNode* or_right = or_op->right;
    ASSERT_TRUE(or_left != NULL);
    ASSERT_TRUE(or_right != NULL);
    ASSERT_TRUE(or_left->type == NODE_IDENTIFIER);
    ASSERT_TRUE(or_right->type == NODE_IDENTIFIER);
    ASSERT_STREQ(or_left->as.identifier.name, "b");
    ASSERT_STREQ(or_right->as.identifier.name, "c");

    return true;
}
