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
TEST_FUNC(TypeChecker_Dereference_NestedPointer_REJECT);
TEST_FUNC(TypeChecker_Dereference_ConstPointer);
TEST_FUNC(TypeChecker_AddressOf_Valid_LValues);
TEST_FUNC(TypeCheckerPointerOps_AddressOf_ValidLValue);
TEST_FUNC(TypeCheckerPointerOps_Dereference_ValidPointer);
TEST_FUNC(TypeCheckerPointerOps_Dereference_InvalidNonPointer);

// Forward declarations for Group 4E: Pointer Arithmetic
TEST_FUNC(TypeChecker_PointerArithmetic_ValidCases_ExplicitTyping);
TEST_FUNC(TypeChecker_PointerArithmetic_InvalidCases_ExplicitTyping);
TEST_FUNC(TypeCheckerVoidTests_PointerAddition);
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
TEST_FUNC(Assignment_VoidPointerToPointer_Valid);
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

// Forward declarations for Tasks 156-160 (Generics)
TEST_FUNC(C89Rejection_ExplicitGeneric);
TEST_FUNC(C89Rejection_ImplicitGeneric);
TEST_FUNC(GenericCatalogue_TracksExplicit);
TEST_FUNC(GenericCatalogue_TracksImplicit);
TEST_FUNC(C89Rejection_ComptimeValueParam);
TEST_FUNC(GenericCatalogue_Deduplication);
TEST_FUNC(Task155_AllTemplateFormsDetectedAndRejected);
TEST_FUNC(Task155_TypeParamRejected);
TEST_FUNC(Task155_AnytypeParamRejected);

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

// Forward declarations for Platform Abstraction Layer (PAL)
TEST_FUNC(platform_alloc);
TEST_FUNC(platform_realloc);
TEST_FUNC(platform_string);
TEST_FUNC(platform_file);
TEST_FUNC(platform_print);

// Forward declarations for Task 156 (Multi-file & Enhanced Generics)
TEST_FUNC(Task156_ModuleDerivation);
TEST_FUNC(Task156_ASTNodeModule);
TEST_FUNC(Task156_EnhancedGenericDetection);
TEST_FUNC(Task156_InternalErrorCode);

// Forward declarations for Task 157
TEST_FUNC(lex_decrement_operator);
TEST_FUNC(lex_decrement_mixed);
TEST_FUNC(lex_pipe_pipe_operator);
TEST_FUNC(GenericCatalogue_ImplicitInstantiation);
TEST_FUNC(TypeChecker_ImplicitGenericDetection);
TEST_FUNC(TypeChecker_MultipleImplicitInstantiations);
TEST_FUNC(TypeChecker_AnytypeImplicitDetection);
TEST_FUNC(Milestone4_GenericsIntegration_MixedCalls);
TEST_FUNC(Milestone4_GenericsIntegration_ComplexParams);

// Forward declarations for Task 161 (Name Mangling)
TEST_FUNC(simple_mangling);
TEST_FUNC(generic_mangling);
TEST_FUNC(multiple_generic_mangling);
TEST_FUNC(c_keyword_collision);
TEST_FUNC(reserved_name_collision);
TEST_FUNC(length_limit);
TEST_FUNC(determinism);

// Forward declarations for Milestone 4 Features
TEST_FUNC(Milestone4_Lexer_Tokens);
TEST_FUNC(Milestone4_Parser_AST);
TEST_FUNC(OptionalType_Creation);
TEST_FUNC(OptionalType_ToString);
TEST_FUNC(TypeChecker_OptionalType);
TEST_FUNC(NameMangler_Milestone4Types);

// Forward declarations for Tasks 163-164
TEST_FUNC(CallSiteLookupTable_Basic);
TEST_FUNC(CallSiteLookupTable_Unresolved);
TEST_FUNC(TypeChecker_CallSiteRecording_Direct);
TEST_FUNC(TypeChecker_CallSiteRecording_Recursive);
TEST_FUNC(TypeChecker_CallSiteRecording_Generic);

