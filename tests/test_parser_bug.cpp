#include "test_framework.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include <new>
#include <cstring>

TEST_FUNC(ParserBug_LogicalOperatorSymbol) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source = "const x: bool = a && b;";
    ParserTestContext ctx(source, arena, interner);
    Parser parser = ctx.getParser();

    ASTNode* node = parser.parseVarDecl();

    // The parser should crash before this point, but if it doesn't, these assertions will fail.
    ASSERT_TRUE(node != NULL);
    ASTVarDeclNode* var_decl = node->as.var_decl;
    ASTNode* initializer = var_decl->initializer;
    ASSERT_TRUE(initializer != NULL);

    // The core of the bug: The parser will likely create a bitwise AND, not a logical AND.
    // Or it might fail to parse the expression altogether.
    ASSERT_TRUE(initializer->type == NODE_BINARY_OP);

    ASTBinaryOpNode* bin_op = initializer->as.binary_op;
    ASSERT_TRUE(bin_op->op == TOKEN_AND);

    return true;
}
