#include "test_framework.hpp"
#include "test_utils.hpp"
#include "parser.hpp"
#include "compilation_unit.hpp"

TEST_FUNC(Parser_TokenStreamLifetimeIsIndependentOfParserObject) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    const char* source = "const x: i32 = 42;";

    ParserTestContext ctx(source, arena, interner);
    Parser parser1 = ctx.getParser();

    {
        Parser parser2 = ctx.getParser();
        // parser2 is destroyed at the end of this scope.
        // With the fix, this should have no effect on the token stream owned by the context.
    }

    // This should now pass because the token stream is owned by `ctx`,
    // which outlives both parser instances.
    ASTNode* node = parser1.parseVarDecl();
    ASSERT_TRUE(node != NULL);

    return true;
}

TEST_FUNC(Parser_CopyIsSafeAndDoesNotDoubleFree) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    const char* source = "const x: i32 = 42;";

    ParserTestContext ctx(source, arena, interner);

    Parser p1 = ctx.getParser();
    Parser p2 = p1; // Copy constructor
    Parser p3 = ctx.getParser(); // Create a valid parser for assignment
    p3 = p1; // Assignment operator

    // Advance each parser independently to ensure they have their own state
    p1.advance(); // p1 at 'x'

    p2.advance(); // p2 at 'x'
    p2.advance(); // p2 at ':'

    p3.advance(); // p3 at 'x'
    p3.advance(); // p3 at ':'
    p3.advance(); // p3 at 'i32'

    // The test passes if it completes without crashing from a double-free
    // or other memory error when the parsers are destroyed.
    ASSERT_EQ(p1.peek().type, TOKEN_IDENTIFIER);
    ASSERT_EQ(p2.peek().type, TOKEN_COLON);
    ASSERT_EQ(p3.peek().type, TOKEN_IDENTIFIER); // 'i32' is an identifier

    return true;
}
