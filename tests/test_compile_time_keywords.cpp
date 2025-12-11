#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/source_manager.hpp"
#include <cstring>

TEST_FUNC(lex_compile_time_and_special_function_keywords) {
    ArenaAllocator arena(1024);
    SourceManager sm(arena);

    const char* content = "asm comptime errdefer inline noinline test unreachable";
    sm.addFile("test.zig", content, strlen(content));

    Lexer lexer(sm, 0);

    Token token1 = lexer.nextToken();
    ASSERT_EQ(TOKEN_ASM, token1.type);

    Token token2 = lexer.nextToken();
    ASSERT_EQ(TOKEN_COMPTIME, token2.type);

    Token token3 = lexer.nextToken();
    ASSERT_EQ(TOKEN_ERRDEFER, token3.type);

    Token token4 = lexer.nextToken();
    ASSERT_EQ(TOKEN_INLINE, token4.type);

    Token token5 = lexer.nextToken();
    ASSERT_EQ(TOKEN_NOINLINE, token5.type);

    Token token6 = lexer.nextToken();
    ASSERT_EQ(TOKEN_TEST, token6.type);

    Token token7 = lexer.nextToken();
    ASSERT_EQ(TOKEN_UNREACHABLE, token7.type);

    Token token8 = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token8.type);

    return true;
}
