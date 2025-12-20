#include "test_framework.hpp"
#include "parser.hpp"
#include "symbol_table.hpp"
#include "memory.hpp"

TEST_FUNC(parser_symbol_table_integration) {
    ArenaAllocator arena(1024);
    SymbolTable table(arena);
    Token tokens[1]; // Dummy token stream

    // This line should fail to compile initially
    Parser parser(tokens, 1, &arena, &table);

    // This assertion is just to have a valid test body.
    // The real test is the successful compilation.
    ASSERT_TRUE(true);

    return true;
}
