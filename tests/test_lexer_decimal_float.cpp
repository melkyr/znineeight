#include "test_utils.hpp"
#include "lexer.hpp"
#include "source_manager.hpp"
#include "string_interner.hpp"
#include "memory.hpp"
#include "test_framework.hpp"
#include <cmath>

static bool test_float_lexing(const char* source, double expected_value) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    SourceManager sm(arena);
    u32 file_id = sm.addFile("test.zig", source, strlen(source));
    Lexer lexer(sm, interner, arena, file_id);
    Token token = lexer.nextToken();

    ASSERT_TRUE(token.type == TOKEN_FLOAT_LITERAL);
    // Using a small epsilon for float comparison
    ASSERT_TRUE(fabs(token.value.floating_point - expected_value) < 1e-9);
    return true;
}

TEST_FUNC(Lexer_FloatWithUnderscores_IntegerPart);
bool test_Lexer_FloatWithUnderscores_IntegerPart() {
    return test_float_lexing("1_000.0", 1000.0);
}

TEST_FUNC(Lexer_FloatWithUnderscores_FractionalPart);
bool test_Lexer_FloatWithUnderscores_FractionalPart() {
    return test_float_lexing("3.14_159", 3.14159);
}

TEST_FUNC(Lexer_FloatWithUnderscores_ExponentPart);
bool test_Lexer_FloatWithUnderscores_ExponentPart() {
    return test_float_lexing("1.2e+1_0", 1.2e+10);
}

TEST_FUNC(Lexer_FloatWithUnderscores_AllParts);
bool test_Lexer_FloatWithUnderscores_AllParts() {
    return test_float_lexing("1_000.123_456e+1_0", 1000.123456e+10);
}
