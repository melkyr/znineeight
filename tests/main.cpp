#include "../src/include/test_framework.hpp"

// Forward declarations for all test functions
TEST_FUNC(basic_allocation);
TEST_FUNC(multiple_allocations);
TEST_FUNC(allocation_failure);
TEST_FUNC(reset);
TEST_FUNC(aligned_allocation);
TEST_FUNC(string_interning);
TEST_FUNC(dynamic_array_append);
TEST_FUNC(dynamic_array_growth);
TEST_FUNC(single_char_tokens);
TEST_FUNC(multi_char_tokens);
TEST_FUNC(assignment_vs_equality);
TEST_FUNC(skip_comments);
TEST_FUNC(nested_block_comments);
TEST_FUNC(unterminated_block_comment);
TEST_FUNC(Lexer_FloatSimpleDecimal);
TEST_FUNC(Lexer_FloatNoFractionalPart);
TEST_FUNC(Lexer_FloatNoIntegerPart);
TEST_FUNC(Lexer_FloatWithExponent);
TEST_FUNC(Lexer_FloatWithNegativeExponent);
TEST_FUNC(Lexer_FloatExponentNoSign);
TEST_FUNC(Lexer_FloatIntegerWithExponent);
TEST_FUNC(Lexer_FloatInvalidExponent);
TEST_FUNC(Lexer_FloatHexSimple);
TEST_FUNC(Lexer_FloatHexNoFractionalPart);
TEST_FUNC(Lexer_FloatHexNegativeExponent);
TEST_FUNC(Lexer_FloatHexInvalidFormat);
TEST_FUNC(IntegerLiterals);
TEST_FUNC(lex_arithmetic_and_bitwise_operators);
TEST_FUNC(lex_compound_assignment_operators);
TEST_FUNC(LexerSpecialOperators);
TEST_FUNC(LexerSpecialOperatorsMixed);
TEST_FUNC(delimiters_lexing);
TEST_FUNC(lex_visibility_and_linkage_keywords);
TEST_FUNC(lex_compile_time_and_special_function_keywords);
TEST_FUNC(lex_miscellaneous_keywords);
TEST_FUNC(Lexer_ComprehensiveCrossGroup);
TEST_FUNC(Lexer_IdentifiersAndStrings);
TEST_FUNC(Lexer_ErrorConditions);
TEST_FUNC(Lexer_StringLiteral_EscapedCharacters);
TEST_FUNC(Lexer_StringLiteral_LongString);
TEST_FUNC(lex_missing_keywords);

// AST Node Tests
TEST_FUNC(ASTNode_IntegerLiteral);
TEST_FUNC(ASTNode_FloatLiteral);
TEST_FUNC(ASTNode_CharLiteral);
TEST_FUNC(ASTNode_StringLiteral);
TEST_FUNC(ASTNode_Identifier);
TEST_FUNC(ASTNode_UnaryOp);
TEST_FUNC(ASTNode_BinaryOp);
TEST_FUNC(ASTNode_ContainerDeclarations);
TEST_FUNC(ASTNode_ForStmt);
TEST_FUNC(ASTNode_SwitchExpr);


int main() {
    bool (*tests[])() = {
        test_basic_allocation,
        test_multiple_allocations,
        test_allocation_failure,
        test_reset,
        test_aligned_allocation,
        test_string_interning,
        test_dynamic_array_append,
        test_dynamic_array_growth,
        test_single_char_tokens,
        test_multi_char_tokens,
        test_assignment_vs_equality,
        test_skip_comments,
        test_nested_block_comments,
        test_unterminated_block_comment,
        test_Lexer_FloatSimpleDecimal,
        test_Lexer_FloatNoFractionalPart,
        test_Lexer_FloatNoIntegerPart,
        test_Lexer_FloatWithExponent,
        test_Lexer_FloatWithNegativeExponent,
        test_Lexer_FloatExponentNoSign,
        test_Lexer_FloatIntegerWithExponent,
        test_Lexer_FloatInvalidExponent,
        test_Lexer_FloatHexSimple,
        test_Lexer_FloatHexNoFractionalPart,
        test_Lexer_FloatHexNegativeExponent,
        test_Lexer_FloatHexInvalidFormat,
        test_IntegerLiterals,
        test_lex_arithmetic_and_bitwise_operators,
        test_lex_compound_assignment_operators,
        test_LexerSpecialOperators,
        test_LexerSpecialOperatorsMixed,
        test_delimiters_lexing,
        test_lex_visibility_and_linkage_keywords,
        test_lex_compile_time_and_special_function_keywords,
        test_lex_miscellaneous_keywords,
        test_Lexer_ComprehensiveCrossGroup,
        test_Lexer_IdentifiersAndStrings,
        test_Lexer_ErrorConditions,
        test_Lexer_StringLiteral_EscapedCharacters,
        test_Lexer_StringLiteral_LongString,
        test_lex_missing_keywords,
        // AST Tests
        test_ASTNode_IntegerLiteral,
        test_ASTNode_FloatLiteral,
        test_ASTNode_CharLiteral,
        test_ASTNode_StringLiteral,
        test_ASTNode_Identifier,
        test_ASTNode_UnaryOp,
        test_ASTNode_BinaryOp,
        test_ASTNode_ContainerDeclarations,
        test_ASTNode_ForStmt,
        test_ASTNode_SwitchExpr,
    };

    int passed = 0;
    int num_tests = sizeof(tests) / sizeof(tests[0]);

    for (int i = 0; i < num_tests; ++i) {
        if (tests[i]()) {
            passed++;
        }
    }

    printf("Passed %d/%d tests\n", passed, num_tests);
    return passed == num_tests ? 0 : 1;
}
