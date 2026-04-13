# Z98 Test Suite Specification

This document provides an extensive specification of the Z98 compiler test suite. It documents what is being tested and how, using pseudocode to describe the test logic.

---

## 1. Core Architectural Goals

The Z98 test suite is designed to verify the compiler's adherence to the <16MB memory constraint and C89 compatibility through multiple specialized sub-systems.

## 2. Technical Inventory

| Batch | Category | Focus Areas |
|-------|----------|-------------|
| [1](../../tdocs/tests/batch_details_1.md) | Infrastructure | test_DynamicArray_ShouldUseCopyConstructionOnReallocation, test_ArenaAllocator_AllocShouldReturn8ByteAligned, test_arena_alloc_out_of_memory... |
| [2](../../tdocs/tests/batch_details_2.md) | Parser | test_ASTNode_IntegerLiteral, test_ASTNode_FloatLiteral, test_ASTNode_CharLiteral... |
| [3](../../tdocs/tests/batch_details_3.md) | Type System | test_TypeChecker_IntegerLiteralInference, test_TypeChecker_FloatLiteralInference, test_TypeChecker_CharLiteralInference... |
| [4](../../tdocs/tests/batch_details_4.md) | Type System | test_MemoryStability_TokenSupplierDanglingPointer, test_C89Rejection_Slice, test_C89Rejection_TryExpression... |
| [5](../../tdocs/tests/batch_details_5.md) | Static Analysis | test_DoubleFree_SimpleDoubleFree, test_DoubleFree_BasicTracking, test_DoubleFree_UninitializedFree... |
| [6](../../tdocs/tests/batch_details_6.md) | Type System | test_TypeChecker_StructDeclaration_Valid, test_TypeChecker_StructDeclaration_DuplicateField, test_TypeChecker_StructInitialization_Valid... |
| [7](../../tdocs/tests/batch_details_7.md) | Type System | test_Task142_ErrorFunctionDetection, test_Task142_ErrorFunctionRejection, test_Task143_TryExpressionDetection_Contexts... |
| [8](../../tdocs/tests/batch_details_8.md) | Type System | test_Task154_RejectAnytypeParam, test_Task154_RejectTypeParam, test_Task154_CatalogueComptimeDefinition... |
| [9](../../tdocs/tests/batch_details_9.md) | Type System | test_platform_alloc, test_platform_realloc, test_platform_string... |
| [10](../../tdocs/tests/batch_details_10.md) | Compiler | test_simple_mangling, test_generic_mangling, test_multiple_generic_mangling... |
| [11](../../tdocs/tests/batch_details_11.md) | Lexer | test_Milestone4_Lexer_Tokens, test_Milestone4_Parser_AST, test_OptionalType_Creation... |
| [12](../../tdocs/tests/batch_details_12.md) | Type System | test_BootstrapTypes_Allowed_Primitives, test_BootstrapTypes_Allowed_Pointers, test_BootstrapTypes_Allowed_Arrays... |
| [13](../../tdocs/tests/batch_details_13.md) | Compiler | test_IfStatementIntegration_BoolCondition, test_IfStatementIntegration_IntCondition, test_IfStatementIntegration_PointerCondition... |
| [14](../../tdocs/tests/batch_details_14.md) | Compiler | test_WhileLoopIntegration_BoolCondition, test_WhileLoopIntegration_IntCondition, test_WhileLoopIntegration_PointerCondition... |
| [15](../../tdocs/tests/batch_details_15.md) | Compiler | test_StructIntegration_BasicNamedStruct, test_StructIntegration_MemberAccess, test_StructIntegration_NamedInitializerOrder... |
| [16](../../tdocs/tests/batch_details_16.md) | Compiler | test_PointerIntegration_AddressOfDereference, test_PointerIntegration_DereferenceExpression, test_PointerIntegration_PointerArithmeticAdd... |
| [17](../../tdocs/tests/batch_details_17.md) | Validation | test_C89Validator_GCC_KnownGood, test_C89Validator_GCC_KnownBad, test_C89Validator_MSVC6_LongIdentifier... |
| [18](../../tdocs/tests/batch_details_18.md) | Type System | test_ArrayIntegration_FixedSizeDecl, test_ArrayIntegration_Indexing, test_ArrayIntegration_MultiDimensionalIndexing... |
| [19](../../tdocs/tests/batch_details_19.md) | Type System | test_Task183_USizeISizeSupported, test_Task182_ArenaAllocReturnsVoidPtr, test_Task182_ImplicitVoidPtrToTypedPtrAssignment... |
| [20](../../tdocs/tests/batch_details_20.md) | Type System | test_PtrCast_Basic, test_PtrCast_ToConst, test_PtrCast_FromVoid... |
| [21](../../tdocs/tests/batch_details_21.md) | Type System | test_SizeOf_Primitive, test_SizeOf_Struct, test_SizeOf_Array... |
| [22](../../tdocs/tests/batch_details_22.md) | Codegen | test_c89_emitter_basic, test_c89_emitter_buffering, test_plat_file_raw_io... |
| [23](../../tdocs/tests/batch_details_23.md) | Compiler | test_CVariableAllocator_Basic, test_CVariableAllocator_Keywords, test_CVariableAllocator_Truncation... |
| [24](../../tdocs/tests/batch_details_24.md) | Codegen | test_Codegen_Int_i32, test_Codegen_Int_u32, test_Codegen_Int_i64... |
| [25](../../tdocs/tests/batch_details_25.md) | Codegen | test_Codegen_Float_f64, test_Codegen_Float_f32, test_Codegen_Float_WholeNumber... |
| [26](../../tdocs/tests/batch_details_26.md) | Codegen | test_Codegen_StringSimple, test_Codegen_StringEscape, test_Codegen_StringQuotes... |
| [27](../../tdocs/tests/batch_details_27.md) | Codegen | test_Codegen_Local_Simple, test_Codegen_Local_AfterStatement, test_Codegen_Local_Const... |
| [28](../../tdocs/tests/batch_details_28.md) | Compiler | test_Task168_MutualRecursion, test_Task168_IndirectCallRejection, test_Task168_GenericCallChain... |
| [29](../../tdocs/tests/batch_details_29.md) | Codegen | test_Codegen_Binary_Arithmetic, test_Codegen_Binary_Comparison, test_Codegen_Binary_Bitwise... |
| [30](../../tdocs/tests/batch_details_30.md) | Codegen | test_Codegen_MemberAccess_Simple, test_Codegen_MemberAccess_Pointer, test_Codegen_MemberAccess_ExplicitDeref... |
| [31](../../tdocs/tests/batch_details_31.md) | Codegen | test_Codegen_Array_Simple, test_Codegen_Array_MultiDim, test_Codegen_Array_Pointer... |
| [32](../../tdocs/tests/batch_details_32.md) | End-to-End | test_EndToEnd_HelloWorld, test_EndToEnd_PrimeNumbers... |
| [33](../../tdocs/tests/batch_details_33.md) | Imports | test_Import_Simple, test_Import_Circular, test_Import_Missing... |
| [34](../../tdocs/tests/batch_details_34.md) | Imports | test_MultiModule_BasicCall, test_MultiModule_StructUsage, test_MultiModule_PrivateVisibility... |
| [35](../../tdocs/tests/batch_details_35.md) | Imports | test_ImportResolution_Basic, test_ImportResolution_IncludePath, test_ImportResolution_DefaultLib... |
| [36](../../tdocs/tests/batch_details_36.md) | Compiler | test_Pointer_Pointer_Decl, test_Pointer_Pointer_Dereference, test_Pointer_Pointer_Triple... |
| [37](../../tdocs/tests/batch_details_37.md) | Type System | test_ManyItemPointer_Parsing, test_ManyItemPointer_Indexing, test_SingleItemPointer_Indexing_Rejected... |
| [38](../../tdocs/tests/batch_details_38.md) | Type System | test_TypeSystem_FunctionPointerType, test_TypeSystem_SignaturesMatch, test_TypeSystem_AreTypesEqual_FnPtr... |
| [39](../../tdocs/tests/batch_details_39.md) | Compiler | test_DeferIntegration_Basic, test_DeferIntegration_LIFO, test_DeferIntegration_Return... |
| [40](../../tdocs/tests/batch_details_40.md) | Slices | test_SliceIntegration_Declaration, test_SliceIntegration_ParametersAndReturn, test_SliceIntegration_IndexingAndLength... |
| [41](../../tdocs/tests/batch_details_41.md) | Compiler | test_ForIntegration_Array, test_ForIntegration_Slice, test_ForIntegration_Range... |
| [42](../../tdocs/tests/batch_details_42.md) | Compiler | test_ForIntegration_Basic, test_ForIntegration_InvalidIterable, test_ForIntegration_ImmutableCapture... |
| [43](../../tdocs/tests/batch_details_43.md) | Type System | test_SwitchNoreturn_BasicDivergence, test_SwitchNoreturn_AllDivergent, test_SwitchNoreturn_BreakInProng... |
| [44](../../tdocs/tests/batch_details_44.md) | Compiler | test_Task225_2_BracelessIfExpr, test_Task225_2_PrintLowering, test_Task225_2_SwitchIfExpr... |
| [45](../../tdocs/tests/batch_details_45.md) | Compiler | test_ErrorHandling_ErrorSetDefinition, test_ErrorHandling_ErrorLiteral, test_ErrorHandling_SuccessWrapping... |
| [46](../../tdocs/tests/batch_details_46.md) | Parser | test_Parser_Catch_WithBlock, test_Parser_Try_Nested, test_Parser_Catch_Precedence_Arithmetic... |
| [47](../../tdocs/tests/batch_details_47.md) | Optionals | test_Task228_OptionalBasics, test_Task228_OptionalOrelse, test_Task228_OptionalIfCapture... |
| [48](../../tdocs/tests/batch_details_48.md) | Type System | test_RecursiveTypes_SelfRecursiveStruct, test_RecursiveTypes_MutualRecursiveStructs, test_RecursiveTypes_RecursiveSlice... |
| [49](../../tdocs/tests/batch_details_49.md) | Compiler | test_MultiError_Reporting... |
| [50](../../tdocs/tests/batch_details_50.md) | Compiler | test_RecursiveSlice_MultiModule, test_RecursiveSlice_SelfReference, test_RecursiveSlice_MutuallyRecursive... |
| [51](../../tdocs/tests/batch_details_51.md) | Compiler | test_UnionCapture_ForwardDeclaredStruct, test_UnionCapture_NestedUnion, test_UnionCapture_PointerToIncomplete... |
| [52](../../tdocs/tests/batch_details_52.md) | Compiler | test_Task9_8_StringLiteralCoercion, test_Task9_8_ImplicitReturnErrorVoid, test_Task9_8_WhileContinueExpr... |
| [53](../../tdocs/tests/batch_details_53.md) | Type System | test_MetadataPreparation_TransitiveHeaders, test_MetadataPreparation_SpecialTypes, test_MetadataPreparation_RecursivePlaceholder... |
| [54](../../tdocs/tests/batch_details_54.md) | Compiler | test_ASTCloning_Basic, test_ASTCloning_FunctionCall, test_ASTCloning_Switch... |
| [55](../../tdocs/tests/batch_details_55.md) | AST Lifter | test_ASTLifter_BasicIf, test_ASTLifter_Nested, test_ASTLifter_ComplexAssignment... |
| [56](../../tdocs/tests/batch_details_56.md) | Compiler | test_UnionSliceLifting_Basic, test_UnionSliceLifting_Coercion, test_UnionSliceLifting_ManualConstruction... |
| [57](../../tdocs/tests/batch_details_57.md) | Codegen | test_Codegen_AnonymousUnion_Basic, test_Codegen_AnonymousUnion_Nested, test_Codegen_AnonymousStruct_Nested... |
| [58](../../tdocs/tests/batch_details_58.md) | Compiler | test_BracelessControlFlow_If, test_BracelessControlFlow_ElseIf, test_BracelessControlFlow_While... |
| [60](../../tdocs/tests/batch_details_60.md) | Parser | test_clone_basic, test_clone_binary_op, test_clone_range... |
| [61](../../tdocs/tests/batch_details_61.md) | Compiler | test_BracelessControlFlow_If, test_BracelessControlFlow_ElseIf, test_BracelessControlFlow_While... |
| [62](../../tdocs/tests/batch_details_62.md) | Compiler | test_IssueSegfaultReturn... |
| [63](../../tdocs/tests/batch_details_63.md) | Compiler | test_Union_NakedTagsImplicitEnum, test_Union_NakedTagsExplicitEnum, test_Union_NakedTagsRejectionUntagged... |
| [65](../../tdocs/tests/batch_details_65.md) | Tagged Unions | test_TaggedUnionEmission_Named, test_TaggedUnionEmission_Named, test_TaggedUnionEmission_AnonymousField... |
| [66](../../tdocs/tests/batch_details_66.md) | Type System | test_SliceDefinition_PrivateFunction, test_SliceDefinition_RecursiveType, test_SliceDefinition_NestedType... |
| [67](../../tdocs/tests/batch_details_67.md) | Imports | test_UnionTagAccess_Basic, test_UnionTagAccess_AliasChain, test_UnionTagAccess_Alias... |
| [68](../../tdocs/tests/batch_details_68.md) | Compiler | test_StringLiteral_To_ManyPtr, test_StringLiteral_To_Slice, test_StringLiteral_BackwardCompat... |
| [69](../../tdocs/tests/batch_details_69.md) | Codegen | test_Phase1_TaggedUnion_Codegen, test_Phase1_TaggedUnion_ForwardDecl... |
| [70](../../tdocs/tests/batch_details_70.md) | Compiler | test_Unreachable_Statement, test_Unreachable_DeadCode, test_Unreachable_Initializer... |
| [71](../../tdocs/tests/batch_details_71.md) | Compiler | test_Phase3_ErrorUnionRecursion... |
| [72](../../tdocs/tests/batch_details_72.md) | Compiler | test_SwitchProng_ReturnNoSemicolon, test_SwitchProng_BlockMandatoryComma, test_SwitchProng_ExprRequiredCommaFail... |
| [73](../../tdocs/tests/batch_details_73.md) | Recursion | test_Phase7_ValidMutualRecursionPointers, test_Phase7_InvalidValueCycle, test_Phase7_DefinitionOrderValueDependency... |
| [74](../../tdocs/tests/batch_details_74.md) | Compiler | test_AnonInit_TaggedUnion_NestedStruct, test_AnonInit_DeeplyNested, test_AnonInit_Alias... |
| [75](../../tdocs/tests/batch_details_75.md) | Compiler | test_DoubleFree_StructFieldTracking, test_DoubleFree_StructFieldLeak, test_DoubleFree_ArrayCollapseTracking... |
| [80](../../tdocs/tests/batch_details_80.md) | Aggregates | test_TaggedUnion_ArrayDecomposition, test_TaggedUnion_NestedIfExpr, test_TaggedUnion_NestedSwitchExpr... |
| [7_debug](../../tdocs/tests/batch_details_7_debug.md) | Type System | test_Task142_ErrorFunctionDetection, test_Task142_ErrorFunctionRejection, test_Task143_TryExpressionDetection_Contexts... |
| [9a](../../tdocs/tests/batch_details_9a.md) | Compiler | test_Phase9a_ModuleQualifiedTaggedUnion, test_Phase9a_LocalAliasTaggedUnion, test_Phase9a_RecursiveAliasEnum... |
| [9b](../../tdocs/tests/batch_details_9b.md) | Compiler | test_TaggedUnionInit_ReturnAnonymous, test_TaggedUnionInit_Assignment, test_TaggedUnionInit_NakedTag... |
| [9c](../../tdocs/tests/batch_details_9c.md) | Type System | test_ExpectedType_SwitchReturn, test_ExpectedType_Assignment, test_ExpectedType_VarDecl... |
| [_bugs](../../tdocs/tests/batch_details__bugs.md) | Codegen | test_SwitchLifter_NestedControlFlow, test_Codegen_StringSplit, test_Codegen_ForPtrToArray... |

---

## 3. High-Level Logic Specifications

Detailed logic for each batch can be found in the individual documents linked in the table above.
