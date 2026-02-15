#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        // Group 1A
        test_DynamicArray_ShouldUseCopyConstructionOnReallocation,
        test_ArenaAllocator_AllocShouldReturn8ByteAligned,
        test_arena_alloc_out_of_memory,
        test_arena_alloc_zero_size,
        test_arena_alloc_aligned_out_of_memory,
        test_arena_alloc_aligned_overflow_check,
        test_basic_allocation,
        test_multiple_allocations,
        test_allocation_failure,
        test_reset,
        test_aligned_allocation,
        test_dynamic_array_append,
        test_dynamic_array_growth,
        test_dynamic_array_growth_from_zero,
        test_dynamic_array_non_pod_reallocation,
#ifdef DEBUG
        test_plat_itoa_conversion,
#endif
        // Group 1B
        test_string_interning,
        test_compilation_unit_creation,
        test_compilation_unit_var_decl,
        test_SymbolBuilder_BuildsCorrectly,
        test_SymbolTable_DuplicateDetection,
        test_SymbolTable_NestedScopes_And_Lookup,
        test_SymbolTable_HashTableResize,
        // Group 2A
        test_Lexer_FloatWithUnderscores_IntegerPart,
        test_Lexer_FloatWithUnderscores_FractionalPart,
        test_Lexer_FloatWithUnderscores_ExponentPart,
        test_Lexer_FloatWithUnderscores_AllParts,
        test_Lexer_FloatSimpleDecimal,
        test_Lexer_FloatNoFractionalPart,
        test_Lexer_FloatNoIntegerPart,
        test_Lexer_FloatWithExponent,
        test_Lexer_FloatWithNegativeExponent,
        test_Lexer_FloatExponentNoSign,
        test_Lexer_FloatIntegerWithExponent,
        test_Lexer_FloatExponentNoDigits,
        test_Lexer_FloatHexSimple,
        test_Lexer_FloatHexNoFractionalPart,
        test_Lexer_FloatHexNegativeExponent,
        test_Lexer_FloatHexInvalidFormat,
        // Group 2B
        test_lexer_integer_overflow,
        test_lexer_c_string_literal,
        test_lexer_handles_unicode_correctly,
        test_lexer_handles_unterminated_char_hex_escape,
        test_lexer_handles_unterminated_string_hex_escape,
        test_Lexer_HandlesU64Integer,
        test_Lexer_UnterminatedCharHexEscape,
        test_Lexer_UnterminatedStringHexEscape,
        test_Lexer_UnicodeInStringLiteral,
        test_IntegerLiterals,
        test_Lexer_StringLiteral_EscapedCharacters,
        test_Lexer_StringLiteral_LongString,
        test_IntegerLiteralParsing_UnsignedSuffix,
        test_IntegerLiteralParsing_LongSuffix,
        test_IntegerLiteralParsing_UnsignedLongSuffix,
        // Group 2C
        test_single_char_tokens,
        test_multi_char_tokens,
        test_assignment_vs_equality,
        test_lex_arithmetic_and_bitwise_operators,
        test_Lexer_RangeExpression,
        test_lex_compound_assignment_operators,
        test_LexerSpecialOperators,
        test_LexerSpecialOperatorsMixed,
        test_Lexer_Delimiters,
        test_Lexer_DotOperators,
        // Group 2D
        test_skip_comments,
        test_nested_block_comments,
        test_unterminated_block_comment,
        test_lex_visibility_and_linkage_keywords,
        test_lex_compile_time_and_special_function_keywords,
        test_lex_miscellaneous_keywords,
        test_lex_missing_keywords,
        // Group 2E
        test_lexer_handles_tab_correctly,
        test_lexer_handles_long_identifier,
        test_Lexer_HandlesLongIdentifier,
        test_Lexer_NumericLookaheadSafety,
        test_token_fields_are_initialized,
        test_Lexer_ComprehensiveCrossGroup,
        test_Lexer_IdentifiersAndStrings,
        test_Lexer_ErrorConditions,
        test_IntegerRangeAmbiguity,
        test_Lexer_MultiLineIntegrationTest
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
