#include "../src/include/test_framework.hpp"
#include "../src/include/memory.hpp"
#include "../src/include/string_interner.hpp"
#include "../src/include/source_manager.hpp"
#include "../src/include/lexer.hpp"
#include "../src/include/parser.hpp"
#include "type_checker.hpp"
#include "test_utils.hpp"
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
#if defined(_WIN32)
    char command[512];
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

bool expect_parser_oom_abort(const char* source_code) {
    return run_test_in_child_process(source_code, "--run-parser-oom-test");
}

bool expect_statement_parser_abort(const char* source_code) {
    return run_test_in_child_process(source_code, "--run-statement-parser-test");
}

bool expect_type_checker_abort(const char* source_code) {
    return run_test_in_child_process(source_code, "--run-type-checker-test");
}

// Forward declarations for all test functions
TEST_FUNC(Parser_CopiedState_DoesNotCorruptSymbolTable);
TEST_FUNC(CompilationUnit_CreateParser_DoesNotReLex);
TEST_FUNC(TypeChecker_IntegerLiteralInference);
TEST_FUNC(TypeChecker_FloatLiteralInference);
TEST_FUNC(TypeChecker_CharLiteralInference);
TEST_FUNC(TypeChecker_StringLiteralInference);
TEST_FUNC(TypeChecker_RejectSlice);
TEST_FUNC(TypeChecker_RejectNonConstantArraySize);
TEST_FUNC(TypeChecker_AcceptsValidArrayDeclaration);
TEST_FUNC(TypeCheckerVoidTests_DisallowVoidVariableDeclaration);
TEST_FUNC(TypeCheckerVoidTests_ImplicitReturnInVoidFunction);
TEST_FUNC(TypeCheckerVoidTests_ExplicitReturnInVoidFunction);
TEST_FUNC(TypeCheckerVoidTests_ReturnValueInVoidFunction);
TEST_FUNC(TypeCheckerVoidTests_MissingReturnValueInNonVoidFunction);
TEST_FUNC(TypeCheckerVoidTests_ImplicitReturnInNonVoidFunction);
TEST_FUNC(TypeCheckerVoidTests_PointerAddition);
TEST_FUNC(TypeCheckerVoidTests_AllPathsReturnInNonVoidFunction);
TEST_FUNC(Parser_AbortOnAllocationFailure);
TEST_FUNC(Lexer_FloatWithUnderscores_IntegerPart);
TEST_FUNC(Lexer_FloatWithUnderscores_FractionalPart);
TEST_FUNC(Lexer_FloatWithUnderscores_ExponentPart);
TEST_FUNC(Lexer_FloatWithUnderscores_AllParts);
TEST_FUNC(DynamicArray_ShouldUseCopyConstructionOnReallocation);
TEST_FUNC(ArenaAllocator_AllocShouldReturn8ByteAligned);
TEST_FUNC(Parser_TokenStreamLifetimeIsIndependentOfParserObject);
TEST_FUNC(lexer_integer_overflow);
TEST_FUNC(lexer_c_string_literal);
TEST_FUNC(lexer_handles_tab_correctly);
TEST_FUNC(lexer_handles_unicode_correctly);
TEST_FUNC(lexer_handles_unterminated_char_hex_escape);
TEST_FUNC(lexer_handles_unterminated_string_hex_escape);
TEST_FUNC(lexer_handles_long_identifier);
TEST_FUNC(Lexer_HandlesLongIdentifier);
TEST_FUNC(Lexer_HandlesU64Integer);
TEST_FUNC(Lexer_UnterminatedCharHexEscape);
TEST_FUNC(Lexer_UnterminatedStringHexEscape);
TEST_FUNC(Lexer_NumericLookaheadSafety);
TEST_FUNC(Lexer_UnicodeInStringLiteral);
TEST_FUNC(arena_alloc_out_of_memory);
TEST_FUNC(arena_alloc_zero_size);
TEST_FUNC(arena_alloc_aligned_out_of_memory);
TEST_FUNC(arena_alloc_aligned_overflow_check);
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
TEST_FUNC(dynamic_array_non_pod_reallocation);
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
TEST_FUNC(Lexer_FloatExponentNoDigits);
TEST_FUNC(Lexer_FloatHexSimple);
TEST_FUNC(Lexer_FloatHexNoFractionalPart);
TEST_FUNC(Lexer_FloatHexNegativeExponent);
TEST_FUNC(Lexer_FloatHexInvalidFormat);
TEST_FUNC(IntegerLiterals);
TEST_FUNC(lex_arithmetic_and_bitwise_operators);
TEST_FUNC(Lexer_RangeExpression);
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
TEST_FUNC(Lexer_MultiLineIntegrationTest);

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
TEST_FUNC(Parser_RecursionLimit_Unary);
TEST_FUNC(Parser_RecursionLimit_Binary);
TEST_FUNC(compilation_unit_creation);
TEST_FUNC(compilation_unit_var_decl);
TEST_FUNC(Parser_CopyIsSafeAndDoesNotDoubleFree);
TEST_FUNC(SymbolBuilder_BuildsCorrectly);
TEST_FUNC(TypeResolution_ValidPrimitives);
TEST_FUNC(TypeResolution_InvalidOrUnsupported);
TEST_FUNC(TypeResolution_AllPrimitives);
TEST_FUNC(Parser_VarDecl_InsertsSymbolCorrectly);
TEST_FUNC(Parser_VarDecl_DetectsDuplicateSymbol);
TEST_FUNC(Parser_FnDecl_AndScopeManagement);
TEST_FUNC(Parser_NestedBlocks_AndShadowing);
TEST_FUNC(Parser_SymbolDoesNotLeakFromInnerScope);
TEST_FUNC(TypeCheckerValidDeclarations);
TEST_FUNC(TypeCheckerInvalidDeclarations);
TEST_FUNC(TypeCheckerUndeclaredVariable);
TEST_FUNC(TypeCheckerStringLiteralType);
TEST_FUNC(TypeCheckerIntegerLiteralType);
TEST_FUNC(TypeChecker_C89IntegerCompatibility);
TEST_FUNC(ReturnTypeValidation_Valid);
TEST_FUNC(ReturnTypeValidation_Invalid);
TEST_FUNC(TypeCompatibility);
TEST_FUNC(TypeChecker_VarDecl_Valid_Simple);
TEST_FUNC(TypeChecker_VarDecl_Invalid_Mismatch);
TEST_FUNC(TypeChecker_VarDecl_Valid_Widening);
TEST_FUNC(TypeChecker_VarDecl_Multiple_Errors);
TEST_FUNC(TypeToString_Reentrancy);
TEST_FUNC(TypeCheckerFnDecl_ValidSimpleParams);
TEST_FUNC(TypeCheckerFnDecl_InvalidParamType);
TEST_FUNC(TypeChecker_BoolLiteral);
TEST_FUNC(TypeChecker_IntegerLiteral);
TEST_FUNC(TypeChecker_CharLiteral);
TEST_FUNC(TypeChecker_StringLiteral);
TEST_FUNC(TypeChecker_Identifier);

