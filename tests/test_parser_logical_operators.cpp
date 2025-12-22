#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"
#include <cstdlib> // For abort
#include <new>     // For placement new

#if defined(_WIN32)
#include <windows.h>
#else
#include <sys/wait.h>
#include <unistd.h>
#endif

// --- Test Helper Functions ---

#include "symbol_table.hpp"

static Parser create_parser_for_test(
    const char* source,
    ArenaAllocator& arena,
    StringInterner& interner,
    SourceManager& src_manager) {

    u32 file_id = src_manager.addFile("test.zig", source, strlen(source));
    Lexer lexer(src_manager, interner, arena, file_id);
    SymbolTable table(arena);
    DynamicArray<Token> tokens(arena);
    for (Token token = lexer.nextToken(); token.type != TOKEN_EOF; token = lexer.nextToken()) {
        tokens.append(token);
    }
    tokens.append(lexer.nextToken());
    return Parser(tokens.getData(), tokens.length(), &arena, &table);
}

static bool verify_binary_op(ASTNode* node, TokenType op, const char* left_name, const char* right_name) {
    ASSERT_TRUE(node->type == NODE_BINARY_OP);
    ASSERT_TRUE(node->as.binary_op->op == op);
    ASSERT_TRUE(node->as.binary_op->left->type == NODE_IDENTIFIER);
    ASSERT_STREQ(node->as.binary_op->left->as.identifier.name, left_name);
    ASSERT_TRUE(node->as.binary_op->right->type == NODE_IDENTIFIER);
    ASSERT_STREQ(node->as.binary_op->right->as.identifier.name, right_name);
    return true;
}



// --- Test Cases ---

TEST_FUNC(Parser_Logical_AndHasHigherPrecedenceThanOr) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager src_manager(arena);
    Parser parser = create_parser_for_test("a and b or c", arena, interner, src_manager);

    ASTNode* expr = parser.parseExpression();

    // Expected: (a and b) or c
    ASSERT_TRUE(expr->type == NODE_BINARY_OP);
    ASSERT_TRUE(expr->as.binary_op->op == TOKEN_OR);

    ASTNode* left_of_or = expr->as.binary_op->left;
    verify_binary_op(left_of_or, TOKEN_AND, "a", "b");

    ASSERT_TRUE(expr->as.binary_op->right->type == NODE_IDENTIFIER);
    ASSERT_STREQ(expr->as.binary_op->right->as.identifier.name, "c");

    return true;
}

TEST_FUNC(Parser_Logical_AndBindsTighterThanOr) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager src_manager(arena);
    Parser parser = create_parser_for_test("a or b and c", arena, interner, src_manager);

    ASTNode* expr = parser.parseExpression();

    // Expected: a or (b and c)
    ASSERT_TRUE(expr->type == NODE_BINARY_OP);
    ASSERT_TRUE(expr->as.binary_op->op == TOKEN_OR);

    ASSERT_TRUE(expr->as.binary_op->left->type == NODE_IDENTIFIER);
    ASSERT_STREQ(expr->as.binary_op->left->as.identifier.name, "a");

    ASTNode* right_of_or = expr->as.binary_op->right;
    verify_binary_op(right_of_or, TOKEN_AND, "b", "c");

    return true;
}

TEST_FUNC(Parser_Logical_OrHasHigherPrecedenceThanOrElse) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager src_manager(arena);
    Parser parser = create_parser_for_test("x orelse y or z", arena, interner, src_manager);

    ASTNode* expr = parser.parseExpression();

    // Expected: x orelse (y or z)
    ASSERT_TRUE(expr->type == NODE_BINARY_OP);
    ASSERT_TRUE(expr->as.binary_op->op == TOKEN_ORELSE);

    ASSERT_TRUE(expr->as.binary_op->left->type == NODE_IDENTIFIER);
    ASSERT_STREQ(expr->as.binary_op->left->as.identifier.name, "x");

    ASTNode* right_of_orelse = expr->as.binary_op->right;
    verify_binary_op(right_of_orelse, TOKEN_OR, "y", "z");

    return true;
}

TEST_FUNC(Parser_Logical_AndIsLeftAssociative) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager src_manager(arena);
    Parser parser = create_parser_for_test("a and b and c", arena, interner, src_manager);

    ASTNode* expr = parser.parseExpression();

    // Expected: ((a and b) and c)
    ASSERT_TRUE(expr->type == NODE_BINARY_OP);
    ASSERT_TRUE(expr->as.binary_op->op == TOKEN_AND);

    ASTNode* left_of_and = expr->as.binary_op->left;
    verify_binary_op(left_of_and, TOKEN_AND, "a", "b");

    ASSERT_TRUE(expr->as.binary_op->right->type == NODE_IDENTIFIER);
    ASSERT_STREQ(expr->as.binary_op->right->as.identifier.name, "c");

    return true;
}

TEST_FUNC(Parser_Logical_OrElseIsRightAssociative) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager src_manager(arena);
    Parser parser = create_parser_for_test("a orelse b orelse c", arena, interner, src_manager);

    ASTNode* expr = parser.parseExpression();

    // Expected: (a orelse (b orelse c))
    ASSERT_TRUE(expr->type == NODE_BINARY_OP);
    ASSERT_TRUE(expr->as.binary_op->op == TOKEN_ORELSE);

    ASSERT_TRUE(expr->as.binary_op->left->type == NODE_IDENTIFIER);
    ASSERT_STREQ(expr->as.binary_op->left->as.identifier.name, "a");

    ASTNode* right_of_orelse = expr->as.binary_op->right;
    verify_binary_op(right_of_orelse, TOKEN_ORELSE, "b", "c");

    return true;
}

TEST_FUNC(Parser_Logical_ComplexPrecedence) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager src_manager(arena);
    Parser parser = create_parser_for_test("flag and val orelse default", arena, interner, src_manager);

    ASTNode* expr = parser.parseExpression();

    // Expected: (flag and val) orelse default
    ASSERT_TRUE(expr->type == NODE_BINARY_OP);
    ASSERT_TRUE(expr->as.binary_op->op == TOKEN_ORELSE);

    ASTNode* left_of_orelse = expr->as.binary_op->left;
    verify_binary_op(left_of_orelse, TOKEN_AND, "flag", "val");

    ASSERT_TRUE(expr->as.binary_op->right->type == NODE_IDENTIFIER);
    ASSERT_STREQ(expr->as.binary_op->right->as.identifier.name, "default");

    return true;
}

// --- Error Cases ---

TEST_FUNC(Parser_Logical_ErrorOnMissingRHS) {
    ASSERT_TRUE(expect_parser_abort("a orelse"));
    return true;
}

TEST_FUNC(Parser_Logical_ErrorOnMissingLHS) {
    ASSERT_TRUE(expect_parser_abort("and b"));
    return true;
}

TEST_FUNC(Parser_Logical_ErrorOnConsecutiveOperators) {
    ASSERT_TRUE(expect_parser_abort("a or or b"));
    return true;
}
