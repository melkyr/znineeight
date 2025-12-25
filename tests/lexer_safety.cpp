#include "test_framework.hpp"
#include "lexer.hpp"
#include "source_manager.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include <cstring> // For memset

TEST_FUNC(Lexer_Peek_Safety) {
    ArenaAllocator alloc(4096);
    // Allocate a guard buffer and fill it with a known, non-null value.
    // This increases the chance that a buffer over-read will be detected.
    char* guard_buffer = (char*)alloc.alloc(1024);
    memset(guard_buffer, 'X', 1024);

    SourceManager sm(alloc);
    StringInterner interner(alloc);

    // Test with a normal string
    const char* source = "..";
    u32 file_id = sm.addFile("test_peek.zig", source, strlen(source));
    Lexer lexer(sm, interner, alloc, file_id);

    // Test peeking within bounds
    ASSERT_TRUE(lexer.peek(0) == '.');
    ASSERT_TRUE(lexer.peek(1) == '.');

    // Test peeking at the null terminator
    ASSERT_TRUE(lexer.peek(2) == '\0');

    // Test peeking past the end of the buffer.
    // With the unsafe implementation, this is UB, but our guard buffer makes it likely
    // that we'll read 'X' instead of '\0', causing the test to fail.
    // The correct, safe implementation should return '\0'.
    ASSERT_TRUE(lexer.peek(3) == '\0');
    ASSERT_TRUE(lexer.peek(100) == '\0');

    // Test peeking on an empty source
    const char* empty_source = "";
    u32 empty_file_id = sm.addFile("empty.zig", empty_source, strlen(empty_source));
    Lexer empty_lexer(sm, interner, alloc, empty_file_id);
    ASSERT_TRUE(empty_lexer.peek(0) == '\0');
    ASSERT_TRUE(empty_lexer.peek(5) == '\0');

    return true;
}