// Binary Operator Type Checker Tests
TEST_FUNC(TypeCheckerBinaryOps_PointerArithmetic);
TEST_FUNC(TypeCheckerBinaryOps_NumericArithmetic);
TEST_FUNC(TypeCheckerBinaryOps_Comparison);
TEST_FUNC(TypeCheckerBinaryOps_Bitwise);
TEST_FUNC(TypeCheckerBinaryOps_Logical);

// C89 Compatibility Tests
TEST_FUNC(TypeCheckerC89Compat_RejectFunctionWithTooManyArgs);
// TEST_FUNC(TypeCheckerC89Compat_RejectFunctionPointerCall);
TEST_FUNC(TypeChecker_Call_WrongArgumentCount);
TEST_FUNC(TypeChecker_Call_IncompatibleArgumentType);
TEST_FUNC(TypeCheckerC89Compat_FloatWidening);

// Control Flow Type Checker Tests
TEST_FUNC(TypeCheckerControlFlow_IfStatementWithBooleanCondition);
TEST_FUNC(TypeCheckerControlFlow_IfStatementWithIntegerCondition);
TEST_FUNC(TypeCheckerControlFlow_IfStatementWithPointerCondition);
TEST_FUNC(TypeCheckerControlFlow_IfStatementWithFloatCondition);
TEST_FUNC(TypeCheckerControlFlow_IfStatementWithVoidCondition);
TEST_FUNC(TypeCheckerControlFlow_WhileStatementWithBooleanCondition);
TEST_FUNC(TypeCheckerControlFlow_WhileStatementWithIntegerCondition);
TEST_FUNC(TypeCheckerControlFlow_WhileStatementWithPointerCondition);
TEST_FUNC(TypeCheckerControlFlow_WhileStatementWithFloatCondition);
TEST_FUNC(TypeCheckerControlFlow_WhileStatementWithVoidCondition);

