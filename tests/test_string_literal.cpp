#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/source_manager.hpp"
#include "../src/include/string_interner.hpp"
#include <cstring>

TEST_FUNC(Lexer_StringLiteral_EscapedCharacters) {
    ArenaAllocator arena(4096); // Use a larger arena for tests
    StringInterner interner(arena);
    SourceManager sm(arena);

    // 1. Test basic escape sequences
    const char* source1 = "\"Hello\\nWorld\"";
    u32 file_id1 = sm.addFile("test1.zig", source1, strlen(source1));
    Lexer lexer1(sm, interner, arena, file_id1);
    Token t1 = lexer1.nextToken();
    ASSERT_EQ(TOKEN_STRING_LITERAL, t1.type);
    ASSERT_STREQ("Hello\nWorld", t1.value.identifier);

    // 2. Test a mix of escapes
    const char* source2 = "\"\\tLine1\\n\\\"Quoted\\\" \\\\ Backslash\"";
    SourceManager sm2(arena);
    u32 file_id2 = sm2.addFile("test2.zig", source2, strlen(source2));
    Lexer lexer2(sm2, interner, arena, file_id2);
    Token t2 = lexer2.nextToken();
    ASSERT_EQ(TOKEN_STRING_LITERAL, t2.type);
    ASSERT_STREQ("\tLine1\n\"Quoted\" \\ Backslash", t2.value.identifier);

    // 3. Test hex escape sequence
    const char* source3 = "\"Hex: \\x41\"";
    SourceManager sm3(arena);
    u32 file_id3 = sm3.addFile("test3.zig", source3, strlen(source3));
    Lexer lexer3(sm3, interner, arena, file_id3);
    Token t3 = lexer3.nextToken();
    ASSERT_EQ(TOKEN_STRING_LITERAL, t3.type);
    ASSERT_STREQ("Hex: A", t3.value.identifier);

    // 4. Test invalid escape sequence
    const char* source4 = "\"Invalid escape \\z\"";
    SourceManager sm4(arena);
    u32 file_id4 = sm4.addFile("test4.zig", source4, strlen(source4));
    Lexer lexer4(sm4, interner, arena, file_id4);
    Token t4 = lexer4.nextToken();
    ASSERT_EQ(TOKEN_ERROR, t4.type);

    // 5. Test unterminated string
    const char* source5 = "\"Unterminated";
    SourceManager sm5(arena);
    u32 file_id5 = sm5.addFile("test5.zig", source5, strlen(source5));
    Lexer lexer5(sm5, interner, arena, file_id5);
    Token t5 = lexer5.nextToken();
    ASSERT_EQ(TOKEN_ERROR, t5.type);

    return true;
}

TEST_FUNC(Lexer_StringLiteral_LongString) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    SourceManager sm(arena);

    // Create a string longer than 256 characters
    char long_string_source[512];
    strcpy(long_string_source, "\"");
    for (int i = 0; i < 300; ++i) {
        strcat(long_string_source, "a");
    }
    strcat(long_string_source, "\"");

    char expected_string[512];
    strcpy(expected_string, "");
     for (int i = 0; i < 300; ++i) {
        strcat(expected_string, "a");
    }

    u32 file_id = sm.addFile("long_string_test.zig", long_string_source, strlen(long_string_source));
    Lexer lexer(sm, interner, arena, file_id);

    Token t = lexer.nextToken();
    ASSERT_EQ(TOKEN_STRING_LITERAL, t.type);
    ASSERT_STREQ(expected_string, t.value.identifier);

    return true;
}
