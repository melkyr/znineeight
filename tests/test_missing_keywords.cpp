#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/source_manager.hpp"
#include "../src/include/string_interner.hpp"
#include <cstring>

TEST_FUNC(lex_missing_keywords) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    SourceManager sm(arena);

    const char* content = "defer fn var";
    sm.addFile("test.zig", content, strlen(content));

    Lexer lexer(sm, interner, arena, 0);

    Token token;

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_DEFER, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_FN, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_VAR, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}
