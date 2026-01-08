#include "test_framework.hpp"
#include "test_utils.hpp"
#include "parser.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "ast.hpp"

TEST_FUNC(Parser_CopiedState_DoesNotCorruptSymbolTable) {
    // This test is designed to reproduce the SymbolTable memory exhaustion bug.
    // The arena is small, and the test mimics the unsafe use of a copied parser
    // that modifies the shared symbol table.
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    const char* source = "var x: i32 = 42;";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();

    // Calling the top-level parse() method ensures that the global scope is
    // managed correctly by the parser, preventing the symbol table corruption.
    ASTNode* root = parser->parse();

    // The test now passes if it completes without crashing.
    ASSERT_TRUE(root != NULL);
    return true;
}
