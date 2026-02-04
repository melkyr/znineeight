#ifndef TEST_DECLARATIONS_HPP
#define TEST_DECLARATIONS_HPP

#include "../src/include/test_framework.hpp"
#include "test_utils.hpp"

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
TEST_FUNC(TypeCheckerEnum_MemberAccess);
TEST_FUNC(TypeCheckerEnum_InvalidMemberAccess);
TEST_FUNC(TypeCheckerEnum_ImplicitConversion);
TEST_FUNC(TypeCheckerEnum_Switch);
TEST_FUNC(TypeCheckerEnum_DuplicateMember);
TEST_FUNC(TypeCheckerEnum_AutoIncrement);

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
TEST_FUNC(C89Rejection_Slice);
TEST_FUNC(C89Rejection_TryExpression);
TEST_FUNC(C89Rejection_CatchExpression);
TEST_FUNC(C89Rejection_OrelseExpression);
TEST_FUNC(C89Rejection_NestedTryInMemberAccess);
TEST_FUNC(C89Rejection_NestedTryInStructInitializer);
TEST_FUNC(C89Rejection_NestedTryInArrayAccess);
TEST_FUNC(TypeChecker_RejectSliceExpression);

// Bug Fix Verification Tests
TEST_FUNC(dynamic_array_destructor_fix);

// Forward declarations for Task 135 (Error Union & Optional Type Rejection)
TEST_FUNC(C89Rejection_ErrorUnionType_FnReturn);
TEST_FUNC(C89Rejection_OptionalType_VarDecl);
TEST_FUNC(C89Rejection_ErrorUnionType_Param);
TEST_FUNC(C89Rejection_ErrorUnionType_StructField);
TEST_FUNC(C89Rejection_NestedErrorUnionType);

// Forward declarations for Symbol Flags
TEST_FUNC(SymbolFlags_GlobalVariable);
TEST_FUNC(SymbolFlags_SymbolBuilder);

// Forward declarations for Task 119
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
TEST_FUNC(Lifetime_DirectReturnLocalAddress);
TEST_FUNC(Lifetime_ReturnLocalPointer);
TEST_FUNC(Lifetime_ReturnParamOK);
TEST_FUNC(Lifetime_ReturnAddrOfParam);
TEST_FUNC(Lifetime_ReturnGlobalOK);
TEST_FUNC(Lifetime_ReassignedPointerOK);

// Forward declarations for Null Pointer Analysis
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
TEST_FUNC(Integration_FullPipeline);
TEST_FUNC(Integration_CorrectUsage);

// Forward declarations for Double Free Analysis
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
TEST_FUNC(DoubleFree_SwitchPathAware);
TEST_FUNC(DoubleFree_SwitchBothFree);
TEST_FUNC(DoubleFree_TryPathAware);
TEST_FUNC(DoubleFree_CatchPathAware);
TEST_FUNC(DoubleFree_OrelsePathAware);
TEST_FUNC(DoubleFree_LoopConservativeVerification);
TEST_FUNC(DoubleFree_NestedDeferScopes);
TEST_FUNC(DoubleFree_PointerAliasing);
TEST_FUNC(DoubleFree_DeferInLoop);
TEST_FUNC(DoubleFree_ConditionalAllocUnconditionalFree);

// Forward declarations for Group 4J: Struct Type Checking (Task 133)
TEST_FUNC(TypeChecker_StructDeclaration_Valid);
TEST_FUNC(TypeChecker_StructDeclaration_DuplicateField);
TEST_FUNC(TypeChecker_StructInitialization_Valid);
TEST_FUNC(TypeChecker_MemberAccess_Valid);
TEST_FUNC(TypeChecker_MemberAccess_InvalidField);
TEST_FUNC(TypeChecker_StructInitialization_MissingField);
TEST_FUNC(TypeChecker_StructInitialization_ExtraField);
TEST_FUNC(TypeChecker_StructInitialization_TypeMismatch);
TEST_FUNC(TypeChecker_StructLayout_Verification);
TEST_FUNC(TypeChecker_UnionDeclaration_DuplicateField);

// Forward declarations for Task 136
TEST_FUNC(Task136_ErrorSet_Catalogue);
TEST_FUNC(Task136_ErrorSet_Rejection);
TEST_FUNC(Task136_ErrorSetMerge_Rejection);
TEST_FUNC(Task136_Import_Rejection);

