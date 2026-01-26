#include "../src/include/test_framework.hpp"
#include "test_utils.hpp"
#include <cstdio>
#include <cstring>
#include <cstdlib>

// Helper function to read source from a temporary file for child process
static char* read_source_from_file(const char* path) {
    FILE* file = fopen(path, "rb");
    if (!file) return NULL;
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    fseek(file, 0, SEEK_SET);
    char* buffer = (char*)malloc(length + 1);
    if (!buffer) {
        fclose(file);
        return NULL;
    }
    fread(buffer, 1, length, file);
    buffer[length] = '\0';
    fclose(file);
    return buffer;
}


// Forward declarations for Group 1A: Memory Management
TEST_FUNC(DynamicArray_ShouldUseCopyConstructionOnReallocation);
TEST_FUNC(ArenaAllocator_AllocShouldReturn8ByteAligned);
TEST_FUNC(arena_alloc_out_of_memory);
TEST_FUNC(arena_alloc_zero_size);
TEST_FUNC(arena_alloc_aligned_out_of_memory);
TEST_FUNC(arena_alloc_aligned_overflow_check);
TEST_FUNC(basic_allocation);
TEST_FUNC(multiple_allocations);
TEST_FUNC(allocation_failure);
TEST_FUNC(reset);
TEST_FUNC(aligned_allocation);
TEST_FUNC(dynamic_array_append);
TEST_FUNC(dynamic_array_growth);
TEST_FUNC(dynamic_array_growth_from_zero);
TEST_FUNC(dynamic_array_non_pod_reallocation);
#ifdef DEBUG
TEST_FUNC(simple_itoa_conversion);
#endif
// Forward declarations for Group 1B: Core Components
TEST_FUNC(string_interning);
TEST_FUNC(compilation_unit_creation);
TEST_FUNC(compilation_unit_var_decl);
TEST_FUNC(SymbolBuilder_BuildsCorrectly);
TEST_FUNC(SymbolTable_DuplicateDetection);
TEST_FUNC(SymbolTable_NestedScopes_And_Lookup);
TEST_FUNC(SymbolTable_HashTableResize);

// Forward declarations for Group 2A: Float Literals
TEST_FUNC(Lexer_FloatWithUnderscores_IntegerPart);
TEST_FUNC(Lexer_FloatWithUnderscores_FractionalPart);
TEST_FUNC(Lexer_FloatWithUnderscores_ExponentPart);
TEST_FUNC(Lexer_FloatWithUnderscores_AllParts);
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

// Forward declarations for Group 2B: Integer & String Literals
TEST_FUNC(lexer_integer_overflow);
TEST_FUNC(lexer_c_string_literal);
TEST_FUNC(lexer_handles_unicode_correctly);
TEST_FUNC(lexer_handles_unterminated_char_hex_escape);
TEST_FUNC(lexer_handles_unterminated_string_hex_escape);
TEST_FUNC(Lexer_HandlesU64Integer);
TEST_FUNC(Lexer_UnterminatedCharHexEscape);
TEST_FUNC(Lexer_UnterminatedStringHexEscape);
TEST_FUNC(Lexer_UnicodeInStringLiteral);
TEST_FUNC(IntegerLiterals);
TEST_FUNC(Lexer_StringLiteral_EscapedCharacters);
TEST_FUNC(Lexer_StringLiteral_LongString);
TEST_FUNC(IntegerLiteralParsing_UnsignedSuffix);
TEST_FUNC(IntegerLiteralParsing_LongSuffix);
TEST_FUNC(IntegerLiteralParsing_UnsignedLongSuffix);

// Forward declarations for Group 2C: Operators & Delimiters
TEST_FUNC(single_char_tokens);
TEST_FUNC(multi_char_tokens);
TEST_FUNC(assignment_vs_equality);
TEST_FUNC(lex_arithmetic_and_bitwise_operators);
TEST_FUNC(Lexer_RangeExpression);
TEST_FUNC(lex_compound_assignment_operators);
TEST_FUNC(LexerSpecialOperators);
TEST_FUNC(LexerSpecialOperatorsMixed);
TEST_FUNC(Lexer_Delimiters);
TEST_FUNC(Lexer_DotOperators);

// Forward declarations for Group 2D: Keywords & Comments
TEST_FUNC(skip_comments);
TEST_FUNC(nested_block_comments);
TEST_FUNC(unterminated_block_comment);
TEST_FUNC(lex_visibility_and_linkage_keywords);
TEST_FUNC(lex_compile_time_and_special_function_keywords);
TEST_FUNC(lex_miscellaneous_keywords);
TEST_FUNC(lex_missing_keywords);

// Forward declarations for Group 2E: Identifiers, Integration & Edge Cases
TEST_FUNC(lexer_handles_tab_correctly);
TEST_FUNC(lexer_handles_long_identifier);
TEST_FUNC(Lexer_HandlesLongIdentifier);
TEST_FUNC(Lexer_NumericLookaheadSafety);
TEST_FUNC(token_fields_are_initialized);
TEST_FUNC(Lexer_ComprehensiveCrossGroup);
TEST_FUNC(Lexer_IdentifiersAndStrings);
TEST_FUNC(Lexer_ErrorConditions);
TEST_FUNC(IntegerRangeAmbiguity);
TEST_FUNC(Lexer_MultiLineIntegrationTest);

