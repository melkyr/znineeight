#include "../src/include/test_framework.hpp"
#include "test_utils.hpp"
#include <limits>

TEST_FUNC(Lexer_NumberParsing_WithUnderscores) {
    // Test valid underscore usage
    ASSERT_TOKEN_INT("1_000", 1000);
    ASSERT_TOKEN_INT("0xFF_FF", 0xFFFF);
    ASSERT_TOKEN_FLOAT("3.141_592", 3.141592);

    // Test invalid underscore usage
    ASSERT_TOKEN_ERROR("1__000"); // Double underscore
    ASSERT_TOKEN_ERROR("100_");   // Trailing underscore
    ASSERT_TOKEN_ERROR("_100");   // Leading underscore
    ASSERT_TOKEN_ERROR("1._0");   // Underscore after decimal point
    ASSERT_TOKEN_ERROR("1.0_");   // Underscore at the end of a float

    return true;
}

TEST_FUNC(Lexer_NumberParsing_FloatEdgeCases) {
    ASSERT_TOKEN_FLOAT("1.", 1.0);
    ASSERT_TOKEN_KIND("1..", TOKEN_INTEGER_LITERAL);
    return true;
}

TEST_FUNC(Lexer_NumberParsing_IntegerOverflow) {
    // This requires a 64-bit integer parser to work correctly.
    // The test will fail until the lexer is updated.
    const char* max_u64_str = "18446744073709551615"; // 2^64 - 1
    const char* overflow_u64_str = "18446744073709551616"; // 2^64

    u64 expected_max = 18446744073709551615U;

    ASSERT_TOKEN_UINT(max_u64_str, expected_max);
    ASSERT_TOKEN_ERROR(overflow_u64_str);

    return true;
}