// Forward declarations for Tasks 137-141 (Generics)
TEST_FUNC(C89Rejection_ExplicitGeneric);
TEST_FUNC(C89Rejection_ImplicitGeneric);
TEST_FUNC(GenericCatalogue_TracksExplicit);
TEST_FUNC(GenericCatalogue_TracksImplicit);
TEST_FUNC(C89Rejection_ComptimeValueParam);
TEST_FUNC(GenericCatalogue_Deduplication);

// Forward declarations for Task 142
TEST_FUNC(Task142_ErrorFunctionDetection);
TEST_FUNC(Task142_ErrorFunctionRejection);

// Forward declarations for Task 143
TEST_FUNC(Task143_TryExpressionDetection_Contexts);
TEST_FUNC(Task143_TryExpressionDetection_Nested);
TEST_FUNC(Task143_TryExpressionDetection_MultipleInStatement);

// Forward declarations for Task 144
TEST_FUNC(CatchExpressionCatalogue_Basic);
TEST_FUNC(CatchExpressionCatalogue_Chaining);
TEST_FUNC(OrelseExpressionCatalogue_Basic);
TEST_FUNC(Task144_CatchExpressionDetection_Basic);
TEST_FUNC(Task144_CatchExpressionDetection_Chained);
TEST_FUNC(Task144_OrelseExpressionDetection);

// Forward declarations for TypeChecker Bug Fixes
TEST_FUNC(TypeChecker_VarDecl_Inferred_Crash);
TEST_FUNC(TypeChecker_VarDecl_Inferred_Loop);
TEST_FUNC(TypeChecker_VarDecl_Inferred_Multiple);

// Forward declarations for Task 146 (Extraction Analysis)
TEST_FUNC(ExtractionAnalysis_StackStrategy);
TEST_FUNC(ExtractionAnalysis_ArenaStrategy_LargePayload);
TEST_FUNC(ExtractionAnalysis_ArenaStrategy_DeepNesting);
TEST_FUNC(ExtractionAnalysis_OutParamStrategy);
TEST_FUNC(ExtractionAnalysis_ArenaStrategy_Alignment);
TEST_FUNC(ExtractionAnalysis_Linking);

// Forward declarations for Task 147
TEST_FUNC(Task147_ErrDeferRejection);
TEST_FUNC(Task147_AnyErrorRejection);

// Forward declarations for Task 148
TEST_FUNC(Task148_PatternGeneration_StructReturn);
TEST_FUNC(Task148_PatternGeneration_OutParameter);
TEST_FUNC(Task148_PatternGeneration_Arena);

// Forward declarations for Task 149
TEST_FUNC(Task149_ErrorHandlingFeaturesCatalogued);

// Forward declarations for Task 150
TEST_FUNC(Task150_ErrorTypeEliminatedFromFinalTypeSystem);
TEST_FUNC(C89Rejection_GenericFnDecl_ShouldBeRejected);
TEST_FUNC(C89Rejection_DeferAndErrDefer);
TEST_FUNC(C89Rejection_ErrorTypeInParam_ShouldBeRejected);
TEST_FUNC(Task150_MoreComprehensiveElimination);
TEST_FUNC(C89Rejection_ArraySliceExpression);

// Forward declarations for Task 151
TEST_FUNC(Task151_ErrorTypeRejection);
TEST_FUNC(Task151_OptionalTypeRejection);

// Forward declarations for Task 152 (Name Collision Detection)
TEST_FUNC(FunctionNameCollisionSameScope);
TEST_FUNC(FunctionVariableCollisionSameScope);
TEST_FUNC(ShadowingAllowed);

// Forward declarations for Task 153 (Signature Analysis)
TEST_FUNC(SignatureAnalysisNonC89Types);
TEST_FUNC(SignatureAnalysisTooManyParams);
TEST_FUNC(SignatureAnalysisMultiLevelPointers);
TEST_FUNC(SignatureAnalysisTypeAliasResolution);
TEST_FUNC(SignatureAnalysisArrayParameterWarning);
TEST_FUNC(SignatureAnalysisReturnTypeRejection);

// Forward declarations for Task 154 (Generic Function Detection)
TEST_FUNC(Task154_RejectAnytypeParam);
TEST_FUNC(Task154_RejectTypeParam);
TEST_FUNC(Task154_CatalogueComptimeDefinition);
TEST_FUNC(Task154_CatalogueAnytypeDefinition);
TEST_FUNC(Task154_CatalogueTypeParamDefinition);

#endif // TEST_DECLARATIONS_HPP