// Forward declarations for Group 3A: Basic AST Nodes & Primary Expressions
TEST_FUNC(ASTNode_IntegerLiteral);
TEST_FUNC(ASTNode_FloatLiteral);
TEST_FUNC(ASTNode_CharLiteral);
TEST_FUNC(ASTNode_StringLiteral);
TEST_FUNC(ASTNode_Identifier);
TEST_FUNC(ASTNode_UnaryOp);
TEST_FUNC(ASTNode_BinaryOp);
TEST_FUNC(Parser_ParsePrimaryExpr_IntegerLiteral);
TEST_FUNC(Parser_ParsePrimaryExpr_FloatLiteral);
TEST_FUNC(Parser_ParsePrimaryExpr_CharLiteral);
TEST_FUNC(Parser_ParsePrimaryExpr_StringLiteral);
TEST_FUNC(Parser_ParsePrimaryExpr_Identifier);
TEST_FUNC(Parser_ParsePrimaryExpr_ParenthesizedExpression);

// Forward declarations for Group 3B: Postfix, Binary & Advanced Expressions
TEST_FUNC(Parser_FunctionCall_NoArgs);
TEST_FUNC(Parser_FunctionCall_WithArgs);
TEST_FUNC(Parser_FunctionCall_WithTrailingComma);
TEST_FUNC(Parser_ArrayAccess);
TEST_FUNC(Parser_ChainedPostfixOps);
TEST_FUNC(Parser_CompoundAssignment_Simple);
TEST_FUNC(Parser_CompoundAssignment_AllOperators);
TEST_FUNC(Parser_CompoundAssignment_RightAssociativity);
TEST_FUNC(Parser_CompoundAssignment_ComplexRHS);
TEST_FUNC(Parser_BinaryExpr_SimplePrecedence);
TEST_FUNC(Parser_BinaryExpr_LeftAssociativity);
TEST_FUNC(Parser_TryExpr_Simple);
TEST_FUNC(Parser_TryExpr_Chained);
TEST_FUNC(Parser_CatchExpression_Simple);
TEST_FUNC(Parser_CatchExpression_WithPayload);
TEST_FUNC(Parser_CatchExpression_MixedAssociativity);
TEST_FUNC(Parser_Orelse_IsLeftAssociative);
TEST_FUNC(Parser_Catch_IsLeftAssociative);
TEST_FUNC(Parser_CatchExpr_Simple);
TEST_FUNC(Parser_CatchExpr_LeftAssociativity);
TEST_FUNC(Parser_CatchExpr_MixedAssociativity);
TEST_FUNC(Parser_OrelseExpr_Simple);
TEST_FUNC(Parser_OrelseExpr_LeftAssociativity);
TEST_FUNC(Parser_OrelseExpr_Precedence);


// Forward declarations for Group 3C: Struct & Union Declarations
TEST_FUNC(ASTNode_ContainerDeclarations);
TEST_FUNC(Parser_Struct_Error_MissingLBrace);
TEST_FUNC(Parser_Struct_Error_MissingRBrace);
TEST_FUNC(Parser_Struct_Error_MissingColon);
TEST_FUNC(Parser_Struct_Error_MissingType);
TEST_FUNC(Parser_Struct_Error_InvalidField);
TEST_FUNC(Parser_StructDeclaration_Simple);
TEST_FUNC(Parser_StructDeclaration_Empty);
TEST_FUNC(Parser_StructDeclaration_MultipleFields);
TEST_FUNC(Parser_StructDeclaration_WithTrailingComma);
TEST_FUNC(Parser_StructDeclaration_ComplexFieldType);
TEST_FUNC(ParserBug_TopLevelUnion);
TEST_FUNC(ParserBug_TopLevelStruct);
TEST_FUNC(ParserBug_UnionFieldNodeType);

// Forward declarations for Group 3D: Enum Declarations
TEST_FUNC(Parser_Enum_Empty);
TEST_FUNC(Parser_Enum_SimpleMembers);
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

// Forward declarations for Group 3E: Function & Variable Declarations
TEST_FUNC(Parser_FnDecl_ValidEmpty);
TEST_FUNC(Parser_FnDecl_Valid_NoArrow);
TEST_FUNC(Parser_FnDecl_Error_MissingReturnType);
TEST_FUNC(Parser_FnDecl_Error_MissingParens);
TEST_FUNC(Parser_NonEmptyFunctionBody);
TEST_FUNC(Parser_VarDecl_InsertsSymbolCorrectly);
TEST_FUNC(Parser_VarDecl_DetectsDuplicateSymbol);
TEST_FUNC(Parser_FnDecl_AndScopeManagement);

// Forward declarations for Group 3F: Control Flow & Blocks
TEST_FUNC(ASTNode_ForStmt);
TEST_FUNC(ASTNode_SwitchExpr);
TEST_FUNC(Parser_IfStatement_Simple);
TEST_FUNC(Parser_IfStatement_WithElse);
TEST_FUNC(Parser_ParseEmptyBlock);
TEST_FUNC(Parser_ParseBlockWithEmptyStatement);
TEST_FUNC(Parser_ParseBlockWithMultipleEmptyStatements);
TEST_FUNC(Parser_ParseBlockWithNestedEmptyBlock);
TEST_FUNC(Parser_ParseBlockWithMultipleNestedEmptyBlocks);
TEST_FUNC(Parser_ParseBlockWithNestedBlockAndEmptyStatement);
TEST_FUNC(Parser_ErrDeferStatement_Simple);
TEST_FUNC(Parser_ComptimeBlock_Valid);
TEST_FUNC(Parser_NestedBlocks_AndShadowing);
TEST_FUNC(Parser_SymbolDoesNotLeakFromInnerScope);

