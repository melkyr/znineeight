#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/source_manager.hpp"
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
    SourceManager sm(arena);

    std::string test_content;
    for (int i = 0; i < num_keywords; ++i) {
        test_content += keywords[i].name;
        if (i < num_keywords - 1) {
            test_content += " ";
        }
    }

    sm.addFile("test.zig", test_content.c_str(), test_content.length());

    Lexer lexer(sm, 0);

    for (int i = 0; i < num_keywords; ++i) {
        Token token = lexer.nextToken();
        ASSERT_EQ(keywords[i].type, token.type);
    }

    Token token = lexer.nextToken();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}
