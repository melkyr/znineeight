#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"
#include <cstdlib>

// Helper function to create a parser for a given source string.
// This is a simplified version of what's in other test files.
static Parser create_parser_for_test(const char* source, ArenaAllocator& arena, StringInterner& interner) {
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", source, strlen(source));

    Lexer lexer(sm, interner, arena, file_id);
    DynamicArray<Token> tokens(arena);
    Token token;
    do {
        token = lexer.nextToken();
        tokens.append(token);
    } while (token.type != TOKEN_EOF);

    return Parser(tokens.getData(), tokens.length(), &arena);
}


TEST_FUNC(Parser_SwitchExpression_Basic) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("switch (x) { 1 => 10, else => 20 }", arena, interner);

    ASTNode* node = parser.parseExpression();
    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_SWITCH_EXPR);

    ASTSwitchExprNode* switch_node = node->as.switch_expr;
    ASSERT_EQ(switch_node->expression->type, NODE_IDENTIFIER);
    ASSERT_EQ(switch_node->prongs->length(), 2);

    // Prong 1: 1 => 10
    ASTSwitchProngNode* prong1 = (*switch_node->prongs)[0];
    ASSERT_TRUE(!prong1->is_else);
    ASSERT_EQ(prong1->cases->length(), 1);
    ASSERT_EQ((*prong1->cases)[0]->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ((*prong1->cases)[0]->as.integer_literal.value, 1);
    ASSERT_EQ(prong1->body->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(prong1->body->as.integer_literal.value, 10);

    // Prong 2: else => 20
    ASTSwitchProngNode* prong2 = (*switch_node->prongs)[1];
    ASSERT_TRUE(prong2->is_else);
    ASSERT_EQ(prong2->cases->length(), 0);
    ASSERT_EQ(prong2->body->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(prong2->body->as.integer_literal.value, 20);

    return true;
}

TEST_FUNC(Parser_SwitchExpression_MultiCaseProng) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test("switch (y) { 1, 2, 3 => 42, else => 0 }", arena, interner);

    ASTNode* node = parser.parseExpression();
    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_SWITCH_EXPR);

    ASTSwitchExprNode* switch_node = node->as.switch_expr;
    ASSERT_EQ(switch_node->prongs->length(), 2);

    // Prong 1: 1, 2, 3 => 42
    ASTSwitchProngNode* prong1 = (*switch_node->prongs)[0];
    ASSERT_TRUE(!prong1->is_else);
    ASSERT_EQ(prong1->cases->length(), 3);
    ASSERT_EQ((*prong1->cases)[0]->as.integer_literal.value, 1);
    ASSERT_EQ((*prong1->cases)[1]->as.integer_literal.value, 2);
    ASSERT_EQ((*prong1->cases)[2]->as.integer_literal.value, 3);
    ASSERT_EQ(prong1->body->as.integer_literal.value, 42);

    return true;
}

TEST_FUNC(Parser_SwitchExpression_Nested) {
    const char* source = "switch (a) { 1 => switch (b) { 10 => 100, else => 200 }, else => 300 }";
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    Parser parser = create_parser_for_test(source, arena, interner);

    ASTNode* node = parser.parseExpression();
    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_SWITCH_EXPR);

    ASTSwitchExprNode* outer_switch = node->as.switch_expr;
    ASSERT_EQ(outer_switch->prongs->length(), 2);

    // Prong 1: 1 => switch (b) { ... }
    ASTSwitchProngNode* prong1 = (*outer_switch->prongs)[0];
    ASSERT_EQ(prong1->body->type, NODE_SWITCH_EXPR);

    ASTSwitchExprNode* inner_switch = prong1->body->as.switch_expr;
    ASSERT_EQ(inner_switch->expression->type, NODE_IDENTIFIER);
    ASSERT_STREQ(inner_switch->expression->as.identifier.name, "b");
    ASSERT_EQ(inner_switch->prongs->length(), 2);
    ASSERT_EQ((*inner_switch->prongs)[0]->body->as.integer_literal.value, 100);

    return true;
}

TEST_FUNC(Parser_SwitchExpression_Error_MissingLParen) {
    ASSERT_TRUE(expect_parser_abort("switch x) { 1 => 1 }"));
    return true;
}

TEST_FUNC(Parser_SwitchExpression_Error_MissingRParen) {
    ASSERT_TRUE(expect_parser_abort("switch (x { 1 => 1 }"));
    return true;
}

TEST_FUNC(Parser_SwitchExpression_Error_MissingLBrace) {
    ASSERT_TRUE(expect_parser_abort("switch (x) 1 => 1 }"));
    return true;
}

TEST_FUNC(Parser_SwitchExpression_Error_MissingFatArrow) {
    ASSERT_TRUE(expect_parser_abort("switch (x) { 1 1 }"));
    return true;
}

TEST_FUNC(Parser_SwitchExpression_Error_MissingBody) {
    // Note: The current parser design might see the comma as part of the case.
    // Let's test for `case => ,`
    ASSERT_TRUE(expect_parser_abort("switch (x) { 1 => , }"));
    return true;
}

TEST_FUNC(Parser_SwitchExpression_Error_DuplicateElse) {
    ASSERT_TRUE(expect_parser_abort("switch (x) { else => 1, else => 2 }"));
    return true;
}

TEST_FUNC(Parser_SwitchExpression_Error_EmptyBody) {
    ASSERT_TRUE(expect_parser_abort("switch (x) {}"));
    return true;
}
