#include "../src/include/test_framework.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/compilation_unit.hpp"
#include "../src/include/parser.hpp"
#include "../src/include/string_interner.hpp"
#include <cstring>

TEST_FUNC(lex_missing_keywords) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* content = "defer fn var";
    u32 file_id = unit.addSource("test.zig", content);
    Parser* parser = unit.createParser(file_id);

    ASSERT_EQ(TOKEN_DEFER, parser->advance().type);
    ASSERT_EQ(TOKEN_FN, parser->advance().type);
    ASSERT_EQ(TOKEN_VAR, parser->advance().type);
    ASSERT_EQ(TOKEN_EOF, parser->peek().type);

    return true;
}