// Forward declarations for Group 3G: Parser Error Handling
TEST_FUNC(Parser_Error_OnUnexpectedToken);
TEST_FUNC(Parser_Error_OnMissingColon);
TEST_FUNC(Parser_IfStatement_Error_MissingLParen);
TEST_FUNC(Parser_IfStatement_Error_MissingRParen);
TEST_FUNC(Parser_IfStatement_Error_MissingThenBlock);
TEST_FUNC(Parser_IfStatement_Error_MissingElseBlock);
TEST_FUNC(Parser_BinaryExpr_Error_MissingRHS);
TEST_FUNC(Parser_TryExpr_InvalidSyntax);
TEST_FUNC(Parser_CatchExpression_Error_MissingElseExpr);
TEST_FUNC(Parser_CatchExpression_Error_IncompletePayload);
TEST_FUNC(Parser_CatchExpression_Error_MissingPipe);
TEST_FUNC(Parser_ErrDeferStatement_Error_MissingBlock);
TEST_FUNC(Parser_ComptimeBlock_Error_MissingExpression);
TEST_FUNC(Parser_ComptimeBlock_Error_MissingOpeningBrace);
TEST_FUNC(Parser_ComptimeBlock_Error_MissingClosingBrace);

// Forward declarations for Group 3H: Integration, Bugs, and Edge Cases
TEST_FUNC(Parser_AbortOnAllocationFailure);
TEST_FUNC(Parser_TokenStreamLifetimeIsIndependentOfParserObject);
TEST_FUNC(ParserIntegration_VarDeclWithBinaryExpr);
TEST_FUNC(ParserIntegration_IfWithComplexCondition);
TEST_FUNC(ParserIntegration_WhileWithFunctionCall);
TEST_FUNC(ParserBug_LogicalOperatorSymbol);
TEST_FUNC(Parser_RecursionLimit);
TEST_FUNC(Parser_RecursionLimit_Unary);
TEST_FUNC(Parser_RecursionLimit_Binary);
TEST_FUNC(Parser_CopyIsSafeAndDoesNotDoubleFree);
TEST_FUNC(Parser_Bugfix_HandlesExpressionStatement);

// Forward declarations for Group 4A: Literal & Primitive Type Inference
TEST_FUNC(TypeChecker_IntegerLiteralInference);
TEST_FUNC(TypeChecker_FloatLiteralInference);
TEST_FUNC(TypeChecker_CharLiteralInference);
TEST_FUNC(TypeChecker_StringLiteralInference);
TEST_FUNC(TypeCheckerStringLiteralType);
TEST_FUNC(TypeCheckerIntegerLiteralType);
TEST_FUNC(TypeChecker_C89IntegerCompatibility);
TEST_FUNC(TypeResolution_ValidPrimitives);
TEST_FUNC(TypeResolution_InvalidOrUnsupported);
TEST_FUNC(TypeResolution_AllPrimitives);
TEST_FUNC(TypeChecker_BoolLiteral);
TEST_FUNC(TypeChecker_IntegerLiteral);
TEST_FUNC(TypeChecker_CharLiteral);
TEST_FUNC(TypeChecker_StringLiteral);
TEST_FUNC(TypeChecker_Identifier);

// Forward declarations for Group 4B: Variable Declaration & Scope
TEST_FUNC(TypeCheckerValidDeclarations);
TEST_FUNC(TypeCheckerInvalidDeclarations);
TEST_FUNC(TypeCheckerUndeclaredVariable);
TEST_FUNC(TypeChecker_VarDecl_Valid_Simple);
TEST_FUNC(TypeChecker_VarDecl_Invalid_Mismatch);
TEST_FUNC(TypeChecker_VarDecl_Invalid_Widening);
TEST_FUNC(TypeChecker_VarDecl_Multiple_Errors);

// Forward declarations for Group 4C: Function Declarations & Return Validation
TEST_FUNC(ReturnTypeValidation_Valid);
TEST_FUNC(ReturnTypeValidation_Invalid);
TEST_FUNC(TypeCheckerFnDecl_ValidSimpleParams);
TEST_FUNC(TypeCheckerFnDecl_InvalidParamType);
TEST_FUNC(TypeCheckerVoidTests_ImplicitReturnInVoidFunction);
TEST_FUNC(TypeCheckerVoidTests_ExplicitReturnInVoidFunction);
TEST_FUNC(TypeCheckerVoidTests_ReturnValueInVoidFunction);
TEST_FUNC(TypeCheckerVoidTests_MissingReturnValueInNonVoidFunction);
TEST_FUNC(TypeCheckerVoidTests_ImplicitReturnInNonVoidFunction);
TEST_FUNC(TypeCheckerVoidTests_AllPathsReturnInNonVoidFunction);

// Forward declarations for Group 4D: Pointer Operations
TEST_FUNC(TypeChecker_AddressOf_RValueLiteral);
TEST_FUNC(TypeChecker_AddressOf_RValueExpression);
TEST_FUNC(TypeChecker_Dereference_ValidPointer);
TEST_FUNC(TypeChecker_Dereference_Invalid_NonPointer);
TEST_FUNC(TypeChecker_Dereference_VoidPointer);
TEST_FUNC(TypeChecker_Dereference_NullLiteral);
TEST_FUNC(TypeChecker_Dereference_ZeroLiteral);
TEST_FUNC(TypeChecker_Dereference_NestedPointer);
TEST_FUNC(TypeChecker_Dereference_ConstPointer);
TEST_FUNC(TypeChecker_AddressOf_Valid_LValues);
TEST_FUNC(TypeCheckerPointerOps_AddressOf_ValidLValue);
TEST_FUNC(TypeCheckerPointerOps_Dereference_ValidPointer);
TEST_FUNC(TypeCheckerPointerOps_Dereference_InvalidNonPointer);

