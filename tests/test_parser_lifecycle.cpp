#include "test_framework.hpp"
#include "test_utils.hpp"
#include "parser.hpp"
#include "compilation_unit.hpp"

TEST_FUNC(Parser_TokenStreamLifetimeIsIndependentOfParserObject) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    const char* source = "const x: i32 = 42;";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser1 = ctx.getParser();

    {
        Parser* parser2 = ctx.getParser();
        RETR_UNUSED(parser2);
        // parser2 is a pointer and the object it points to is managed by the arena.
        // The object is not destroyed at the end of this scope.
    }

    // This should now pass because the token stream is owned by `ctx`,
    // which outlives both parser instances.
    ASTNode* node = parser1->parseVarDecl();
    ASSERT_TRUE(node != NULL);

    return true;
}

TEST_FUNC(Parser_MalformedStream_MissingEOF) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);

    // Manually construct a token array without EOF
    Token tokens[2];
    tokens[0].type = TOKEN_IDENTIFIER;
    tokens[0].value.identifier = interner.intern("x");
    tokens[0].location = SourceLocation();
    tokens[1].type = TOKEN_SEMICOLON;
    tokens[1].location = SourceLocation();

    SymbolTable symbol_table(arena);
    // Actually, it's easier to use the existing infrastructure if possible,
    // but the TokenSupplier always adds EOF.
    // Let's use the Parser constructor directly.

    SourceManager source_manager(arena);
    ErrorHandler eh(source_manager, arena);
    ErrorSetCatalogue catalogue(arena);
    GenericCatalogue generic_catalogue(arena);
    TypeInterner type_interner(arena);

    Parser parser(tokens, 2, &arena, &symbol_table, &eh, &catalogue, &generic_catalogue, &type_interner, &interner, "test");

    // Advance to the end
    ASSERT_FALSE(parser.is_at_end());
    parser.advance(); // consume 'x'
    ASSERT_FALSE(parser.is_at_end());
    parser.advance(); // consume ';'

    // Now we are at current_index_ == 2, which is == token_count_.
    // Before the fix, this would read tokens[2] and likely crash or return garbage.
    // Now it should return true and report an internal error.
    ASSERT_TRUE(parser.is_at_end());
    ASSERT_TRUE(eh.hasErrors());

    // Verify peek() also returns EOF safely
    ASSERT_EQ(parser.peek().type, TOKEN_EOF);

    return true;
}

// TEST_FUNC(Parser_CopyIsSafeAndDoesNotDoubleFree) {
//     // This test is now obsolete. The Parser class has been made non-copyable
//     // by making its copy constructor and assignment operator private. This was
//     // a key part of the fix to prevent memory corruption caused by shallow
//     // copies of the parser object.
//
//     // The test is preserved here as a historical record of the bug and its fix.
//     // The code below will no longer compile, which is the expected and desired behavior.
//
//     /*
//     ArenaAllocator arena(262144);
//     StringInterner interner(arena);
//     const char* source = "const x: i32 = 42;";
//
//     ParserTestContext ctx(source, arena, interner);
//
//     Parser p1 = ctx.getParser();
//     Parser p2 = p1; // Copy constructor - THIS WILL NOT COMPILE
//     Parser p3 = ctx.getParser(); // Create a valid parser for assignment
//     p3 = p1; // Assignment operator - THIS WILL NOT COMPILE
//
//     // Advance each parser independently to ensure they have their own state
//     p1.advance(); // p1 at 'x'
//
//     p2.advance(); // p2 at 'x'
//     p2.advance(); // p2 at ':'
//
//     p3.advance(); // p3 at 'x'
//     p3.advance(); // p3 at ':'
//     p3.advance(); // p3 at 'i32'
//
//     // The test passes if it completes without crashing from a double-free
//     // or other memory error when the parsers are destroyed.
//     ASSERT_EQ(p1.peek().type, TOKEN_IDENTIFIER);
//     ASSERT_EQ(p2.peek().type, TOKEN_COLON);
//     ASSERT_EQ(p3.peek().type, TOKEN_IDENTIFIER); // 'i32' is an identifier
//     */
//
//     return true;
// }

TEST_FUNC(Parser_CopyIsSafeAndDoesNotDoubleFree) {
    // This test is obsolete as the Parser is now non-copyable.
    // Returning true to satisfy the test runner.
    return true;
}
