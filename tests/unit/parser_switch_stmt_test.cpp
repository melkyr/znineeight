#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include <cstdlib>

TEST_FUNC(Parser_SwitchStatement_Basic) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("switch (x) { 1 => { foo(); }, else => { bar(); } }", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseStatement();
    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_SWITCH_STMT);

    ASTSwitchStmtNode* switch_node = node->as.switch_stmt;
    ASSERT_EQ(switch_node->expression->type, NODE_IDENTIFIER);
    ASSERT_EQ(switch_node->prongs->length(), 2);

    // Prong 1: 1 => { foo(); }
    ASTSwitchStmtProngNode* prong1 = (*switch_node->prongs)[0];
    ASSERT_TRUE(!prong1->is_else);
    ASSERT_EQ(prong1->items->length(), 1);
    ASSERT_EQ((*prong1->items)[0]->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(prong1->body->type, NODE_BLOCK_STMT);

    // Prong 2: else => { bar(); }
    ASTSwitchStmtProngNode* prong2 = (*switch_node->prongs)[1];
    ASSERT_TRUE(prong2->is_else);
    ASSERT_EQ(prong2->body->type, NODE_BLOCK_STMT);

    return true;
}

TEST_FUNC(Parser_Switch_ExpressionContext) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("var x = switch (y) { else => 42 };", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseStatement();
    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_VAR_DECL);

    ASTNode* init = node->as.var_decl->initializer;
    ASSERT_TRUE(init != NULL);
    ASSERT_EQ(init->type, NODE_SWITCH_EXPR);

    return true;
}

TEST_FUNC(Parser_Switch_InclusiveRange) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("switch (x) { 1...10 => {}, else => {}, }", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseStatement();
    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_SWITCH_STMT);

    ASTSwitchStmtNode* switch_node = node->as.switch_stmt;
    ASTSwitchStmtProngNode* prong1 = (*switch_node->prongs)[0];
    ASSERT_EQ(prong1->items->length(), 1);

    ASTNode* item = (*prong1->items)[0];
    ASSERT_EQ(item->type, NODE_RANGE);
    ASSERT_TRUE(item->as.range->is_inclusive);
    ASSERT_EQ(item->as.range->start->as.integer_literal.value, (u64)1);
    ASSERT_EQ(item->as.range->end->as.integer_literal.value, (u64)10);

    return true;
}

TEST_FUNC(Parser_Switch_ExclusiveRange) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("switch (x) { 1..10 => {}, else => {}, }", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseStatement();
    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_SWITCH_STMT);

    ASTSwitchStmtNode* switch_node = node->as.switch_stmt;
    ASTSwitchStmtProngNode* prong1 = (*switch_node->prongs)[0];

    ASTNode* item = (*prong1->items)[0];
    ASSERT_EQ(item->type, NODE_RANGE);
    ASSERT_TRUE(!item->as.range->is_inclusive);
    ASSERT_EQ(item->as.range->start->as.integer_literal.value, (u64)1);
    ASSERT_EQ(item->as.range->end->as.integer_literal.value, (u64)10);

    return true;
}

TEST_FUNC(Parser_Switch_MixedItems) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx("switch (x) { 1, 3...5, 10 => {}, else => {}, }", arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseStatement();
    ASSERT_TRUE(node != NULL);
    ASTSwitchStmtNode* switch_node = node->as.switch_stmt;
    ASTSwitchStmtProngNode* prong1 = (*switch_node->prongs)[0];

    ASSERT_EQ(prong1->items->length(), 3);
    ASSERT_EQ((*prong1->items)[0]->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ((*prong1->items)[1]->type, NODE_RANGE);
    ASSERT_EQ((*prong1->items)[2]->type, NODE_INTEGER_LITERAL);

    return true;
}

#ifndef RETROZIG_TEST
int main() {
    int passed = 0;
    int total = 0;

    total++; if (test_Parser_SwitchStatement_Basic()) passed++;
    total++; if (test_Parser_Switch_InclusiveRange()) passed++;
    total++; if (test_Parser_Switch_ExclusiveRange()) passed++;
    total++; if (test_Parser_Switch_MixedItems()) passed++;

    printf("Switch Parser Tests: %d/%d passed\n", passed, total);
    return (passed == total) ? 0 : 1;
}
#endif