// Forward declarations for pointer type checker tests
TEST_FUNC(ParserBug_TopLevelUnion);
TEST_FUNC(ParserBug_TopLevelStruct);
TEST_FUNC(ParserBug_UnionFieldNodeType);
TEST_FUNC(TypeChecker_Dereference_ValidPointer);
TEST_FUNC(TypeChecker_Dereference_Invalid_NonPointer);
TEST_FUNC(TypeChecker_Dereference_ConstPointer);
TEST_FUNC(TypeChecker_AddressOf_Invalid_RValue);
TEST_FUNC(TypeChecker_AddressOf_Valid_LValues);
TEST_FUNC(TypeChecker_PointerIntegerAddition);
TEST_FUNC(TypeChecker_IntegerPointerAddition);
TEST_FUNC(TypeChecker_PointerIntegerSubtraction);
TEST_FUNC(TypeChecker_PointerPointerSubtraction);
TEST_FUNC(TypeChecker_Invalid_PointerPointerAddition);
TEST_FUNC(TypeChecker_Invalid_PointerPointerSubtraction_DifferentTypes);
TEST_FUNC(TypeChecker_Invalid_PointerMultiplication);

// C89 Type Mapping Tests
TEST_FUNC(C89TypeMapping_Validation);
TEST_FUNC(C89Compat_FunctionTypeValidation);

// Symbol Table Tests
TEST_FUNC(SymbolTable_DuplicateDetection);
TEST_FUNC(SymbolTable_NestedScopes_And_Lookup);
TEST_FUNC(SymbolTable_HashTableResize);

// Integer Literal Suffix Parsing Tests
TEST_FUNC(IntegerLiteralParsing_UnsignedSuffix);
TEST_FUNC(IntegerLiteralParsing_LongSuffix);
TEST_FUNC(IntegerLiteralParsing_UnsignedLongSuffix);
TEST_FUNC(TypeChecker_Bool_Literals);
TEST_FUNC(TypeChecker_Bool_ComparisonOps);
TEST_FUNC(TypeChecker_Bool_LogicalOps);
TEST_FUNC(TypeCheckerPointerOps_AddressOf_ValidLValue);
TEST_FUNC(TypeCheckerPointerOps_AddressOf_InvalidRValue);
TEST_FUNC(TypeCheckerPointerOps_Dereference_ValidPointer);
TEST_FUNC(TypeCheckerPointerOps_Dereference_InvalidNonPointer);
TEST_FUNC(TypeCheckerPointerOps_Arithmetic_PointerInteger);
TEST_FUNC(TypeCheckerPointerOps_Arithmetic_PointerPointer);
TEST_FUNC(TypeCheckerPointerOps_Arithmetic_InvalidOperations);
TEST_FUNC(TypeChecker_C89_StructFieldValidation_Slice);
TEST_FUNC(TypeChecker_C89_UnionFieldValidation_MultiLevelPointer);
TEST_FUNC(TypeChecker_C89_StructFieldValidation_ValidArray);
TEST_FUNC(TypeChecker_C89_UnionFieldValidation_ValidFields);
TEST_FUNC(TypeCheckerEnumTests_SignedIntegerOverflow);
TEST_FUNC(TypeCheckerEnumTests_SignedIntegerUnderflow);
TEST_FUNC(TypeCheckerEnumTests_UnsignedIntegerOverflow);
TEST_FUNC(TypeCheckerEnumTests_NegativeValueInUnsignedEnum);
TEST_FUNC(TypeCheckerEnumTests_AutoIncrementOverflow);
TEST_FUNC(TypeCheckerEnumTests_AutoIncrementSignedOverflow);
TEST_FUNC(TypeCheckerEnumTests_ValidValues);
TEST_FUNC(Parser_Bugfix_HandlesExpressionStatement);


