#include "test_utils.hpp"
#include "lexer.hpp"
#include "source_manager.hpp"
#include "string_interner.hpp"
#include "memory.hpp"
#include "test_framework.hpp"

TEST_FUNC(lexer_peek_safe_at_end);
bool test_lexer_peek_safe_at_end() {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);

    u32 file_id = sm.addFile("test.zig", "var", 3);
    Lexer lexer(sm, interner, arena, file_id);

    // "var" is 3 chars. End is at index 3.
    // Peeking far beyond the end of the buffer should not crash
    // and should return a null character.
    ASSERT_TRUE(lexer.peek(100) == '\0');

    // Advance to the end
    lexer.advance(3);

    // Peeking exactly at the null terminator
    ASSERT_TRUE(lexer.peek(0) == '\0');
    // Peeking just past the null terminator
    ASSERT_TRUE(lexer.peek(1) == '\0');

    return true;
}

TEST_FUNC(lexer_peek_within_bounds);
bool test_lexer_peek_within_bounds() {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager sm(arena);

    u32 file_id = sm.addFile("test.zig", "const", 5);
    Lexer lexer(sm, interner, arena, file_id);

    ASSERT_TRUE(lexer.peek(0) == 'c');
    ASSERT_TRUE(lexer.peek(1) == 'o');
    ASSERT_TRUE(lexer.peek(4) == 't');

    lexer.advance(2); // Now at 'n'
    ASSERT_TRUE(lexer.peek(0) == 'n');
    ASSERT_TRUE(lexer.peek(2) == 't');

    return true;
}
