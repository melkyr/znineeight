#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/compilation_unit.hpp"
#include "../src/include/parser.hpp"
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
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    std::string test_content;
    for (int i = 0; i < num_keywords; ++i) {
        test_content += keywords[i].name;
        if (i < num_keywords - 1) {
            test_content += " ";
        }
    }

    u32 file_id = unit.addSource("test.zig", test_content.c_str());
    Parser* parser = unit.createParser(file_id);

    for (int i = 0; i < num_keywords; ++i) {
        Token token = parser->advance();
        ASSERT_EQ(keywords[i].type, token.type);
    }

    Token token = parser->peek();
    ASSERT_EQ(TOKEN_EOF, token.type);

    return true;
}

TEST_FUNC(lex_miscellaneous_keywords) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* content = "addrspace align allowzero and anyframe anytype callconv noalias nosuspend or packed threadlocal volatile";
    u32 file_id = unit.addSource("test.zig", content);
    Parser* parser = unit.createParser(file_id);

    ASSERT_EQ(TOKEN_ADDRSPACE, parser->advance().type);
    ASSERT_EQ(TOKEN_ALIGN, parser->advance().type);
    ASSERT_EQ(TOKEN_ALLOWZERO, parser->advance().type);
    ASSERT_EQ(TOKEN_AND, parser->advance().type);
    ASSERT_EQ(TOKEN_ANYFRAME, parser->advance().type);
    ASSERT_EQ(TOKEN_ANYTYPE, parser->advance().type);
    ASSERT_EQ(TOKEN_CALLCONV, parser->advance().type);
    ASSERT_EQ(TOKEN_NOALIAS, parser->advance().type);
    ASSERT_EQ(TOKEN_NOSUSPEND, parser->advance().type);
    ASSERT_EQ(TOKEN_OR, parser->advance().type);
    ASSERT_EQ(TOKEN_PACKED, parser->advance().type);
    ASSERT_EQ(TOKEN_THREADLOCAL, parser->advance().type);
    ASSERT_EQ(TOKEN_VOLATILE, parser->advance().type);
    ASSERT_EQ(TOKEN_EOF, parser->peek().type);

    return true;
}

TEST_FUNC(lex_visibility_and_linkage_keywords) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* content = "export extern pub linksection usingnamespace";
    u32 file_id = unit.addSource("test.zig", content);
    Parser* parser = unit.createParser(file_id);

    ASSERT_EQ(TOKEN_EXPORT, parser->advance().type);
    ASSERT_EQ(TOKEN_EXTERN, parser->advance().type);
    ASSERT_EQ(TOKEN_PUB, parser->advance().type);
    ASSERT_EQ(TOKEN_LINKSECTION, parser->advance().type);
    ASSERT_EQ(TOKEN_USINGNAMESPACE, parser->advance().type);
    ASSERT_EQ(TOKEN_EOF, parser->peek().type);

    return true;
}
