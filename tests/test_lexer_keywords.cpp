#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/source_manager.hpp"
#include "../src/include/string_interner.hpp"
#include <cstring>
#include <string>

TEST_FUNC(keywords_are_sorted) {
    for (int i = 0; i < num_keywords - 1; ++i) {
        ASSERT_TRUE(strcmp(keywords[i].name, keywords[i+1].name) < 0);
    }
    return true;
}

TEST_FUNC(lex_keywords) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);

    std::string test_content;
    for (int i = 0; i < num_keywords; ++i) {
        test_content += keywords[i].name;
        if (i < num_keywords - 1) {
            test_content += " ";
        }
    }

    sm.addFile("test.zig", test_content.c_str(), test_content.length());

    Lexer lexer(sm, interner, arena, 0);

    for (int i = 0; i < num_keywords; ++i) {
        Token token = lexer.nextToken();
        ASSERT_EQ(keywords[i].type, token.type);
    }

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(lex_miscellaneous_keywords) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);

    const char* content = "addrspace align allowzero and anyframe anytype callconv noalias nosuspend or packed threadlocal volatile";
    sm.addFile("test.zig", content, strlen(content));

    Lexer lexer(sm, interner, arena, 0);

    Token token;

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_ADDRSPACE, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_ALIGN, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_ALLOWZERO, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_AND, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_ANYFRAME, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_ANYTYPE, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_CALLCONV, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_NOALIAS, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_NOSUSPEND, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_OR, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_PACKED, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_THREADLOCAL, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_VOLATILE, token.type);

    token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(lex_visibility_and_linkage_keywords) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);

    const char* content = "export extern pub linksection usingnamespace";
    sm.addFile("test.zig", content, strlen(content));

    Lexer lexer(sm, interner, arena, 0);

    Token token1 = lexer.nextToken();
    ASSERT_EQ(TOKEN_EXPORT, token1.type);

    Token token2 = lexer.nextToken();
    ASSERT_EQ(TOKEN_EXTERN, token2.type);

    Token token3 = lexer.nextToken();
    ASSERT_EQ(TOKEN_PUB, token3.type);

    Token token4 = lexer.nextToken();
    ASSERT_EQ(TOKEN_LINKSECTION, token4.type);

    Token token5 = lexer.nextToken();
    ASSERT_EQ(TOKEN_USINGNAMESPACE, token5.type);

    Token token6 = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token6.type);

    return true;
}
