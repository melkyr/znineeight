#include "test_framework.hpp"
#include "lexer.hpp"
#include "source_manager.hpp"
#include "string_interner.hpp"
#include "memory.hpp"
#include "test_utils.hpp"
#include <cstring>

TEST_FUNC(peek_and_advance) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    SourceManager source_manager(arena);
    const char* test_content = "abc";
    u32 file_id = source_manager.addFile("test.zig", test_content, strlen(test_content));

    Lexer lexer(source_manager, interner, arena, file_id);

    ASSERT_TRUE(lexer.peek(0) == 'a');
    ASSERT_TRUE(lexer.peek(1) == 'b');
    ASSERT_TRUE(lexer.peek(2) == 'c');

    lexer.advance();
    ASSERT_TRUE(lexer.peek(0) == 'b');

    lexer.advance();
    ASSERT_TRUE(lexer.peek(0) == 'c');

    lexer.advance();
    ASSERT_TRUE(lexer.peek(0) == '\0');

    // Test advancing past the end
    lexer.advance();
    ASSERT_TRUE(lexer.peek(0) == '\0');

    return true;
}

TEST_FUNC(character_classification) {
    ASSERT_TRUE(isIdentifierStart('a'));
    ASSERT_TRUE(isIdentifierStart('Z'));
    ASSERT_TRUE(isIdentifierStart('_'));
    ASSERT_FALSE(isIdentifierStart('9'));
    ASSERT_FALSE(isIdentifierStart('-'));

    ASSERT_TRUE(isIdentifierChar('a'));
    ASSERT_TRUE(isIdentifierChar('Z'));
    ASSERT_TRUE(isIdentifierChar('_'));
    ASSERT_TRUE(isIdentifierChar('9'));
    ASSERT_FALSE(isIdentifierChar('-'));

    return true;
}