// Forward declarations for Group 4E: Pointer Arithmetic
TEST_FUNC(TypeChecker_PointerArithmetic_ValidCases_ExplicitTyping);
TEST_FUNC(TypeChecker_PointerArithmetic_InvalidCases_ExplicitTyping);
TEST_FUNC(TypeCheckerVoidTests_PointerAddition);
TEST_FUNC(TypeChecker_PointerIntegerAddition);
TEST_FUNC(TypeChecker_IntegerPointerAddition);
TEST_FUNC(TypeChecker_PointerIntegerSubtraction);
TEST_FUNC(TypeChecker_PointerPointerSubtraction);
TEST_FUNC(TypeChecker_Invalid_PointerPointerAddition);
TEST_FUNC(TypeChecker_Invalid_PointerPointerSubtraction_DifferentTypes);
TEST_FUNC(TypeChecker_Invalid_PointerMultiplication);
TEST_FUNC(TypeCheckerPointerOps_Arithmetic_PointerInteger);
TEST_FUNC(TypeCheckerPointerOps_Arithmetic_PointerPointer);
TEST_FUNC(TypeCheckerPointerOps_Arithmetic_InvalidOperations);

// Forward declarations for Group 4F: Binary & Logical Operations
TEST_FUNC(TypeCheckerBinaryOps_PointerArithmetic);
TEST_FUNC(TypeCheckerBinaryOps_NumericArithmetic);
TEST_FUNC(TypeCheckerBinaryOps_Comparison);
TEST_FUNC(TypeCheckerBinaryOps_Bitwise);
TEST_FUNC(TypeCheckerBinaryOps_Logical);
TEST_FUNC(TypeChecker_Bool_ComparisonOps);
TEST_FUNC(TypeChecker_Bool_LogicalOps);

// Forward declarations for Group 4G: Control Flow (if, while)
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

// Forward declarations for Group 4H: Container & Enum Validation
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

// Forward declarations for Group 4I: C89 Compatibility & Misc
TEST_FUNC(TypeChecker_ArrayAccessInBoundsWithNamedConstant);
TEST_FUNC(TypeChecker_RejectSlice);
TEST_FUNC(TypeChecker_ArrayAccessInBounds);
TEST_FUNC(TypeChecker_ArrayAccessOutOfBoundsPositive);
TEST_FUNC(TypeChecker_ArrayAccessOutOfBoundsNegative);
TEST_FUNC(TypeChecker_ArrayAccessOutOfBoundsExpression);
TEST_FUNC(TypeChecker_ArrayAccessWithVariable);
TEST_FUNC(TypeChecker_IndexingNonArray);
TEST_FUNC(TypeChecker_ArrayAccessWithNamedConstant);
TEST_FUNC(Assignment_IncompatiblePointers_Invalid);
TEST_FUNC(Assignment_ConstPointerToPointer_Invalid);
TEST_FUNC(Assignment_PointerToConstPointer_Valid);
TEST_FUNC(Assignment_VoidPointerToPointer_Invalid);
TEST_FUNC(Assignment_PointerToVoidPointer_Valid);
TEST_FUNC(Assignment_PointerExactMatch_Valid);
TEST_FUNC(Assignment_NullToPointer_Valid);
TEST_FUNC(Assignment_NumericWidening_Fails);
TEST_FUNC(Assignment_ExactNumericMatch);
TEST_FUNC(TypeChecker_RejectNonConstantArraySize);
TEST_FUNC(TypeChecker_AcceptsValidArrayDeclaration);
TEST_FUNC(TypeCheckerVoidTests_DisallowVoidVariableDeclaration);
TEST_FUNC(TypeCompatibility);
TEST_FUNC(TypeToString_Reentrancy);
TEST_FUNC(TypeCheckerC89Compat_RejectFunctionWithTooManyArgs);
TEST_FUNC(TypeChecker_Call_WrongArgumentCount);
TEST_FUNC(TypeChecker_Call_IncompatibleArgumentType);
TEST_FUNC(TypeCheckerC89Compat_FloatWidening_Fails);
TEST_FUNC(C89TypeMapping_Validation);
TEST_FUNC(C89Compat_FunctionTypeValidation);
TEST_FUNC(TypeChecker_Bool_Literals);
TEST_FUNC(TypeChecker_CompoundAssignment_Valid);
TEST_FUNC(TypeChecker_CompoundAssignment_InvalidLValue);
TEST_FUNC(TypeChecker_CompoundAssignment_Bitwise);
TEST_FUNC(TypeChecker_CompoundAssignment_PointerArithmetic);
TEST_FUNC(TypeChecker_CompoundAssignment_InvalidTypes);
TEST_FUNC(DoubleFreeAnalyzer_CompoundAssignment);

// Forward declarations for Memory Stability Tests
TEST_FUNC(MemoryStability_TokenSupplierDanglingPointer);

// Forward declarations for C89 Rejection Tests
#include "type_checker_slice_expression_test.cpp"
TEST_FUNC(C89Rejection_Slice);
TEST_FUNC(C89Rejection_TryExpression);
TEST_FUNC(C89Rejection_CatchExpression);
TEST_FUNC(C89Rejection_OrelseExpression);
TEST_FUNC(TypeChecker_RejectSliceExpression);

// Bug Fix Verification Tests
TEST_FUNC(dynamic_array_destructor_fix);

// Forward declarations for Symbol Flags
#include "test_symbol_flags.cpp"
TEST_FUNC(SymbolFlags_GlobalVariable);
TEST_FUNC(SymbolFlags_SymbolBuilder);

