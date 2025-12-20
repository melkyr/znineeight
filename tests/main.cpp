#include "../src/include/test_framework.hpp"
#include "../src/include/memory.hpp"
#include "../src/include/string_interner.hpp"
#include "../src/include/source_manager.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/parser.hpp"
#include <cstring>
#include <cstdio>

#if defined(_WIN32)
#include <windows.h>
#else
#include <sys/wait.h>
#include <unistd.h>
#endif

// Helper function to run a parsing task in a separate process
// and check if it terminates as expected.
static bool run_test_in_child_process(const char* source_code, const char* test_type_flag) {
    char command[512];
#if defined(_WIN32)
    _snprintf(command, sizeof(command), "test_runner.exe %s \"%s\"", test_type_flag, source_code);
    command[sizeof(command) - 1] = '\0';

    STARTUPINFO si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));

    if (!CreateProcess(NULL, command, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        return false; // Failed to create process
    }

    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD exit_code;
    GetExitCodeProcess(pi.hProcess, &exit_code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return exit_code != 0;
#else
    // On Unix-like systems, use fork and exec.
    pid_t pid = fork();
    if (pid == 0) {
        // Child process: execute the test runner with the special arguments.
        // Suppress stdout/stderr to keep test output clean.
        freopen("/dev/null", "w", stdout);
        freopen("/dev/null", "w", stderr);
        execlp("./test_runner", "test_runner", test_type_flag, source_code, (char*)NULL);
        // If execlp returns, it means an error occurred.
        exit(127); // Exit with a special code to indicate exec failure.
    } else if (pid > 0) {
        // Parent process: wait for the child and check its exit status.
        int status;
        waitpid(pid, &status, 0);
        // We expect the child to be terminated by a signal (SIGABRT from abort()).
        // WIFSIGNALED will be true in this case.
        return WIFSIGNALED(status);
    }
    return false; // Fork failed.
#endif
}

bool expect_parser_abort(const char* source_code) {
    return run_test_in_child_process(source_code, "--run-parser-test");
}

bool expect_statement_parser_abort(const char* source_code) {
    return run_test_in_child_process(source_code, "--run-statement-parser-test");
}

// Forward declarations for all test functions
TEST_FUNC(symbol_table_insertion_and_lookup);
TEST_FUNC(parser_symbol_table_integration);
TEST_FUNC(Lexer_Delimiters);
TEST_FUNC(Lexer_DotOperators);
TEST_FUNC(Parser_ParseEmptyBlock);
TEST_FUNC(Parser_ParseBlockWithEmptyStatement);
TEST_FUNC(Parser_ParseBlockWithMultipleEmptyStatements);
TEST_FUNC(Parser_ParseBlockWithNestedEmptyBlock);
TEST_FUNC(Parser_ParseBlockWithMultipleNestedEmptyBlocks);
TEST_FUNC(Parser_ParseBlockWithNestedBlockAndEmptyStatement);
TEST_FUNC(Parser_ParsePrimaryExpr_IntegerLiteral);
TEST_FUNC(Parser_ParsePrimaryExpr_FloatLiteral);
TEST_FUNC(Parser_ParsePrimaryExpr_CharLiteral);
TEST_FUNC(Parser_ParsePrimaryExpr_StringLiteral);
TEST_FUNC(Parser_ParsePrimaryExpr_Identifier);
TEST_FUNC(Parser_ParsePrimaryExpr_ParenthesizedExpression);
TEST_FUNC(Parser_Error_OnUnexpectedToken);
TEST_FUNC(basic_allocation);
TEST_FUNC(multiple_allocations);
TEST_FUNC(allocation_failure);
TEST_FUNC(reset);
TEST_FUNC(aligned_allocation);
TEST_FUNC(string_interning);
TEST_FUNC(dynamic_array_append);
TEST_FUNC(dynamic_array_growth);
TEST_FUNC(dynamic_array_growth_from_zero);
TEST_FUNC(single_char_tokens);
TEST_FUNC(multi_char_tokens);
TEST_FUNC(token_fields_are_initialized);
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
TEST_FUNC(lex_visibility_and_linkage_keywords);
TEST_FUNC(lex_compile_time_and_special_function_keywords);
TEST_FUNC(lex_miscellaneous_keywords);
TEST_FUNC(Lexer_ComprehensiveCrossGroup);
TEST_FUNC(Lexer_IdentifiersAndStrings);
TEST_FUNC(Lexer_ErrorConditions);
TEST_FUNC(Lexer_StringLiteral_EscapedCharacters);
TEST_FUNC(Lexer_StringLiteral_LongString);
TEST_FUNC(lex_missing_keywords);
TEST_FUNC(IntegerRangeAmbiguity);

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
TEST_FUNC(Parser_Error_OnMissingColon);
TEST_FUNC(Parser_Struct_Error_MissingLBrace);
TEST_FUNC(Parser_Struct_Error_MissingRBrace);
TEST_FUNC(Parser_Struct_Error_MissingColon);
TEST_FUNC(Parser_Struct_Error_MissingType);
TEST_FUNC(Parser_Struct_Error_InvalidField);
TEST_FUNC(Parser_FnDecl_ValidEmpty);
TEST_FUNC(Parser_FnDecl_Error_NonEmptyParams);
TEST_FUNC(Parser_FnDecl_Error_NonEmptyBody);
TEST_FUNC(Parser_FnDecl_Error_MissingArrow);
TEST_FUNC(Parser_FnDecl_Error_MissingReturnType);
TEST_FUNC(Parser_FnDecl_Error_MissingParens);

TEST_FUNC(Parser_ErrDeferStatement_Simple);
TEST_FUNC(Parser_ErrDeferStatement_Error_MissingBlock);

// If Statement Parser Tests
TEST_FUNC(Parser_IfStatement_Simple);
TEST_FUNC(Parser_IfStatement_WithElse);
TEST_FUNC(Parser_IfStatement_Error_MissingLParen);
TEST_FUNC(Parser_IfStatement_Error_MissingRParen);
TEST_FUNC(Parser_IfStatement_Error_MissingThenBlock);
TEST_FUNC(Parser_IfStatement_Error_MissingElseBlock);

// Postfix Expression Parser Tests
TEST_FUNC(Parser_FunctionCall_NoArgs);
TEST_FUNC(Parser_FunctionCall_WithArgs);
TEST_FUNC(Parser_FunctionCall_WithTrailingComma);
TEST_FUNC(Parser_ArrayAccess);
TEST_FUNC(Parser_ChainedPostfixOps);

// Binary Expression Parser Tests
TEST_FUNC(Parser_BinaryExpr_SimplePrecedence);
TEST_FUNC(Parser_BinaryExpr_LeftAssociativity);
TEST_FUNC(Parser_BinaryExpr_Error_MissingRHS);

// Struct Parser Tests
TEST_FUNC(Parser_StructDeclaration_Simple);
TEST_FUNC(Parser_StructDeclaration_Empty);
TEST_FUNC(Parser_StructDeclaration_MultipleFields);
TEST_FUNC(Parser_StructDeclaration_WithTrailingComma);
TEST_FUNC(Parser_StructDeclaration_ComplexFieldType);

// Enum Parser Tests
TEST_FUNC(Parser_Enum_Empty);
TEST_FUNC(Parser_Enum_SimpleMembers);

// Try Expression Parser Tests
TEST_FUNC(Parser_TryExpr_Simple);
TEST_FUNC(Parser_TryExpr_Chained);
TEST_FUNC(Parser_TryExpr_InvalidSyntax);
TEST_FUNC(Parser_Enum_TrailingComma);
TEST_FUNC(Parser_Enum_WithValues);
TEST_FUNC(Parser_Enum_MixedMembers);
TEST_FUNC(Parser_Enum_WithBackingType);
TEST_FUNC(Parser_Enum_SyntaxError_MissingOpeningBrace);
TEST_FUNC(Parser_Enum_SyntaxError_MissingClosingBrace);
TEST_FUNC(Parser_Enum_SyntaxError_NoComma);
TEST_FUNC(Parser_Enum_SyntaxError_InvalidMember);
TEST_FUNC(Parser_Enum_SyntaxError_MissingInitializer);
TEST_FUNC(Parser_Enum_SyntaxError_BackingTypeNoParens);
TEST_FUNC(Parser_Enum_ComplexInitializer);

// Catch Expression Parser Tests
TEST_FUNC(Parser_CatchExpression_Simple);
TEST_FUNC(Parser_CatchExpression_WithPayload);
TEST_FUNC(Parser_CatchExpression_RightAssociativity);
TEST_FUNC(Parser_CatchExpression_Error_MissingElseExpr);
TEST_FUNC(Parser_CatchExpression_Error_IncompletePayload);
TEST_FUNC(Parser_CatchExpression_Error_MissingPipe);

// Comptime Block Parser Tests
TEST_FUNC(Parser_ComptimeBlock_Valid);
TEST_FUNC(Parser_ComptimeBlock_Error_MissingExpression);
TEST_FUNC(Parser_ComptimeBlock_Error_MissingOpeningBrace);
TEST_FUNC(Parser_ComptimeBlock_Error_MissingClosingBrace);

// Function Parser Tests
TEST_FUNC(Parser_NonEmptyFunctionBody);

// Parser Integration Tests
TEST_FUNC(ParserIntegration_VarDeclWithBinaryExpr);
TEST_FUNC(ParserIntegration_IfWithComplexCondition);
TEST_FUNC(ParserIntegration_WhileWithFunctionCall);
// TEST_FUNC(ParserIntegration_ForLoopOverSlice);
// TEST_FUNC(ParserIntegration_ComprehensiveFunction);
TEST_FUNC(ParserBug_LogicalOperatorSymbol);
TEST_FUNC(Parser_RecursionLimit);


// This function is executed in a child process by the error handling test.
// It sets up the parser and attempts to parse invalid code.
// The successful outcome is for the program to abort.
void run_parser_test_and_abort(const char* source_code, bool is_statement_test) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SourceManager src_manager(arena);
    u32 file_id = src_manager.addFile("test.zig", source_code, strlen(source_code));
    Lexer lexer(src_manager, interner, arena, file_id);

    DynamicArray<Token> tokens(arena);
    Token token;
    do {
        token = lexer.nextToken();
        tokens.append(token);
    } while (token.type != TOKEN_EOF);

    SymbolTable symbols(arena);
    Parser parser = ParserBuilder(tokens.getData(), tokens.length(), &arena, &symbols).build();
    if (is_statement_test) {
        parser.parseStatement();
    } else {
        parser.parseExpression();
    }

    // If we reach here, the parser did NOT abort as expected.
    // Exit with 0, which the parent process will interpret as a test failure.
    exit(0);
}

