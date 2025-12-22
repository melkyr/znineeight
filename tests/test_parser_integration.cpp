#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include <new>

// Helper function from test_parser_errors.cpp
bool expect_parser_abort(const char* source);

TEST_FUNC(ParserIntegration_VarDeclWithBinaryExpr) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source = "var x: i32 = 10 + 20;";
    ParserTestContext ctx(source, arena, interner);
    Parser& parser = ctx.getParser();

    ASTNode* node = parser.parseVarDecl();

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

TEST_FUNC(ParserIntegration_LogicalAnd) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    // Test with '&&'
    {
        const char* source = "if (a && b) {}";
        ParserTestContext ctx(source, arena, interner);
        Parser& parser = ctx.getParser();
        ASTNode* node = parser.parseIfStatement();
        ASSERT_TRUE(node != NULL);
        ASTIfStmtNode* if_stmt = node->as.if_stmt;
        ASSERT_TRUE(if_stmt->condition->type == NODE_BINARY_OP);
        ASSERT_TRUE(if_stmt->condition->as.binary_op->op == TOKEN_AMPERSAND2);
    }

    // Test that 'and' is not a valid logical operator and causes a parser error.
    ASSERT_TRUE(expect_parser_abort("a and b"));

    return true;
}

TEST_FUNC(ParserIntegration_DeferStatement) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source = "defer file.close();";
    ParserTestContext ctx(source, arena, interner);
    Parser& parser = ctx.getParser();

    ASTNode* node = parser.parseDeferStatement();

    ASSERT_TRUE(node != NULL);
    ASSERT_TRUE(node->type == NODE_DEFER_STMT);

    ASTDeferStmtNode* defer_stmt = &node->as.defer_stmt;
    ASSERT_TRUE(defer_stmt->statement != NULL);
    ASSERT_TRUE(defer_stmt->statement->type == NODE_FUNCTION_CALL);

    ASTFunctionCallNode* call_node = defer_stmt->statement->as.function_call;
    ASSERT_TRUE(call_node->callee != NULL);
    ASSERT_TRUE(call_node->callee->type == NODE_BINARY_OP); // member access is a binary op

    ASTBinaryOpNode* member_access = call_node->callee->as.binary_op;
    ASSERT_TRUE(member_access->op == TOKEN_DOT);
    ASSERT_TRUE(member_access->left->type == NODE_IDENTIFIER);
    ASSERT_STREQ(member_access->left->as.identifier.name, "file");
    ASSERT_TRUE(member_access->right->type == NODE_IDENTIFIER);
    ASSERT_STREQ(member_access->right->as.identifier.name, "close");

    return true;
}

TEST_FUNC(ParserIntegration_StructDeclaration) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source = "const MyStruct = struct { a: i32, b: bool, };";
    ParserTestContext ctx(source, arena, interner);
    Parser& parser = ctx.getParser();

    ASTNode* node = parser.parseVarDecl();

    ASSERT_TRUE(node != NULL);
    ASSERT_TRUE(node->type == NODE_VAR_DECL);

    ASTVarDeclNode* var_decl = node->as.var_decl;
    ASSERT_TRUE(var_decl != NULL);
    ASSERT_STREQ(var_decl->name, "MyStruct");
    ASSERT_TRUE(var_decl->is_const);
    ASSERT_TRUE(var_decl->initializer == NULL);

    ASTNode* type_node = var_decl->type;
    ASSERT_TRUE(type_node != NULL);
    ASSERT_TRUE(type_node->type == NODE_STRUCT_DECL);

    ASTStructDeclNode* struct_decl = type_node->as.struct_decl;
    ASSERT_TRUE(struct_decl != NULL);
    ASSERT_EQ(struct_decl->fields->length(), 2);

    // Field 1: a: i32
    ASTStructFieldNode* field1 = (*struct_decl->fields)[0]->as.struct_field;
    ASSERT_STREQ(field1->name, "a");
    ASSERT_TRUE(field1->type->type == NODE_TYPE_NAME);
    ASSERT_STREQ(field1->type->as.type_name.name, "i32");

    // Field 2: b: bool
    ASTStructFieldNode* field2 = (*struct_decl->fields)[1]->as.struct_field;
    ASSERT_STREQ(field2->name, "b");
    ASSERT_TRUE(field2->type->type == NODE_TYPE_NAME);
    ASSERT_STREQ(field2->type->as.type_name.name, "bool");

    return true;
}