// Forward declarations for Task 165
TEST_FUNC(Task165_ForwardReference);
TEST_FUNC(Task165_BuiltinRejection);
TEST_FUNC(Task165_C89Incompatible);

// Forward declarations for Task 166
TEST_FUNC(IndirectCall_Variable);
TEST_FUNC(IndirectCall_Member);
TEST_FUNC(IndirectCall_Array);
TEST_FUNC(IndirectCall_Returned);
TEST_FUNC(IndirectCall_Complex);
TEST_FUNC(ForwardReference_GlobalVariable);
TEST_FUNC(ForwardReference_MutualFunction);
TEST_FUNC(ForwardReference_StructType);

// Forward declarations for Task 167
TEST_FUNC(Recursive_Factorial);
TEST_FUNC(Recursive_Mutual_Mangled);
TEST_FUNC(Recursive_Forward_Mangled);

// Task 168: Call Syntax Verification
TEST_FUNC(CallSyntax_AtImport);
TEST_FUNC(CallSyntax_AtImport_Rejection);
TEST_FUNC(CallSyntax_ComplexPostfix);
TEST_FUNC(CallSyntax_MethodCall);

// Task 168: Final Validation Tests
TEST_FUNC(Task168_ComplexContexts);
TEST_FUNC(Task168_MutualRecursion);
TEST_FUNC(Task168_IndirectCallRejection);
TEST_FUNC(Task168_GenericCallChain);
TEST_FUNC(Task168_BuiltinCall);

// Task 169: Bootstrap Type System Tests
TEST_FUNC(BootstrapTypes_Allowed_Primitives);
TEST_FUNC(BootstrapTypes_Allowed_Pointers);
TEST_FUNC(BootstrapTypes_Allowed_Arrays);
TEST_FUNC(BootstrapTypes_Allowed_Structs);
TEST_FUNC(BootstrapTypes_Allowed_Enums);
TEST_FUNC(BootstrapTypes_Rejected_MultiLevelPointer);
TEST_FUNC(BootstrapTypes_Rejected_Slice);
TEST_FUNC(BootstrapTypes_Rejected_ErrorUnion);
TEST_FUNC(BootstrapTypes_Rejected_Optional);
TEST_FUNC(BootstrapTypes_Rejected_FunctionPointer);
TEST_FUNC(BootstrapTypes_Rejected_TooManyArgs);
TEST_FUNC(BootstrapTypes_Rejected_MultiLevelPointer_StructField);
TEST_FUNC(BootstrapTypes_Rejected_VoidVariable);

// Task 169: MSVC Compatibility Tests
TEST_FUNC(MsvcCompatibility_Int64Mapping);
TEST_FUNC(MsvcCompatibility_TypeSizes);

// Task 170: Literal Integration Tests
TEST_FUNC(LiteralIntegration_IntegerDecimal);
TEST_FUNC(LiteralIntegration_IntegerHex);
TEST_FUNC(LiteralIntegration_IntegerUnsigned);
TEST_FUNC(LiteralIntegration_IntegerLong);
TEST_FUNC(LiteralIntegration_IntegerUnsignedLong);
TEST_FUNC(LiteralIntegration_FloatSimple);
TEST_FUNC(LiteralIntegration_FloatScientific);
TEST_FUNC(LiteralIntegration_FloatExplicitF64);
TEST_FUNC(LiteralIntegration_CharBasic);
TEST_FUNC(LiteralIntegration_CharEscape);
TEST_FUNC(LiteralIntegration_StringBasic);
TEST_FUNC(LiteralIntegration_StringEscape);
TEST_FUNC(LiteralIntegration_BoolTrue);
TEST_FUNC(LiteralIntegration_BoolFalse);
TEST_FUNC(LiteralIntegration_NullLiteral);
TEST_FUNC(LiteralIntegration_ExpressionStatement);