// Forward declarations for Task 119
#include "task_119_test.cpp"
#include "test_utils_bug.cpp"
TEST_FUNC(safe_append_null_termination);
TEST_FUNC(safe_append_explicit_check);
TEST_FUNC(simple_itoa_null_termination);
TEST_FUNC(Task119_DetectMalloc);
TEST_FUNC(Task119_DetectCalloc);
TEST_FUNC(Task119_DetectRealloc);
TEST_FUNC(Task119_DetectFree);
TEST_FUNC(Task119_DetectAlignedAlloc);
TEST_FUNC(Task119_DetectStrdup);
TEST_FUNC(Task119_DetectMemcpy);
TEST_FUNC(Task119_DetectMemset);
TEST_FUNC(Task119_DetectStrcpy);

// Forward declarations for Lifetime Analysis
#include "lifetime_analysis_tests.cpp"
TEST_FUNC(Lifetime_DirectReturnLocalAddress);
TEST_FUNC(Lifetime_ReturnLocalPointer);
TEST_FUNC(Lifetime_ReturnParamOK);
TEST_FUNC(Lifetime_ReturnAddrOfParam);
TEST_FUNC(Lifetime_ReturnGlobalOK);
TEST_FUNC(Lifetime_ReassignedPointerOK);

// Forward declarations for Null Pointer Analysis
#include "null_pointer_analysis_tests.cpp"
TEST_FUNC(NullPointerAnalyzer_BasicTracking);
TEST_FUNC(NullPointerAnalyzer_PersistentStateTracking);
TEST_FUNC(NullPointerAnalyzer_AssignmentTracking);
TEST_FUNC(NullPointerAnalyzer_IfNullGuard);
TEST_FUNC(NullPointerAnalyzer_IfElseMerge);
TEST_FUNC(NullPointerAnalyzer_WhileGuard);
TEST_FUNC(NullPointerAnalyzer_WhileConservativeReset);
TEST_FUNC(NullPointerAnalyzer_Shadowing);
TEST_FUNC(NullPointerAnalyzer_NoLeakage);

// Forward declarations for Integration Tests
#include "integration_tests.cpp"
TEST_FUNC(Integration_FullPipeline);
TEST_FUNC(Integration_CorrectUsage);

// Forward declarations for Double Free Analysis
#include "double_free_analysis_tests.cpp"
#include "test_double_free_locations.cpp"
#include "test_double_free_task_129.cpp"
#include "test_double_free_path_aware.cpp"
TEST_FUNC(DoubleFree_SimpleDoubleFree);
TEST_FUNC(DoubleFree_BasicTracking);
TEST_FUNC(DoubleFree_UninitializedFree);
TEST_FUNC(DoubleFree_MemoryLeak);
TEST_FUNC(DoubleFree_DeferDoubleFree);
TEST_FUNC(DoubleFree_ReassignmentLeak);
TEST_FUNC(DoubleFree_NullReassignmentLeak);
TEST_FUNC(DoubleFree_ReturnExempt);
TEST_FUNC(DoubleFree_SwitchAnalysis);
TEST_FUNC(DoubleFree_TryAnalysis);
TEST_FUNC(DoubleFree_TryAnalysisComplex);
TEST_FUNC(DoubleFree_CatchAnalysis);
TEST_FUNC(DoubleFree_BinaryOpAnalysis);
TEST_FUNC(DoubleFree_LocationInLeakWarning);
TEST_FUNC(DoubleFree_LocationInReassignmentLeak);
TEST_FUNC(DoubleFree_LocationInDoubleFreeError);
TEST_FUNC(DoubleFree_TransferTracking);
TEST_FUNC(DoubleFree_DeferContextInError);
TEST_FUNC(DoubleFree_ErrdeferContextInError);
TEST_FUNC(DoubleFree_IfElseBranching);
TEST_FUNC(DoubleFree_IfElseBothFree);
TEST_FUNC(DoubleFree_WhileConservative);
#include "test_task_130_switch.cpp"
TEST_FUNC(DoubleFree_SwitchPathAware);
TEST_FUNC(DoubleFree_SwitchBothFree);
#include "test_task_130_error_handling.cpp"
TEST_FUNC(DoubleFree_TryPathAware);
TEST_FUNC(DoubleFree_CatchPathAware);
TEST_FUNC(DoubleFree_OrelsePathAware);
#include "test_task_130_loops.cpp"
TEST_FUNC(DoubleFree_LoopConservativeVerification);


