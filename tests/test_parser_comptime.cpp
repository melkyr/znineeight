#include "test_framework.hpp"
#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"

#include <cstdlib>
#include <cstring>

// Helper function from test_parser_errors.cpp
bool expect_parser_abort(const char* source);

#include "symbol_table.hpp"

// Helper to create a parser for a given source string.
static Parser create_parser_for_test(
    const char* source,
    ArenaAllocator& arena,
    SourceManager& sm,
    StringInterner& interner
) {
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);
    SymbolTable table(arena);

    DynamicArray<Token> tokens(arena);
    Token token;
    do {
        token = lexer.nextToken();
        tokens.append(token);
    } while (token.type != TOKEN_EOF);

    return ParserBuilder(tokens.getData(), tokens.length(), &arena, &table).build();
}

// Test parsing a valid comptime block
TEST_FUNC(Parser_ComptimeBlock_Valid) {
    ArenaAllocator arena(1024);
    SourceManager sm(arena);
    StringInterner interner(arena);
    const char* source = "comptime { 123 }";
    Parser parser = create_parser_for_test(source, arena, sm, interner);

    ASTNode* stmt = parser.parseStatement();
    ASSERT_TRUE(stmt != NULL);
    ASSERT_EQ(stmt->type, NODE_COMPTIME_BLOCK);

    ASTComptimeBlockNode* comptime_block = &stmt->as.comptime_block;
    ASSERT_TRUE(comptime_block->expression != NULL);
    ASSERT_EQ(comptime_block->expression->type, NODE_INTEGER_LITERAL);
    ASSERT_EQ(comptime_block->expression->as.integer_literal.value, 123);

    return true;
}

// Test that a comptime block must have an expression
TEST_FUNC(Parser_ComptimeBlock_Error_MissingExpression) {
    ASSERT_TRUE(expect_parser_abort("comptime { }"));
    return true;
}

// Test that a comptime block must have an opening brace
TEST_FUNC(Parser_ComptimeBlock_Error_MissingOpeningBrace) {
    ASSERT_TRUE(expect_parser_abort("comptime 123 }"));
    return true;
}

// Test that a comptime block must have a closing brace
TEST_FUNC(Parser_ComptimeBlock_Error_MissingClosingBrace) {
    ASSERT_TRUE(expect_parser_abort("comptime { 123"));
    return true;
}