// Task 171: Variable Declaration Integration Tests
TEST_FUNC(VariableIntegration_BasicI32);
TEST_FUNC(VariableIntegration_BasicConstF64);
TEST_FUNC(VariableIntegration_GlobalVar);
TEST_FUNC(VariableIntegration_LocalVar);
TEST_FUNC(VariableIntegration_InferredInt);
TEST_FUNC(VariableIntegration_InferredFloat);
TEST_FUNC(VariableIntegration_InferredBool);
TEST_FUNC(VariableIntegration_MangleKeyword);
TEST_FUNC(VariableIntegration_MangleReserved);
TEST_FUNC(VariableIntegration_MangleLongName);
TEST_FUNC(VariableIntegration_DuplicateNameError);
TEST_FUNC(VariableIntegration_RejectSlice);
TEST_FUNC(VariableIntegration_PointerToVoid);

// Task 172: Arithmetic Integration Tests
TEST_FUNC(ArithmeticIntegration_IntAdd);
TEST_FUNC(ArithmeticIntegration_IntSub);
TEST_FUNC(ArithmeticIntegration_IntMul);
TEST_FUNC(ArithmeticIntegration_IntDiv);
TEST_FUNC(ArithmeticIntegration_IntMod);
TEST_FUNC(ArithmeticIntegration_FloatAdd);
TEST_FUNC(ArithmeticIntegration_FloatSub);
TEST_FUNC(ArithmeticIntegration_FloatMul);
TEST_FUNC(ArithmeticIntegration_FloatDiv);
TEST_FUNC(ArithmeticIntegration_IntEq);
TEST_FUNC(ArithmeticIntegration_IntNe);
TEST_FUNC(ArithmeticIntegration_IntLt);
TEST_FUNC(ArithmeticIntegration_IntLe);
TEST_FUNC(ArithmeticIntegration_IntGt);
TEST_FUNC(ArithmeticIntegration_IntGe);
TEST_FUNC(ArithmeticIntegration_LogicalAnd);
TEST_FUNC(ArithmeticIntegration_LogicalOr);
TEST_FUNC(ArithmeticIntegration_LogicalNot);
TEST_FUNC(ArithmeticIntegration_UnaryMinus);
TEST_FUNC(ArithmeticIntegration_Parentheses);
TEST_FUNC(ArithmeticIntegration_NestedParentheses);
TEST_FUNC(ArithmeticIntegration_Int8LiteralPromotion);
TEST_FUNC(ArithmeticIntegration_TypeMismatchError);
TEST_FUNC(ArithmeticIntegration_FloatModuloError);
TEST_FUNC(ArithmeticIntegration_BoolArithmeticError);

// Task 173: Function Declaration Integration Tests
TEST_FUNC(FunctionIntegration_NoParams);
TEST_FUNC(FunctionIntegration_FourParams);
TEST_FUNC(FunctionIntegration_PointerTypes);
TEST_FUNC(FunctionIntegration_MangleKeyword);
TEST_FUNC(FunctionIntegration_MangleLongName);
TEST_FUNC(FunctionIntegration_Recursion);
TEST_FUNC(FunctionIntegration_ForwardReference);
TEST_FUNC(FunctionIntegration_RejectFiveParams);
TEST_FUNC(FunctionIntegration_RejectSliceReturn);
TEST_FUNC(FunctionIntegration_RejectMultiLevelPointer);
TEST_FUNC(FunctionIntegration_RejectDuplicateName);