TEST_FUNC(ParserIntegration_SwitchExpression) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "const x = switch (value) {\n"
        "    1 => 10,\n"
        "    2, 3 => 20,\n"
        "    else => 30,\n"
        "};\n";
    ParserTestContext ctx(source, arena, interner);
    Parser& parser = ctx.getParser();

    ASTNode* node = parser.parseVarDecl();

    ASSERT_TRUE(node != NULL);
    ASSERT_TRUE(node->type == NODE_VAR_DECL);

    ASTVarDeclNode* var_decl = node->as.var_decl;
    ASSERT_TRUE(var_decl != NULL);

    ASTNode* switch_node = var_decl->initializer;
    ASSERT_TRUE(switch_node != NULL);
    ASSERT_TRUE(switch_node->type == NODE_SWITCH_EXPR);

    ASTSwitchExprNode* switch_expr = switch_node->as.switch_expr;
    ASSERT_TRUE(switch_expr != NULL);
    ASSERT_TRUE(switch_expr->expression->type == NODE_IDENTIFIER);
    ASSERT_STREQ(switch_expr->expression->as.identifier.name, "value");

    ASSERT_EQ(switch_expr->prongs->length(), 3);

    // Prong 1: 1 => return 10
    ASTSwitchProngNode* prong1 = (*switch_expr->prongs)[0];
    ASSERT_FALSE(prong1->is_else);
    ASSERT_EQ(prong1->cases->length(), 1);
    ASSERT_TRUE((*prong1->cases)[0]->type == NODE_INTEGER_LITERAL);
    ASSERT_EQ((*prong1->cases)[0]->as.integer_literal.value, 1);
    ASSERT_TRUE(prong1->body->type == NODE_RETURN_STMT);

    // Prong 2: 2, 3 => return 20
    ASTSwitchProngNode* prong2 = (*switch_expr->prongs)[1];
    ASSERT_FALSE(prong2->is_else);
    ASSERT_EQ(prong2->cases->length(), 2);
    ASSERT_TRUE((*prong2->cases)[0]->type == NODE_INTEGER_LITERAL);
    ASSERT_EQ((*prong2->cases)[0]->as.integer_literal.value, 2);
    ASSERT_TRUE((*prong2->cases)[1]->type == NODE_INTEGER_LITERAL);
    ASSERT_EQ((*prong2->cases)[1]->as.integer_literal.value, 3);
    ASSERT_TRUE(prong2->body->type == NODE_RETURN_STMT);

    // Prong 3: else => return 30
    ASTSwitchProngNode* prong3 = (*switch_expr->prongs)[2];
    ASSERT_TRUE(prong3->is_else);
    ASSERT_TRUE(prong3->cases == NULL);
    ASSERT_TRUE(prong3->body->type == NODE_RETURN_STMT);

    return true;
}

TEST_FUNC(ParserIntegration_ForLoopOverSlice) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    // This is a guess at the slice syntax, as it's not fully documented.
    const char* source = "for (my_slice[0..4]) |item| {}";
    ParserTestContext ctx(source, arena, interner);
    Parser& parser = ctx.getParser();

    ASTNode* node = parser.parseForStatement();

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

    // 3. Check iterable is an array access expression
    ASTNode* iterable = for_stmt->iterable_expr;
    ASSERT_TRUE(iterable != NULL);
    ASSERT_TRUE(iterable->type == NODE_ARRAY_ACCESS);

    // 4. Check array access details
    ASTArrayAccessNode* access_node = iterable->as.array_access;
    ASSERT_TRUE(access_node->array != NULL);
    ASSERT_TRUE(access_node->array->type == NODE_IDENTIFIER);
    ASSERT_STREQ(access_node->array->as.identifier.name, "my_slice");

    // 5. Check index is a binary op (..)
    ASTNode* index_expr = access_node->index;
    ASSERT_TRUE(index_expr != NULL);
    ASSERT_TRUE(index_expr->type == NODE_BINARY_OP);

    ASTBinaryOpNode* range_op = index_expr->as.binary_op;
    ASSERT_TRUE(range_op->op == TOKEN_RANGE);

    ASTNode* left = range_op->left;
    ASTNode* right = range_op->right;
    ASSERT_TRUE(left != NULL);
    ASSERT_TRUE(right != NULL);
    ASSERT_TRUE(left->type == NODE_INTEGER_LITERAL);
    ASSERT_TRUE(right->type == NODE_INTEGER_LITERAL);
    ASSERT_EQ(left->as.integer_literal.value, 0);
    ASSERT_EQ(right->as.integer_literal.value, 4);

    return true;
}

TEST_FUNC(ParserIntegration_ComprehensiveFunction) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

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

    ParserTestContext ctx(source, arena, interner);
    Parser& parser = ctx.getParser();
    ASTNode* node = parser.parseFnDecl();

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
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source = "while (should_continue()) {}";
    ParserTestContext ctx(source, arena, interner);
    Parser& parser = ctx.getParser();

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
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source = "if (a && (b || c)) {}";
    ParserTestContext ctx(source, arena, interner);
    Parser& parser = ctx.getParser();

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