int main(int argc, char* argv[]) {
    // Check if the test runner is being invoked in the special mode
    // for testing parser errors.
    if (argc == 3 && strcmp(argv[1], "--run-parser-test") == 0) {
        run_parser_test_and_abort(argv[2], false);
        return 1; // Should be unreachable
    }

    if (argc == 3 && strcmp(argv[1], "--run-statement-parser-test") == 0) {
        run_parser_test_and_abort(argv[2], true);
        return 1; // Should be unreachable
    }


    // Normal test suite execution
    bool (*tests[])() = {
        test_symbol_table_insertion_and_lookup,
        test_parser_symbol_table_integration,
        test_basic_allocation,
        test_multiple_allocations,
        test_allocation_failure,
        test_reset,
        test_aligned_allocation,
        test_string_interning,
        test_dynamic_array_append,
        test_dynamic_array_growth,
        test_dynamic_array_growth_from_zero,
        test_single_char_tokens,
        test_multi_char_tokens,
        test_token_fields_are_initialized,
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
        test_Lexer_Delimiters,
        test_Lexer_DotOperators,
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
        test_Parser_Error_OnMissingColon,
        test_Parser_Struct_Error_MissingLBrace,
        test_Parser_Struct_Error_MissingRBrace,
        test_Parser_Struct_Error_MissingColon,
        test_Parser_Struct_Error_MissingType,
        test_Parser_Struct_Error_InvalidField,
        test_Parser_FnDecl_ValidEmpty,
        test_Parser_FnDecl_Error_NonEmptyParams,
        test_Parser_FnDecl_Error_NonEmptyBody,
        test_Parser_FnDecl_Error_MissingArrow,
        test_Parser_FnDecl_Error_MissingReturnType,
        test_Parser_FnDecl_Error_MissingParens,
        test_Parser_IfStatement_Simple,
        test_Parser_IfStatement_WithElse,
        test_Parser_IfStatement_Error_MissingLParen,
        test_Parser_IfStatement_Error_MissingRParen,
        test_Parser_IfStatement_Error_MissingThenBlock,
        test_Parser_IfStatement_Error_MissingElseBlock,
        test_Parser_ParseEmptyBlock,
        test_Parser_ParseBlockWithEmptyStatement,
        test_Parser_ParseBlockWithMultipleEmptyStatements,
        test_Parser_ParseBlockWithNestedEmptyBlock,
        test_Parser_ParseBlockWithMultipleNestedEmptyBlocks,
        test_Parser_ParseBlockWithNestedBlockAndEmptyStatement,
        // Expression Parser tests
        test_Parser_ParsePrimaryExpr_IntegerLiteral,
        test_Parser_ParsePrimaryExpr_FloatLiteral,
        test_Parser_ParsePrimaryExpr_CharLiteral,
        test_Parser_ParsePrimaryExpr_StringLiteral,
        test_Parser_ParsePrimaryExpr_Identifier,
        test_Parser_ParsePrimaryExpr_ParenthesizedExpression,
        test_Parser_Error_OnUnexpectedToken,
        // Postfix Expression Parser tests
        test_Parser_FunctionCall_NoArgs,
        test_Parser_FunctionCall_WithArgs,
        test_Parser_FunctionCall_WithTrailingComma,
        test_Parser_ArrayAccess,
        test_Parser_ChainedPostfixOps,
        // Binary Expression Parser tests
        test_Parser_BinaryExpr_SimplePrecedence,
        test_Parser_BinaryExpr_LeftAssociativity,
        test_Parser_BinaryExpr_Error_MissingRHS,

        // Struct Parser tests
        test_Parser_StructDeclaration_Simple,
        test_Parser_StructDeclaration_Empty,
        test_Parser_StructDeclaration_MultipleFields,
        test_Parser_StructDeclaration_WithTrailingComma,
        test_Parser_StructDeclaration_ComplexFieldType,

        // Enum Parser Tests
        test_Parser_Enum_Empty,
        test_Parser_Enum_SimpleMembers,
        test_Parser_Enum_TrailingComma,
        test_Parser_Enum_WithValues,
        test_Parser_Enum_MixedMembers,
        test_Parser_Enum_WithBackingType,
        test_Parser_Enum_SyntaxError_MissingOpeningBrace,
        test_Parser_Enum_SyntaxError_MissingClosingBrace,
        test_Parser_Enum_SyntaxError_NoComma,
        test_Parser_Enum_SyntaxError_InvalidMember,
        test_Parser_Enum_SyntaxError_MissingInitializer,
        test_Parser_Enum_SyntaxError_BackingTypeNoParens,
        test_Parser_Enum_ComplexInitializer,

        // Try Expression Parser tests
        test_Parser_TryExpr_Simple,
        test_Parser_TryExpr_Chained,
        test_Parser_TryExpr_InvalidSyntax,

        // Catch Expression Parser tests
        test_Parser_CatchExpression_Simple,
        test_Parser_CatchExpression_WithPayload,
        test_Parser_CatchExpression_RightAssociativity,
        test_Parser_CatchExpression_Error_MissingElseExpr,
        test_Parser_CatchExpression_Error_IncompletePayload,
        test_Parser_CatchExpression_Error_MissingPipe,
        test_Parser_ErrDeferStatement_Simple,
        test_Parser_ErrDeferStatement_Error_MissingBlock,

        // Comptime block tests
        test_Parser_ComptimeBlock_Valid,
        test_Parser_ComptimeBlock_Error_MissingExpression,
        test_Parser_ComptimeBlock_Error_MissingOpeningBrace,
        test_Parser_ComptimeBlock_Error_MissingClosingBrace,

        // Function Parser Tests
        test_Parser_NonEmptyFunctionBody,

        // Parser Integration Tests
        test_ParserIntegration_VarDeclWithBinaryExpr,
        test_ParserIntegration_IfWithComplexCondition,
        test_ParserIntegration_WhileWithFunctionCall,
        // test_ParserIntegration_ForLoopOverSlice,
        // test_ParserIntegration_ComprehensiveFunction,
        test_ParserBug_LogicalOperatorSymbol,
        test_Parser_RecursionLimit,
        test_IntegerRangeAmbiguity,
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