// Task 174: Function Call Integration Tests
TEST_FUNC(FunctionCallIntegration_NoParams);
TEST_FUNC(FunctionCallIntegration_TwoArgs);
TEST_FUNC(FunctionCallIntegration_FourArgs);
TEST_FUNC(FunctionCallIntegration_Nested);
TEST_FUNC(FunctionCallIntegration_MangleKeyword);
TEST_FUNC(FunctionCallIntegration_VoidStatement);
TEST_FUNC(FunctionCallIntegration_CallResolution);
TEST_FUNC(FunctionCallIntegration_RejectFiveArgs);
TEST_FUNC(FunctionCallIntegration_RejectFunctionPointer);
TEST_FUNC(FunctionCallIntegration_TypeMismatch);
TEST_FUNC(FunctionCallIntegration_UndefinedFunction);

// Task 175: If Statement Integration Tests
TEST_FUNC(IfStatementIntegration_BoolCondition);
TEST_FUNC(IfStatementIntegration_IntCondition);
TEST_FUNC(IfStatementIntegration_PointerCondition);
TEST_FUNC(IfStatementIntegration_IfElse);
TEST_FUNC(IfStatementIntegration_ElseIfChain);
TEST_FUNC(IfStatementIntegration_NestedIf);
TEST_FUNC(IfStatementIntegration_LogicalAnd);
TEST_FUNC(IfStatementIntegration_LogicalOr);
TEST_FUNC(IfStatementIntegration_LogicalNot);
TEST_FUNC(IfStatementIntegration_EmptyBlocks);
TEST_FUNC(IfStatementIntegration_ReturnFromBranches);
TEST_FUNC(IfStatementIntegration_RejectFloatCondition);
TEST_FUNC(IfStatementIntegration_RejectBracelessIf);

// Task 176: While Loop Integration Tests
TEST_FUNC(WhileLoopIntegration_BoolCondition);
TEST_FUNC(WhileLoopIntegration_IntCondition);
TEST_FUNC(WhileLoopIntegration_PointerCondition);
TEST_FUNC(WhileLoopIntegration_WithBreak);
TEST_FUNC(WhileLoopIntegration_WithContinue);
TEST_FUNC(WhileLoopIntegration_NestedWhile);
TEST_FUNC(WhileLoopIntegration_Scoping);
TEST_FUNC(WhileLoopIntegration_ComplexCondition);
TEST_FUNC(WhileLoopIntegration_RejectFloatCondition);
TEST_FUNC(WhileLoopIntegration_RejectBracelessWhile);
TEST_FUNC(WhileLoopIntegration_EmptyWhileBlock);

// Task 177: Struct Integration Tests
TEST_FUNC(StructIntegration_BasicNamedStruct);
TEST_FUNC(StructIntegration_MemberAccess);
TEST_FUNC(StructIntegration_NamedInitializerOrder);
TEST_FUNC(StructIntegration_RejectAnonymousStruct);
TEST_FUNC(StructIntegration_RejectStructMethods);
TEST_FUNC(StructIntegration_RejectSliceField);
TEST_FUNC(StructIntegration_RejectMultiLevelPointerField);

// Task 178: Pointer Integration Tests
TEST_FUNC(PointerIntegration_AddressOfDereference);
TEST_FUNC(PointerIntegration_DereferenceExpression);
TEST_FUNC(PointerIntegration_PointerArithmeticAdd);
TEST_FUNC(PointerIntegration_PointerArithmeticSub);
TEST_FUNC(PointerIntegration_NullLiteral);
TEST_FUNC(PointerIntegration_NullComparison);
TEST_FUNC(PointerIntegration_PointerToStruct);
TEST_FUNC(PointerIntegration_VoidPointerAssignment);
TEST_FUNC(PointerIntegration_ConstAdding);
TEST_FUNC(PointerIntegration_ReturnLocalAddressError);
TEST_FUNC(PointerIntegration_DereferenceNullError);
TEST_FUNC(PointerIntegration_PointerPlusPointerError);
TEST_FUNC(PointerIntegration_DereferenceNonPointerError);
TEST_FUNC(PointerIntegration_AddressOfNonLValue);
TEST_FUNC(PointerIntegration_IncompatiblePointerAssignment);

