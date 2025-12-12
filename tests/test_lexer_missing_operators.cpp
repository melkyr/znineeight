#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/source_manager.hpp"
#include "../src/include/string_interner.hpp"
#include <cstring>

TEST_FUNC(Lexer_MissingOperators) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);

    const char* content = "-- &&";
    sm.addFile("test.zig", content, strlen(content));

    Lexer lexer(sm, interner, arena, 0);

    Token token;

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_MINUS2, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_AMPERSAND2, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}