// This function is executed in a child process by the error handling test.
// It sets up the parser and attempts to parse invalid code.
// The successful outcome is for the program to abort.
void run_parser_test_and_abort(const char* source_code, bool is_statement_test) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx(source_code, arena, interner);
    Parser* parser = ctx.getParser();

    if (is_statement_test) {
        parser->parseStatement();
    } else {
        parser->parseExpression();
    }

    // If we reach here, the parser did NOT abort as expected.
    // Exit with 0, which the parent process will interpret as a test failure.
    exit(0);
}

void run_parser_oom_test_and_abort(const char* source_code) {
    // An arena that is JUST big enough for tokenization of a simple expression,
    // but too small for the parser to allocate any AST nodes.
    // DynamicArray<Token> will request space for 8 tokens (8 * 24 = 192 bytes).
    // The first ASTNode allocation is 24 bytes.
    // So, an arena of size 200 should succeed for the token array, but fail
    // for the AST node.
    ArenaAllocator arena(200);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    ParserTestContext ctx(source_code, arena, interner);
    Parser* parser = ctx.getParser();

    parser->parseExpression();

    // If we reach here, the parser did NOT abort as expected.
    exit(0);
}

void run_type_checker_test_and_abort(const char* source_code) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source_code);
    Parser* parser = comp_unit.createParser(file_id);

    ASTNode* ast = parser->parse();

    TypeChecker type_checker(comp_unit);
    type_checker.check(ast);

    // If we reach here, the type checker did NOT abort.
    exit(0);
}


int main(int argc, char* argv[]) {
    // Check if the test runner is being invoked in the special mode
    // for testing parser errors.
    if (argc == 3 && strcmp(argv[1], "--run-parser-test") == 0) {
        run_parser_test_and_abort(argv[2], false);
        return 1; // Should be unreachable
    }

    if (argc == 3 && strcmp(argv[1], "--run-parser-oom-test") == 0) {
        run_parser_oom_test_and_abort(argv[2]);
        return 1; // Should be unreachable
    }

    if (argc == 3 && strcmp(argv[1], "--run-statement-parser-test") == 0) {
        run_parser_test_and_abort(argv[2], true);
        return 1; // Should be unreachable
    }

    if (argc == 3 && strcmp(argv[1], "--run-type-checker-test") == 0) {
        run_type_checker_test_and_abort(argv[2]);
        return 1; // Should be unreachable
    }


    // Normal test suite execution
    bool (*tests[])() = {
        // Group 1A: Memory Management
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
        // Group 1B: Core Components
        test_string_interning,
        test_compilation_unit_creation,
        test_compilation_unit_var_decl,
        test_SymbolBuilder_BuildsCorrectly,
        test_SymbolTable_DuplicateDetection,
        test_SymbolTable_NestedScopes_And_Lookup,
        test_SymbolTable_HashTableResize,
        // New tests
        test_Parser_CopiedState_DoesNotCorruptSymbolTable,
        test_CompilationUnit_CreateParser_DoesNotReLex,
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