// Task 179: C89 Validation Framework Tests
TEST_FUNC(C89Validator_GCC_KnownGood);
TEST_FUNC(C89Validator_GCC_KnownBad);
TEST_FUNC(C89Validator_MSVC6_LongIdentifier);
TEST_FUNC(C89Validator_MSVC6_CppComment);
TEST_FUNC(C89Validator_MSVC6_LongLong);
TEST_FUNC(C89Validator_MSVC6_KnownGood);

// Task 180: Integration Test Suite Expansion
TEST_FUNC(ArrayIntegration_FixedSizeDecl);
TEST_FUNC(ArrayIntegration_Indexing);
TEST_FUNC(ArrayIntegration_MultiDimensionalIndexing);
TEST_FUNC(EnumIntegration_BasicEnum);
TEST_FUNC(EnumIntegration_MemberAccess);
TEST_FUNC(EnumIntegration_RejectNonIntBacking);
TEST_FUNC(UnionIntegration_BareUnion);
TEST_FUNC(UnionIntegration_RejectTaggedUnion);
TEST_FUNC(SwitchIntegration_Basic);
TEST_FUNC(SwitchIntegration_InferredType);
TEST_FUNC(ForIntegration_Basic);
TEST_FUNC(ForIntegration_Scoping);
TEST_FUNC(DeferIntegration_Basic);
TEST_FUNC(RejectionIntegration_ErrorUnion);
TEST_FUNC(RejectionIntegration_Optional);
TEST_FUNC(RejectionIntegration_TryExpression);

// Task 182 & 183: Implicit *void conversion and usize/isize
TEST_FUNC(Task183_USizeISizeSupported);
TEST_FUNC(Task182_ArenaAllocReturnsVoidPtr);
TEST_FUNC(Task182_ImplicitVoidPtrToTypedPtrAssignment);
TEST_FUNC(Task182_ImplicitVoidPtrToTypedPtrArgument);
TEST_FUNC(Task182_ImplicitVoidPtrToTypedPtrReturn);
TEST_FUNC(Task182_ConstCorrectness_AddConst);
TEST_FUNC(Task182_ConstCorrectness_PreserveConst);
TEST_FUNC(Task182_ConstCorrectness_DiscardConst_REJECT);
TEST_FUNC(Task182_NonC89Target_REJECT);
TEST_FUNC(PointerArithmetic_PtrPlusUSize);
TEST_FUNC(PointerArithmetic_USizePlusPtr);
TEST_FUNC(PointerArithmetic_PtrMinusUSize);
TEST_FUNC(PointerArithmetic_PtrMinusPtr);
TEST_FUNC(PointerArithmetic_PtrPlusISize);
TEST_FUNC(PointerArithmetic_PtrMinusPtr_ConstCompatible);
TEST_FUNC(PointerArithmetic_PtrPlusSigned_Error);
TEST_FUNC(PointerArithmetic_VoidPtr_Error);
TEST_FUNC(PointerArithmetic_MultiLevel_Error);
TEST_FUNC(PointerArithmetic_SizeOfUSize);
TEST_FUNC(PointerArithmetic_AlignOfISize);
TEST_FUNC(PointerArithmetic_PtrCast);
TEST_FUNC(PointerArithmetic_OffsetOf);
TEST_FUNC(PointerArithmetic_PtrPlusPtr_Error);
TEST_FUNC(PointerArithmetic_PtrMulInt_Error);
TEST_FUNC(PointerArithmetic_DiffDifferentTypes_Error);
TEST_FUNC(IntegerWidening_Args_Signed);
TEST_FUNC(IntegerWidening_Args_ISize);
TEST_FUNC(IntegerNarrowing_Args_Error);
TEST_FUNC(IntegerNarrowing_ISize_Error);
TEST_FUNC(IntegerWidening_Args_Unsigned);
TEST_FUNC(IntegerWidening_Args_USize);

