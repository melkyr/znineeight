#include "test_framework.hpp"
#include "lexer.hpp"
#include "source_manager.hpp"
#include "string_interner.hpp"
#include "memory.hpp"
#include "test_utils.hpp"
#include <cstring>

TEST_FUNC(unicode_validation) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager source_manager(arena);

    // Test for out-of-range Unicode codepoint
    const char* out_of_range_content = "\"\\u{110000}\"";
    u32 out_of_range_file_id = source_manager.addFile("out_of_range.zig", out_of_range_content, strlen(out_of_range_content));
    Lexer out_of_range_lexer(source_manager, interner, arena, out_of_range_file_id);
    Token out_of_range_token = out_of_range_lexer.nextToken();
    ASSERT_EQ(out_of_range_token.type, TOKEN_ERROR);

    // Test for surrogate half Unicode codepoint
    const char* surrogate_content = "\"\\u{D800}\"";
    u32 surrogate_file_id = source_manager.addFile("surrogate.zig", surrogate_content, strlen(surrogate_content));
    Lexer surrogate_lexer(source_manager, interner, arena, surrogate_file_id);
    Token surrogate_token = surrogate_lexer.nextToken();
    ASSERT_EQ(surrogate_token.type, TOKEN_ERROR);

    return true;
}

TEST_FUNC(c_style_strings) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager source_manager(arena);
    const char* test_content = "c\"hello\"";
    u32 file_id = source_manager.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(source_manager, interner, arena, file_id);
    Token token = lexer.nextToken();

    ASSERT_EQ(token.type, TOKEN_STRING_LITERAL);
    ASSERT_STREQ(token.value.identifier, "hello");

    return true;
}

TEST_FUNC(multiline_strings) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager source_manager(arena);
    const char* test_content = "\"hello\\\nworld\"";
    u32 file_id = source_manager.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(source_manager, interner, arena, file_id);
    Token token = lexer.nextToken();

    ASSERT_EQ(token.type, TOKEN_STRING_LITERAL);
    ASSERT_STREQ(token.value.identifier, "helloworld");

    return true;
}
