# Technical Debt: Exhaustive TypeChecker Maintainability Review

This document tracks maintainability issues across all methods in `src/bootstrap/type_checker.cpp`. The metrics highlight areas with excessive complexity that hinder future development and debugging.

## Executive Summary

- **Total Methods Analyzed**: 136
- **Critical Outliers (Lines > 400)**: `visitMemberAccess`, `visitVarDecl`, `coerceNode`, `visitFunctionCall`
- **Deep Nesting Outliers (Nesting > 8)**: `visitMemberAccess`, `visitFnBody`, `coerceNode`, `IsTypeAssignableTo`, `areTypesCompatible`, `visitBlockStmt`

## Comprehensive Review Table

| Method | Category | Lines | Nesting | Difficulty (1-10) | Impact (1-10) | Complexity Reduction (1-10) | Primary Issue/Smell |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| `IsTypeAssignableTo` | Type System | 283 | 9 | 9 | 9 | 9 | Recursive type compatibility logic with complex rules for literals, pointers, and aggregates. |
| `all_paths_return` | Other | 66 | 4 | 3 | 3 | 6 | Modular/Clean |
| `areSamePointerTypeIgnoringConst` | Type System | 21 | 1 | 0 | 2 | 1 | Modular/Clean |
| `areTypesCompatible` | Type System | 279 | 9 | 9 | 8 | 9 | Symmetry-sensitive compatibility checking with deep nesting for function pointers and error unions. |
| `areTypesEqual` | Type System | 176 | 6 | 6 | 6 | 8 | Modular/Clean |
| `canLiteralFitInType` | Type System | 30 | 3 | 1 | 2 | 5 | Modular/Clean |
| `catalogGenericInstantiation` | Other | 111 | 5 | 4 | 4 | 5 | Modular/Clean |
| `check` | Type System | 59 | 6 | 4 | 3 | 6 | Modular/Clean |
| `checkArithmeticWithLiteralPromotion` | Type System | 23 | 7 | 3 | 2 | 7 | Modular/Clean |
| `checkBinaryOpCompatibility` | Type System | 17 | 2 | 1 | 2 | 2 | Modular/Clean |
| `checkBinaryOperation` | Type System | 320 | 6 | 9 | 10 | 8 | Central dispatcher for all binary operators; handles arithmetic, logical, and pointer ops. |
| `checkComparisonWithLiteralPromotion` | Type System | 12 | 3 | 1 | 2 | 1 | Modular/Clean |
| `checkDuplicateLabel` | Type System | 13 | 3 | 1 | 2 | 1 | Modular/Clean |
| `checkIntegerLiteralFit` | Type System | 30 | 3 | 1 | 2 | 5 | Modular/Clean |
| `checkPointerArithmetic` | Type System | 88 | 3 | 2 | 4 | 3 | Modular/Clean |
| `checkStructInitializerFields` | Type System | 130 | 10 | 7 | 5 | 10 | Excessive Nesting |
| `coerceNode` | Coercion | 480 | 10 | 10 | 10 | 10 | Monolithic coercion dispatcher. Combines scalar, array, slice, and error union coercion logic in one place. |
| `coerceStringLiteralToSlice` | Coercion | 28 | 1 | 0 | 2 | 1 | Modular/Clean |
| `createArrayAccess` | Other | 12 | 1 | 1 | 2 | 1 | Modular/Clean |
| `createBinaryOp` | Other | 13 | 1 | 1 | 2 | 1 | Modular/Clean |
| `createErrorUnionDataType` | Type System | 44 | 2 | 1 | 3 | 2 | Modular/Clean |
| `createIntegerLiteral` | Other | 33 | 1 | 0 | 2 | 1 | Modular/Clean |
| `createMemberAccess` | Other | 12 | 1 | 1 | 2 | 1 | Modular/Clean |
| `createUnaryOp` | Other | 11 | 1 | 1 | 2 | 1 | Modular/Clean |
| `detectIndirectType` | Type System | 34 | 4 | 2 | 2 | 4 | Modular/Clean |
| `evaluateConstantExpression` | Other | 84 | 7 | 4 | 4 | 10 | Modular/Clean |
| `exprToString` | Other | 47 | 3 | 1 | 3 | 5 | Modular/Clean |
| `fatalError` | Other | 24 | 1 | 0 | 2 | 1 | Modular/Clean |
| `fatalError` | Other | 5 | 1 | 1 | 2 | 1 | Modular/Clean |
| `finalizePlaceholder` | Resolution | 68 | 4 | 3 | 3 | 4 | Modular/Clean |
| `findEnumMemberValue` | Other | 11 | 3 | 1 | 2 | 1 | Modular/Clean |
| `findErrorTagValue` | Other | 5 | 1 | 1 | 2 | 1 | Modular/Clean |
| `findStructField` | Other | 17 | 3 | 1 | 2 | 3 | Modular/Clean |
| `forceResolveModule` | Other | 52 | 6 | 4 | 3 | 6 | Modular/Clean |
| `getOrCreateErrorUnionDataType` | Type System | 8 | 2 | 1 | 2 | 1 | Modular/Clean |
| `handleModuleMemberFound` | Other | 111 | 7 | 5 | 4 | 7 | Modular/Clean |
| `injectPtrAccessIfNeeded` | Other | 44 | 3 | 1 | 3 | 3 | Modular/Clean |
| `isAmbiguousTag` | Type System | 8 | 1 | 1 | 2 | 1 | Modular/Clean |
| `isCompletePointerType` | Type System | 17 | 2 | 1 | 2 | 2 | Modular/Clean |
| `isFloatType` | Type System | 5 | 1 | 1 | 2 | 1 | Modular/Clean |
| `isIntegerType` | Type System | 12 | 2 | 1 | 2 | 1 | Modular/Clean |
| `isLValueConst` | Type System | 91 | 6 | 4 | 4 | 8 | Modular/Clean |
| `isLocalContext` | Type System | 7 | 1 | 1 | 2 | 1 | Modular/Clean |
| `isMainWithArgs` | Type System | 27 | 1 | 0 | 2 | 1 | Modular/Clean |
| `isNumericType` | Type System | 11 | 2 | 1 | 2 | 1 | Modular/Clean |
| `isPointerIndirectionTo` | Type System | 37 | 4 | 2 | 2 | 6 | Modular/Clean |
| `isPointerType` | Type System | 5 | 1 | 1 | 2 | 1 | Modular/Clean |
| `isTopLevelDeclaration` | Type System | 19 | 3 | 1 | 2 | 3 | Modular/Clean |
| `isUnsignedIntegerType` | Type System | 16 | 2 | 1 | 2 | 2 | Modular/Clean |
| `is_type_undefined` | Type System | 4 | 1 | 1 | 2 | 1 | Modular/Clean |
| `logFeatureLocation` | Other | 22 | 1 | 0 | 2 | 1 | Modular/Clean |
| `needsStringLiteralCoercion` | Other | 11 | 1 | 1 | 2 | 1 | Modular/Clean |
| `registerAliasPlaceholderIfNeeded` | Resolution | 54 | 3 | 2 | 3 | 3 | Modular/Clean |
| `registerPlaceholders` | Resolution | 270 | 8 | 9 | 8 | 10 | Excessive Nesting |
| `reportAndReturnUndefined` | Other | 5 | 1 | 1 | 2 | 1 | Modular/Clean |
| `resolveAllPlaceholders` | Resolution | 132 | 5 | 4 | 5 | 7 | High Resolution Entanglement |
| `resolveCallSite` | Resolution | 106 | 4 | 4 | 4 | 4 | Modular/Clean |
| `resolveGlobalDeclarations` | Resolution | 30 | 5 | 2 | 2 | 7 | Modular/Clean |
| `resolveLabel` | Resolution | 17 | 4 | 2 | 2 | 4 | Modular/Clean |
| `resolveNamedPlaceholder` | Resolution | 78 | 6 | 4 | 3 | 6 | Modular/Clean |
| `resolveNamedType` | Resolution | 45 | 4 | 2 | 3 | 4 | Modular/Clean |
| `resolveOrVisit` | Resolution | 6 | 2 | 1 | 2 | 1 | Modular/Clean |
| `resolvePlaceholder` | Resolution | 78 | 4 | 3 | 3 | 4 | Modular/Clean |
| `resolveTypeAlias` | Resolution | 53 | 5 | 3 | 3 | 5 | Modular/Clean |
| `resolveTypeConstant` | Resolution | 39 | 4 | 2 | 2 | 4 | Modular/Clean |
| `signaturesMatch` | Other | 66 | 3 | 2 | 3 | 3 | Modular/Clean |
| `transformExternType` | Type System | 21 | 9 | 4 | 2 | 9 | Excessive Nesting |
| `tryPromoteLiteral` | Other | 21 | 3 | 1 | 2 | 3 | Modular/Clean |
| `unwrapType` | Type System | 28 | 4 | 2 | 2 | 4 | Modular/Clean |
| `validateRange` | Other | 38 | 2 | 1 | 2 | 2 | Modular/Clean |
| `validateStructOrUnionFields` | Other | 31 | 3 | 1 | 2 | 3 | Modular/Clean |
| `validateSwitch` | Other | 244 | 7 | 7 | 8 | 7 | Modular/Clean |
| `verifyTypeIdentity` | Type System | 42 | 3 | 1 | 3 | 5 | Modular/Clean |
| `visit` | Other | 178 | 14 | 10 | 6 | 10 | Excessive Nesting |
| `visitArrayAccess` | Expressions | 92 | 4 | 3 | 4 | 4 | Modular/Clean |
| `visitArraySlice` | Other | 162 | 4 | 5 | 6 | 4 | Modular/Clean |
| `visitArrayType` | Declarations | 49 | 3 | 1 | 3 | 3 | Modular/Clean |
| `visitAsExpr` | Expressions | 51 | 2 | 2 | 3 | 2 | Modular/Clean |
| `visitAssignment` | Other | 52 | 3 | 2 | 3 | 3 | Modular/Clean |
| `visitBinaryOp` | Expressions | 72 | 3 | 2 | 3 | 3 | Modular/Clean |
| `visitBlockStmt` | Statements | 121 | 9 | 6 | 5 | 9 | Handles local variable pre-insertion and the 'Forced Local Type Resolution' pass. |
| `visitBoolLiteral` | Expressions | 4 | 1 | 1 | 2 | 1 | Modular/Clean |
| `visitBreakStmt` | Statements | 17 | 3 | 1 | 2 | 3 | Modular/Clean |
| `visitCatchExpr` | Expressions | 51 | 3 | 2 | 3 | 3 | Modular/Clean |
| `visitCharLiteral` | Expressions | 4 | 1 | 1 | 2 | 1 | Modular/Clean |
| `visitCompoundAssignment` | Other | 89 | 3 | 2 | 4 | 5 | Modular/Clean |
| `visitComptimeBlock` | Statements | 8 | 1 | 1 | 2 | 1 | Modular/Clean |
| `visitContinueStmt` | Statements | 17 | 3 | 1 | 2 | 3 | Modular/Clean |
| `visitDeferStmt` | Statements | 11 | 1 | 1 | 2 | 1 | Modular/Clean |
| `visitEmptyStmt` | Statements | 4 | 1 | 1 | 2 | 1 | Modular/Clean |
| `visitEnumDecl` | Declarations | 130 | 5 | 4 | 5 | 5 | Complex Branching Logic |
| `visitErrdeferStmt` | Statements | 11 | 1 | 1 | 2 | 1 | Modular/Clean |
| `visitErrorLiteral` | Expressions | 7 | 1 | 1 | 2 | 1 | Modular/Clean |
| `visitErrorSetDefinition` | Other | 31 | 5 | 2 | 2 | 5 | Complex Branching Logic |
| `visitErrorSetMerge` | Other | 47 | 5 | 2 | 3 | 5 | Complex Branching Logic |
| `visitErrorUnionType` | Declarations | 15 | 2 | 1 | 2 | 2 | Modular/Clean |
| `visitExpressionStmt` | Statements | 8 | 1 | 1 | 2 | 1 | Modular/Clean |
| `visitFloatCast` | Coercion | 43 | 4 | 2 | 3 | 4 | Modular/Clean |
| `visitFloatLiteral` | Expressions | 6 | 1 | 1 | 2 | 1 | Modular/Clean |
| `visitFnBody` | Declarations | 205 | 11 | 9 | 7 | 10 | Manages function-level scope, return path validation, and deferred statement tracking. |
| `visitFnDecl` | Declarations | 10 | 2 | 1 | 2 | 1 | Modular/Clean |
| `visitFnSignature` | Declarations | 96 | 4 | 3 | 4 | 4 | Modular/Clean |
| `visitForStmt` | Statements | 101 | 5 | 4 | 4 | 5 | Complex Branching Logic |
| `visitFunctionCall` | Expressions | 466 | 7 | 10 | 10 | 9 | Handles direct calls, indirect calls, built-ins (@sizeOf etc.), and std.debug.print format validation. |
| `visitFunctionType` | Declarations | 28 | 3 | 1 | 2 | 3 | Modular/Clean |
| `visitIdentifier` | Expressions | 88 | 3 | 2 | 4 | 3 | Modular/Clean |
| `visitIfExpr` | Expressions | 100 | 3 | 3 | 4 | 3 | Modular/Clean |
| `visitIfStmt` | Statements | 59 | 3 | 2 | 3 | 3 | Modular/Clean |
| `visitImportStmt` | Statements | 13 | 2 | 1 | 2 | 1 | Modular/Clean |
| `visitIntCast` | Coercion | 57 | 3 | 2 | 3 | 3 | Modular/Clean |
| `visitIntToFloat` | Other | 38 | 3 | 1 | 2 | 3 | Modular/Clean |
| `visitIntegerLiteral` | Expressions | 26 | 4 | 2 | 2 | 4 | Modular/Clean |
| `visitMemberAccess` | Expressions | 544 | 12 | 10 | 10 | 10 | Hybrid logic for instance fields, static type access, slice/array/optional built-ins, and tagged union variants. Extremely high nesting (12 levels). |
| `visitNullLiteral` | Expressions | 4 | 1 | 1 | 2 | 1 | Modular/Clean |
| `visitOffsetOf` | Other | 72 | 4 | 3 | 3 | 4 | Modular/Clean |
| `visitOptionalType` | Declarations | 9 | 1 | 1 | 2 | 1 | Modular/Clean |
| `visitOrelseExpr` | Expressions | 42 | 3 | 1 | 3 | 3 | Modular/Clean |
| `visitPanic` | Other | 34 | 3 | 1 | 2 | 3 | Modular/Clean |
| `visitPointerType` | Declarations | 9 | 1 | 1 | 2 | 1 | Modular/Clean |
| `visitPtrCast` | Coercion | 31 | 3 | 1 | 2 | 3 | Modular/Clean |
| `visitRange` | Statements | 31 | 3 | 1 | 2 | 3 | Modular/Clean |
| `visitReturnStmt` | Statements | 58 | 4 | 3 | 3 | 4 | Modular/Clean |
| `visitStringLiteral` | Expressions | 9 | 1 | 1 | 2 | 1 | Modular/Clean |
| `visitStructDecl` | Declarations | 144 | 5 | 4 | 5 | 5 | Complex Branching Logic |
| `visitStructInitializer` | Expressions | 90 | 5 | 3 | 4 | 5 | Complex Branching Logic |
| `visitSwitchExpr` | Expressions | 9 | 2 | 1 | 2 | 1 | Modular/Clean |
| `visitSwitchStmt` | Statements | 17 | 2 | 1 | 2 | 2 | Modular/Clean |
| `visitTryExpr` | Expressions | 41 | 4 | 2 | 3 | 4 | Modular/Clean |
| `visitTupleLiteral` | Expressions | 101 | 5 | 4 | 4 | 5 | Complex Branching Logic |
| `visitTypeName` | Declarations | 80 | 8 | 5 | 4 | 8 | Excessive Nesting |
| `visitUnaryOp` | Expressions | 107 | 5 | 4 | 4 | 9 | Complex Branching Logic |
| `visitUndefinedLiteral` | Expressions | 5 | 1 | 1 | 2 | 1 | Modular/Clean |
| `visitUnionDecl` | Declarations | 149 | 4 | 4 | 5 | 4 | Modular/Clean |
| `visitUnreachable` | Other | 5 | 1 | 1 | 2 | 1 | Modular/Clean |
| `visitVarDecl` | Declarations | 585 | 8 | 10 | 10 | 8 | Complex state machine managing local/global scope, type inference, placeholder registration, and re-resolution passes. |
| `visitWhileStmt` | Statements | 77 | 3 | 2 | 3 | 3 | Modular/Clean |