// Task 185: Explicit Cast (@ptrCast)
TEST_FUNC(PtrCast_Basic);
TEST_FUNC(PtrCast_ToConst);
TEST_FUNC(PtrCast_FromVoid);
TEST_FUNC(PtrCast_ToVoid);
TEST_FUNC(PtrCast_TargetNotPointer_Error);
TEST_FUNC(PtrCast_SourceNotPointer_Error);
TEST_FUNC(PtrCast_Nested);
TEST_FUNC(IntCast_Constant_Fold);
TEST_FUNC(IntCast_Constant_Overflow_Error);
TEST_FUNC(IntCast_Runtime);
TEST_FUNC(IntCast_Widening);
TEST_FUNC(IntCast_Bool);
TEST_FUNC(FloatCast_Constant_Fold);
TEST_FUNC(FloatCast_Runtime_Widening);
TEST_FUNC(FloatCast_Runtime_Narrowing);
TEST_FUNC(Cast_Invalid_Types_Error);

// Task 186: Compile-time Size & Alignment Introspection
TEST_FUNC(SizeOf_Primitive);
TEST_FUNC(AlignOf_Primitive);
TEST_FUNC(SizeOf_Struct);
TEST_FUNC(SizeOf_Array);
TEST_FUNC(SizeOf_Pointer);
TEST_FUNC(SizeOf_Incomplete_Error);
TEST_FUNC(AlignOf_Struct);

// Task 188: @offsetOf
TEST_FUNC(BuiltinOffsetOf_StructBasic);
TEST_FUNC(BuiltinOffsetOf_StructPadding);
TEST_FUNC(BuiltinOffsetOf_Union);
TEST_FUNC(BuiltinOffsetOf_NonAggregate_Error);
TEST_FUNC(BuiltinOffsetOf_FieldNotFound_Error);
TEST_FUNC(BuiltinOffsetOf_IncompleteType_Error);

// Task 189: C89 Emitter
TEST_FUNC(c89_emitter_basic);
TEST_FUNC(c89_emitter_buffering);
TEST_FUNC(plat_file_raw_io);

// Task 190: C Variable Allocator
TEST_FUNC(CVariableAllocator_Basic);
TEST_FUNC(CVariableAllocator_Keywords);
TEST_FUNC(CVariableAllocator_Truncation);
TEST_FUNC(CVariableAllocator_MangledReuse);
TEST_FUNC(CVariableAllocator_Generate);
TEST_FUNC(CVariableAllocator_Reset);

// Task 191: Integer Literal Codegen
TEST_FUNC(Codegen_Int_i32);
TEST_FUNC(Codegen_Int_u32);
TEST_FUNC(Codegen_Int_i64);
TEST_FUNC(Codegen_Int_u64);
TEST_FUNC(Codegen_Int_usize);
TEST_FUNC(Codegen_Int_u8);
TEST_FUNC(Codegen_Int_HexToDecimal);
TEST_FUNC(Codegen_Int_LargeU64);

// Task 192: Float Literal Codegen
TEST_FUNC(Codegen_Float_f64);
TEST_FUNC(Codegen_Float_f32);
TEST_FUNC(Codegen_Float_WholeNumber);
TEST_FUNC(Codegen_Float_Scientific);
TEST_FUNC(Codegen_Float_HexConversion);

// Task 193: String and Char Literal Codegen
TEST_FUNC(Codegen_StringSimple);
TEST_FUNC(Codegen_StringEscape);
TEST_FUNC(Codegen_StringQuotes);
TEST_FUNC(Codegen_StringOctal);
TEST_FUNC(Codegen_CharSimple);
TEST_FUNC(Codegen_CharEscape);
TEST_FUNC(Codegen_CharSingleQuote);
TEST_FUNC(Codegen_CharDoubleQuote);
TEST_FUNC(Codegen_CharOctal);
TEST_FUNC(Codegen_StringSymbolicEscapes);
TEST_FUNC(Codegen_StringAllC89Escapes);

