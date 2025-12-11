#include "test_framework.hpp"
#include "lexer.hpp"
#include "source_manager.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include <cstring>

// Helper function to test a single keyword token
static bool test_single_keyword(const char* keyword_str, TokenType expected_type) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", keyword_str, strlen(keyword_str));
    Lexer lexer(sm, interner, file_id);
    Token token = lexer.nextToken();
    ASSERT_EQ(token.type, expected_type);
    ASSERT_EQ(lexer.nextToken().type, TOKEN_EOF);
    return true;
}

TEST_FUNC(LexerKeywordEnum) {
    ASSERT_TRUE(test_single_keyword("enum", TOKEN_ENUM));
    return true;
}

TEST_FUNC(LexerKeywordError) {
    // Using TOKEN_ERROR_SET to avoid conflict with TOKEN_ERROR for lexical errors.
    ASSERT_TRUE(test_single_keyword("error", TOKEN_ERROR_SET));
    return true;
}

TEST_FUNC(LexerKeywordStruct) {
    ASSERT_TRUE(test_single_keyword("struct", TOKEN_STRUCT));
    return true;
}

TEST_FUNC(LexerKeywordUnion) {
    ASSERT_TRUE(test_single_keyword("union", TOKEN_UNION));
    return true;
}

TEST_FUNC(LexerKeywordOpaque) {
    ASSERT_TRUE(test_single_keyword("opaque", TOKEN_OPAQUE));
    return true;
}

TEST_FUNC(LexerLongIdentifierError) {
    char long_identifier[300];
    // Create a string longer than 255 characters, which is the current buffer limit.
    for (int i = 0; i < 257; ++i) {
        long_identifier[i] = 'a';
    }
    long_identifier[257] = '\0';

    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", long_identifier, strlen(long_identifier));
    Lexer lexer(sm, interner, file_id);
    Token token = lexer.nextToken();
    // The lexer should return an error for identifiers that are too long.
    ASSERT_EQ(token.type, TOKEN_ERROR);
    return true;
}
