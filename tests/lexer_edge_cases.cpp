#include "test_framework.hpp"
#include "lexer.hpp"
#include "source_manager.hpp"
#include "string_interner.hpp"
#include "memory.hpp"
#include "compilation_unit.hpp"
#include "test_utils.hpp"
#include <cstring> // For strlen

// Test function implementations will go here.

/**
 * @brief Tests that the lexer correctly handles tab characters for column tracking.
 *
 * This test verifies that a tab character advances the column number to the next
 * 4-space tab stop, ensuring accurate error reporting.
 */
TEST_FUNC(lexer_handles_tab_correctly) {
    ArenaAllocator arena(4096);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);

    u32 file_id = comp_unit.addSource("test.zig", "\tident");
    Parser parser = comp_unit.createParser(file_id);

    Token token = parser.peek();
    ASSERT_EQ(TOKEN_IDENTIFIER, token.type);
    ASSERT_EQ(5, token.location.column);
    return 1;
}

/**
 * @brief Tests that the lexer correctly parses a Unicode escape sequence in a character literal.
 *
 * This test ensures that the lexer can handle 32-bit Unicode code points without
 * truncating the value, which was a bug in a previous version.
 */
TEST_FUNC(lexer_handles_unicode_correctly) {
    ArenaAllocator arena(4096);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);

    u32 file_id = comp_unit.addSource("test.zig", "'\\u{1F4A9}'");
    Parser parser = comp_unit.createParser(file_id);

    Token token = parser.peek();
    ASSERT_EQ(TOKEN_CHAR_LITERAL, token.type);
    ASSERT_EQ(0x1F4A9, token.value.character);
    return 1;
}

/**
 * @brief Tests that the lexer correctly handles an unterminated hexadecimal escape sequence in a character literal.
 *
 * This test is a memory safety check to ensure that the lexer does not read past
 * the end of the source buffer when parsing a malformed hex escape sequence.
 */
TEST_FUNC(lexer_handles_unterminated_char_hex_escape) {
    ArenaAllocator arena(4096);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);

    u32 file_id = comp_unit.addSource("test.zig", "'\\x");
    Parser parser = comp_unit.createParser(file_id);

    Token token = parser.peek();
    ASSERT_EQ(TOKEN_ERROR, token.type);
    return 1;
}

/**
 * @brief Tests that the lexer correctly handles an unterminated hexadecimal escape sequence in a string literal.
 *
 * This test is a memory safety check to ensure that the lexer does not read past
 * the end of the source buffer when parsing a malformed hex escape sequence.
 */
TEST_FUNC(lexer_handles_unterminated_string_hex_escape) {
    ArenaAllocator arena(4096);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);

    u32 file_id = comp_unit.addSource("test.zig", "\"\\x");
    Parser parser = comp_unit.createParser(file_id);

    Token token = parser.peek();
    ASSERT_EQ(TOKEN_ERROR, token.type);
    return 1;
}

/**
 * @brief Tests that the lexer correctly handles an identifier that is longer than 256 characters.
 *
 * This test verifies that the lexer no longer has a fixed-size buffer limitation
 * for identifiers, which was a bug in a previous version.
 */
TEST_FUNC(lexer_handles_long_identifier) {
    ArenaAllocator arena(1024 * 1024); // 1MB arena
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);

    // Create a very long identifier string
    char long_identifier[300];
    for (int i = 0; i < 299; ++i) {
        long_identifier[i] = 'a';
    }
    long_identifier[299] = '\0';

    u32 file_id = comp_unit.addSource("test.zig", long_identifier);
    Parser parser = comp_unit.createParser(file_id);

    Token token = parser.peek();
    ASSERT_EQ(TOKEN_IDENTIFIER, token.type);
    ASSERT_STREQ(long_identifier, token.value.identifier);
    return 1;
}

TEST_FUNC(lexer_integer_overflow);
TEST_FUNC(lexer_c_string_literal);

bool test_lexer_integer_overflow() {
    ArenaAllocator arena(4096);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);

    // u64_max is 18446744073709551615, so this is u64_max + 1
    u32 file_id = comp_unit.addSource("test.zig", "18446744073709551616");
    Parser parser = comp_unit.createParser(file_id);

    Token token = parser.peek();
    ASSERT_EQ(TOKEN_ERROR, token.type);

    return true;
}

bool test_lexer_c_string_literal() {
    ArenaAllocator arena(4096);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);

    u32 file_id = comp_unit.addSource("test.zig", "c\"hello\"");
    Parser parser = comp_unit.createParser(file_id);

    // First token should be the identifier 'c'
    Token token1 = parser.peek();
    ASSERT_EQ(TOKEN_IDENTIFIER, token1.type);
    ASSERT_STREQ("c", token1.value.identifier);

    // Advance the parser to the next token
    parser.advance();

    // Second token should be the string literal "hello"
    Token token2 = parser.peek();
    ASSERT_EQ(TOKEN_STRING_LITERAL, token2.type);
    ASSERT_STREQ("hello", token2.value.identifier);

    return true;
}