int main(int argc, char* argv[]) {
    if (argc == 3) {
        const char* flag = argv[1];
        const char* filepath = argv[2];
        char* source = read_source_from_file(filepath);
        if (!source) {
            fprintf(stderr, "Failed to read source file in child process: %s\n", filepath);
            return 1;
        }

        if (strcmp(flag, "--run_parser_test") == 0) {
            run_parser_test_in_child(source);
        } else if (strcmp(flag, "--run_type_checker_test") == 0) {
            run_type_checker_test_in_child(source);
        }

        free(source);
        return 0; // Child process should exit after running the test
    }


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
        test_simple_itoa_conversion,
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
        test_Lexer_MultiLineIntegrationTest,
        // Group 3A
        test_ASTNode_IntegerLiteral,
        test_ASTNode_FloatLiteral,
        test_ASTNode_CharLiteral,
        test_ASTNode_StringLiteral,
        test_ASTNode_Identifier,
        test_ASTNode_UnaryOp,
        test_ASTNode_BinaryOp,
        test_Parser_ParsePrimaryExpr_IntegerLiteral,
        test_Parser_ParsePrimaryExpr_FloatLiteral,
        test_Parser_ParsePrimaryExpr_CharLiteral,
        test_Parser_ParsePrimaryExpr_StringLiteral,
        test_Parser_ParsePrimaryExpr_Identifier,
        test_Parser_ParsePrimaryExpr_ParenthesizedExpression,
        // Group 3B
        test_Parser_FunctionCall_NoArgs,
        test_Parser_FunctionCall_WithArgs,
        test_Parser_FunctionCall_WithTrailingComma,
        test_Parser_ArrayAccess,
        test_Parser_ChainedPostfixOps,
        test_Parser_CompoundAssignment_Simple,
        test_Parser_CompoundAssignment_AllOperators,
        test_Parser_CompoundAssignment_RightAssociativity,
        test_Parser_CompoundAssignment_ComplexRHS,
        test_Parser_BinaryExpr_SimplePrecedence,
        test_Parser_BinaryExpr_LeftAssociativity,
        test_Parser_TryExpr_Simple,
        test_Parser_TryExpr_Chained,
        test_Parser_CatchExpression_Simple,
        test_Parser_CatchExpression_WithPayload,
        test_Parser_CatchExpression_MixedAssociativity,
        test_Parser_Orelse_IsLeftAssociative,
        test_Parser_Catch_IsLeftAssociative,
        test_Parser_CatchExpr_Simple,
        test_Parser_CatchExpr_LeftAssociativity,
        test_Parser_CatchExpr_MixedAssociativity,
        test_Parser_OrelseExpr_Simple,
        test_Parser_OrelseExpr_LeftAssociativity,
        test_Parser_OrelseExpr_Precedence,
        // Group 3C
        test_ASTNode_ContainerDeclarations,
        test_Parser_Struct_Error_MissingLBrace,
        test_Parser_Struct_Error_MissingRBrace,
        test_Parser_Struct_Error_MissingColon,
        test_Parser_Struct_Error_MissingType,
        test_Parser_Struct_Error_InvalidField,
        test_Parser_StructDeclaration_Simple,
        test_Parser_StructDeclaration_Empty,
        test_Parser_StructDeclaration_MultipleFields,
        test_Parser_StructDeclaration_WithTrailingComma,
        test_Parser_StructDeclaration_ComplexFieldType,
        test_ParserBug_TopLevelUnion,
        test_ParserBug_TopLevelStruct,
        test_ParserBug_UnionFieldNodeType,
        // Group 3D
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
        // Group 3E
        test_Parser_FnDecl_ValidEmpty,
        test_Parser_FnDecl_Valid_NoArrow,
        test_Parser_FnDecl_Error_MissingReturnType,
        test_Parser_FnDecl_Error_MissingParens,
        test_Parser_NonEmptyFunctionBody,
        test_Parser_VarDecl_InsertsSymbolCorrectly,
        test_Parser_VarDecl_DetectsDuplicateSymbol,
        test_Parser_FnDecl_AndScopeManagement,
        // Group 3F
        test_ASTNode_ForStmt,
        test_ASTNode_SwitchExpr,
        test_Parser_IfStatement_Simple,
        test_Parser_IfStatement_WithElse,
        test_Parser_ParseEmptyBlock,
        test_Parser_ParseBlockWithEmptyStatement,
        test_Parser_ParseBlockWithMultipleEmptyStatements,
        test_Parser_ParseBlockWithNestedEmptyBlock,
        test_Parser_ParseBlockWithMultipleNestedEmptyBlocks,
        test_Parser_ParseBlockWithNestedBlockAndEmptyStatement,
        test_Parser_ErrDeferStatement_Simple,
        test_Parser_ComptimeBlock_Valid,
        test_Parser_NestedBlocks_AndShadowing,
        test_Parser_SymbolDoesNotLeakFromInnerScope,
        // Group 3G
        test_Parser_Error_OnUnexpectedToken,
        test_Parser_Error_OnMissingColon,
        test_Parser_IfStatement_Error_MissingLParen,
        test_Parser_IfStatement_Error_MissingRParen,
        test_Parser_IfStatement_Error_MissingThenBlock,
        test_Parser_IfStatement_Error_MissingElseBlock,
        test_Parser_BinaryExpr_Error_MissingRHS,
        test_Parser_TryExpr_InvalidSyntax,
        test_Parser_CatchExpression_Error_MissingElseExpr,
        test_Parser_CatchExpression_Error_IncompletePayload,
        test_Parser_CatchExpression_Error_MissingPipe,
        test_Parser_ErrDeferStatement_Error_MissingBlock,
        test_Parser_ComptimeBlock_Error_MissingExpression,
        test_Parser_ComptimeBlock_Error_MissingOpeningBrace,
        test_Parser_ComptimeBlock_Error_MissingClosingBrace,
        // Group 3H
        test_Parser_AbortOnAllocationFailure,
        test_Parser_TokenStreamLifetimeIsIndependentOfParserObject,
        test_ParserIntegration_VarDeclWithBinaryExpr,
        test_ParserIntegration_IfWithComplexCondition,
        test_ParserIntegration_WhileWithFunctionCall,
        test_ParserBug_LogicalOperatorSymbol,
        test_Parser_RecursionLimit,
        test_Parser_RecursionLimit_Unary,
        test_Parser_RecursionLimit_Binary,
        test_Parser_CopyIsSafeAndDoesNotDoubleFree,
        test_Parser_Bugfix_HandlesExpressionStatement,
        // Group 4A
        test_TypeChecker_IntegerLiteralInference,
        test_TypeChecker_FloatLiteralInference,
        test_TypeChecker_CharLiteralInference,
        test_TypeChecker_StringLiteralInference,
        test_TypeCheckerStringLiteralType,
        test_TypeCheckerIntegerLiteralType,
        test_TypeChecker_C89IntegerCompatibility,
        test_TypeResolution_ValidPrimitives,
        test_TypeResolution_InvalidOrUnsupported,
        test_TypeResolution_AllPrimitives,
        test_TypeChecker_BoolLiteral,
        test_TypeChecker_IntegerLiteral,
        test_TypeChecker_CharLiteral,
        test_TypeChecker_StringLiteral,
        test_TypeChecker_Identifier,
        // Group 4B
        test_TypeCheckerValidDeclarations,
        test_TypeCheckerInvalidDeclarations,
        test_TypeCheckerUndeclaredVariable,
        test_TypeChecker_VarDecl_Valid_Simple,
        test_TypeChecker_VarDecl_Invalid_Mismatch,
        test_TypeChecker_VarDecl_Invalid_Widening,
        test_TypeChecker_VarDecl_Multiple_Errors,
        // Group 4C
        test_ReturnTypeValidation_Valid,
        test_ReturnTypeValidation_Invalid,
        test_TypeCheckerFnDecl_ValidSimpleParams,
        test_TypeCheckerFnDecl_InvalidParamType,
        test_TypeCheckerVoidTests_ImplicitReturnInVoidFunction,
        test_TypeCheckerVoidTests_ExplicitReturnInVoidFunction,
        test_TypeCheckerVoidTests_ReturnValueInVoidFunction,
        test_TypeCheckerVoidTests_MissingReturnValueInNonVoidFunction,
        test_TypeCheckerVoidTests_ImplicitReturnInNonVoidFunction,
        test_TypeCheckerVoidTests_AllPathsReturnInNonVoidFunction,
        // Group 4D
        test_TypeChecker_AddressOf_RValueLiteral,
        test_TypeChecker_AddressOf_RValueExpression,
        test_TypeChecker_Dereference_ValidPointer,
        test_TypeChecker_Dereference_Invalid_NonPointer,
        test_TypeChecker_Dereference_VoidPointer,
        test_TypeChecker_Dereference_NullLiteral,
        test_TypeChecker_Dereference_ZeroLiteral,
        test_TypeChecker_Dereference_NestedPointer,
        test_TypeChecker_Dereference_ConstPointer,
        test_TypeChecker_AddressOf_Valid_LValues,
        test_TypeCheckerPointerOps_AddressOf_ValidLValue,
        test_TypeCheckerPointerOps_Dereference_ValidPointer,
        test_TypeCheckerPointerOps_Dereference_InvalidNonPointer,
        // Group 4E
        test_TypeChecker_PointerArithmetic_ValidCases_ExplicitTyping,
        test_TypeChecker_PointerArithmetic_InvalidCases_ExplicitTyping,
        test_TypeCheckerVoidTests_PointerAddition,
        test_TypeChecker_PointerIntegerAddition,
        test_TypeChecker_IntegerPointerAddition,
        test_TypeChecker_PointerIntegerSubtraction,
        test_TypeChecker_PointerPointerSubtraction,
        test_TypeChecker_Invalid_PointerPointerAddition,
        test_TypeChecker_Invalid_PointerPointerSubtraction_DifferentTypes,
        test_TypeChecker_Invalid_PointerMultiplication,
        test_TypeCheckerPointerOps_Arithmetic_PointerInteger,
        test_TypeCheckerPointerOps_Arithmetic_PointerPointer,
        test_TypeCheckerPointerOps_Arithmetic_InvalidOperations,
        // Group 4F
        test_TypeCheckerBinaryOps_PointerArithmetic,
        test_TypeCheckerBinaryOps_NumericArithmetic,
        test_TypeCheckerBinaryOps_Comparison,
        test_TypeCheckerBinaryOps_Bitwise,
        test_TypeCheckerBinaryOps_Logical,
        test_TypeChecker_Bool_ComparisonOps,
        test_TypeChecker_Bool_LogicalOps,
        // Group 4G
        test_TypeCheckerControlFlow_IfStatementWithBooleanCondition,
        test_TypeCheckerControlFlow_IfStatementWithIntegerCondition,
        test_TypeCheckerControlFlow_IfStatementWithPointerCondition,
        test_TypeCheckerControlFlow_IfStatementWithFloatCondition,
        test_TypeCheckerControlFlow_IfStatementWithVoidCondition,
        test_TypeCheckerControlFlow_WhileStatementWithBooleanCondition,
        test_TypeCheckerControlFlow_WhileStatementWithIntegerCondition,
        test_TypeCheckerControlFlow_WhileStatementWithPointerCondition,
        test_TypeCheckerControlFlow_WhileStatementWithFloatCondition,
        test_TypeCheckerControlFlow_WhileStatementWithVoidCondition,
        // Group 4H
        test_TypeChecker_C89_StructFieldValidation_Slice,
        test_TypeChecker_C89_UnionFieldValidation_MultiLevelPointer,
        test_TypeChecker_C89_StructFieldValidation_ValidArray,
        test_TypeChecker_C89_UnionFieldValidation_ValidFields,
        test_TypeCheckerEnumTests_SignedIntegerOverflow,
        test_TypeCheckerEnumTests_SignedIntegerUnderflow,
        test_TypeCheckerEnumTests_UnsignedIntegerOverflow,
        test_TypeCheckerEnumTests_NegativeValueInUnsignedEnum,
        test_TypeCheckerEnumTests_AutoIncrementOverflow,
        test_TypeCheckerEnumTests_AutoIncrementSignedOverflow,
        test_TypeCheckerEnumTests_ValidValues,
        // Group 4I
        test_TypeChecker_ArrayAccessInBoundsWithNamedConstant,
        test_TypeChecker_RejectSlice,
        test_TypeChecker_ArrayAccessInBounds,
        test_TypeChecker_ArrayAccessOutOfBoundsPositive,
        test_TypeChecker_ArrayAccessOutOfBoundsNegative,
        test_TypeChecker_ArrayAccessOutOfBoundsExpression,
        test_TypeChecker_ArrayAccessWithVariable,
        test_TypeChecker_IndexingNonArray,
        test_TypeChecker_ArrayAccessWithNamedConstant,
        test_Assignment_IncompatiblePointers_Invalid,
        test_Assignment_ConstPointerToPointer_Invalid,
        test_Assignment_PointerToConstPointer_Valid,
        test_Assignment_VoidPointerToPointer_Invalid,
        test_Assignment_PointerToVoidPointer_Valid,
        test_Assignment_PointerExactMatch_Valid,
        test_Assignment_NullToPointer_Valid,
        test_Assignment_NumericWidening_Fails,
        test_Assignment_ExactNumericMatch,
        test_TypeChecker_RejectNonConstantArraySize,
        test_TypeChecker_AcceptsValidArrayDeclaration,
        test_TypeCheckerVoidTests_DisallowVoidVariableDeclaration,
        test_TypeCompatibility,
        test_TypeToString_Reentrancy,
        test_TypeCheckerC89Compat_RejectFunctionWithTooManyArgs,
        test_TypeChecker_Call_WrongArgumentCount,
        test_TypeChecker_Call_IncompatibleArgumentType,
        test_TypeCheckerC89Compat_FloatWidening_Fails,
        test_C89TypeMapping_Validation,
        test_C89Compat_FunctionTypeValidation,
        test_TypeChecker_Bool_Literals,
        test_TypeChecker_CompoundAssignment_Valid,
        test_TypeChecker_CompoundAssignment_InvalidLValue,
        test_TypeChecker_CompoundAssignment_Bitwise,
        test_TypeChecker_CompoundAssignment_PointerArithmetic,
        test_TypeChecker_CompoundAssignment_InvalidTypes,
        test_DoubleFreeAnalyzer_CompoundAssignment,
        // Memory Stability
        test_MemoryStability_TokenSupplierDanglingPointer,

        // C89 Rejection
        test_C89Rejection_Slice,
        test_C89Rejection_TryExpression,
        test_C89Rejection_CatchExpression,
        test_C89Rejection_OrelseExpression,
        test_TypeChecker_RejectSliceExpression,

        // Address-of Operator
        test_TypeChecker_AddressOf_RValueLiteral,
        test_TypeChecker_AddressOf_RValueExpression,

        // Bug Fix Verification
        test_dynamic_array_destructor_fix,

        // Task 119
        test_Task119_DetectMalloc,
        test_Task119_DetectCalloc,
        test_Task119_DetectRealloc,
        test_Task119_DetectFree,
        test_Task119_DetectAlignedAlloc,
        test_Task119_DetectStrdup,
        test_Task119_DetectMemcpy,
        test_Task119_DetectMemset,
        test_Task119_DetectStrcpy,

        // Symbol Flags
        test_SymbolFlags_GlobalVariable,
        test_SymbolFlags_SymbolBuilder,

        // Utils Bug Fix
        test_safe_append_null_termination,
        test_safe_append_explicit_check,
        test_simple_itoa_null_termination,

        // Lifetime Analysis
        test_Lifetime_DirectReturnLocalAddress,
        test_Lifetime_ReturnLocalPointer,
        test_Lifetime_ReturnParamOK,
        test_Lifetime_ReturnAddrOfParam,
        test_Lifetime_ReturnGlobalOK,
        test_Lifetime_ReassignedPointerOK,

        // Null Pointer Analysis
        test_NullPointerAnalyzer_BasicTracking,
        test_NullPointerAnalyzer_PersistentStateTracking,
        test_NullPointerAnalyzer_AssignmentTracking,
        test_NullPointerAnalyzer_IfNullGuard,
        test_NullPointerAnalyzer_IfElseMerge,
        test_NullPointerAnalyzer_WhileGuard,
        test_NullPointerAnalyzer_WhileConservativeReset,
        test_NullPointerAnalyzer_Shadowing,
        test_NullPointerAnalyzer_NoLeakage,

        // Double Free Analysis
        test_DoubleFree_SimpleDoubleFree,
        test_DoubleFree_BasicTracking,
        test_DoubleFree_UninitializedFree,
        test_DoubleFree_MemoryLeak,
        test_DoubleFree_DeferDoubleFree,
        test_DoubleFree_ReassignmentLeak,
        test_DoubleFree_NullReassignmentLeak,
        test_DoubleFree_ReturnExempt,
        test_DoubleFree_SwitchAnalysis,
        test_DoubleFree_TryAnalysis,
        test_DoubleFree_TryAnalysisComplex,
        test_DoubleFree_CatchAnalysis,
        test_DoubleFree_BinaryOpAnalysis,
        test_DoubleFree_LocationInLeakWarning,
        test_DoubleFree_LocationInReassignmentLeak,
        test_DoubleFree_LocationInDoubleFreeError,
        test_DoubleFree_TransferTracking,
        test_DoubleFree_DeferContextInError,
        test_DoubleFree_ErrdeferContextInError,
        test_DoubleFree_IfElseBranching,
        test_DoubleFree_IfElseBothFree,
        test_DoubleFree_WhileConservative,
        test_DoubleFree_SwitchPathAware,
        test_DoubleFree_SwitchBothFree,
        test_DoubleFree_TryPathAware,
        test_DoubleFree_CatchPathAware,
        test_DoubleFree_OrelsePathAware,
        test_DoubleFree_LoopConservativeVerification,
        // Integration Tests
        test_Integration_FullPipeline,
        test_Integration_CorrectUsage
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
