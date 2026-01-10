#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/compilation_unit.hpp"
#include "../src/include/parser.hpp"
#include "../src/include/string_interner.hpp"
#include <cstring>

TEST_FUNC(lex_compile_time_and_special_function_keywords) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* content = "asm comptime errdefer inline noinline test unreachable";
    u32 file_id = unit.addSource("test.zig", content);
    Parser* parser = unit.createParser(file_id);

    ASSERT_EQ(TOKEN_ASM, parser->advance().type);
    ASSERT_EQ(TOKEN_COMPTIME, parser->advance().type);
    ASSERT_EQ(TOKEN_ERRDEFER, parser->advance().type);
    ASSERT_EQ(TOKEN_INLINE, parser->advance().type);
    ASSERT_EQ(TOKEN_NOINLINE, parser->advance().type);
    ASSERT_EQ(TOKEN_TEST, parser->advance().type);
    ASSERT_EQ(TOKEN_UNREACHABLE, parser->advance().type);
    ASSERT_EQ(TOKEN_EOF, parser->peek().type);

    return true;
}