// Task 194: Global Variable Codegen
TEST_FUNC(Codegen_Global_PubConst);
TEST_FUNC(Codegen_Global_PrivateConst);
TEST_FUNC(Codegen_Global_PubVar);
TEST_FUNC(Codegen_Global_PrivateVar);
TEST_FUNC(Codegen_Global_Array);
TEST_FUNC(Codegen_Global_Array_WithInit);
TEST_FUNC(Codegen_Global_Pointer);
TEST_FUNC(Codegen_Global_ConstPointer);
TEST_FUNC(Codegen_Global_KeywordCollision);
TEST_FUNC(Codegen_Global_LongName);
TEST_FUNC(Codegen_Global_PointerToGlobal);
TEST_FUNC(Codegen_Global_Arithmetic);
TEST_FUNC(Codegen_Global_Enum);
TEST_FUNC(Codegen_Global_Struct);
TEST_FUNC(Codegen_Global_AnonymousContainer_Error);
TEST_FUNC(Codegen_Global_NonConstantInit_Error);

// Task 195: Local Variable Codegen
TEST_FUNC(Codegen_Local_Simple);
TEST_FUNC(Codegen_Local_AfterStatement);
TEST_FUNC(Codegen_Local_Const);
TEST_FUNC(Codegen_Local_Undefined);
TEST_FUNC(Codegen_Local_Shadowing);
TEST_FUNC(Codegen_Local_IfStatement);
TEST_FUNC(Codegen_Local_WhileLoop);
TEST_FUNC(Codegen_Local_Return);
TEST_FUNC(Codegen_Local_MultipleBlocks);

// Task 196: Function Codegen
TEST_FUNC(Codegen_Fn_Simple);
TEST_FUNC(Codegen_Fn_Public);
TEST_FUNC(Codegen_Fn_Params);
TEST_FUNC(Codegen_Fn_Pointers);
TEST_FUNC(Codegen_Fn_Call);
TEST_FUNC(Codegen_Fn_KeywordParam);
TEST_FUNC(Codegen_Fn_MangledCall);
TEST_FUNC(Codegen_Fn_StructReturn);
TEST_FUNC(Codegen_Fn_Extern);
TEST_FUNC(Codegen_Fn_Export);
TEST_FUNC(Codegen_Fn_LongName);
TEST_FUNC(Codegen_Fn_RejectArrayReturn);

// Task 199: Member Access Codegen
TEST_FUNC(Codegen_MemberAccess_Simple);
TEST_FUNC(Codegen_MemberAccess_Pointer);
TEST_FUNC(Codegen_MemberAccess_ExplicitDeref);
TEST_FUNC(Codegen_MemberAccess_AddressOf);
TEST_FUNC(Codegen_MemberAccess_Union);
TEST_FUNC(Codegen_MemberAccess_Nested);
TEST_FUNC(Codegen_MemberAccess_Array);
TEST_FUNC(Codegen_MemberAccess_Call);
TEST_FUNC(Codegen_MemberAccess_Cast);
TEST_FUNC(Codegen_MemberAccess_NestedPointer);
TEST_FUNC(Codegen_MemberAccess_ComplexPostfix);

// Task 200: Array Indexing Codegen
TEST_FUNC(Codegen_Array_Simple);
TEST_FUNC(Codegen_Array_MultiDim);
TEST_FUNC(Codegen_Array_Pointer);
TEST_FUNC(Codegen_Array_Const);
TEST_FUNC(Codegen_Array_ExpressionIndex);
TEST_FUNC(Codegen_Array_NestedMember);
TEST_FUNC(Codegen_Array_OOB_Error);
TEST_FUNC(Codegen_Array_NonIntegerIndex_Error);
TEST_FUNC(Codegen_Array_NonArrayBase_Error);

#endif // TEST_DECLARATIONS_HPP
