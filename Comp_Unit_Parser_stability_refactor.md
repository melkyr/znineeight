Technical Action Plan: Refactoring for Task 107 & Memory Safety

This document outlines the systematic approach to resolving the Parser shallow-copy memory corruption and implementing strict C89 assignment validation for Milestone 4 (Task 107).
1. Executive Summary

The current architecture suffers from memory corruption because CompilationUnit::createParser() returns a Parser by value, creating shallow copies that share Arena and SymbolTable pointers. The solution transitions the TypeChecker to a Resource-Observer model, where it references the CompilationUnit directly rather than owning a Parser.
2. Technical Constraints & Context

    Standard: C++98 (Strict).

    Memory: < 16MB Peak.

    Allocation: Arena-based (no malloc/free in hot paths).

    Environment: MSVC 6.0 compatibility (Win32 API only).

3. The Implementation Plan
Phase 1: AST & Infrastructure Setup

    Task 1.1: Update ast.hpp with assignment node types.

    Task 1.2: Update Parser.h to make the class non-copyable.

    Task 1.3: Modify CompilationUnit to return Parser* from createParser().

Required AST Additions (ast.hpp)
C++

// Add to NodeType enum
NODE_ASSIGNMENT,
NODE_COMPOUND_ASSIGNMENT,

// Struct definitions
typedef struct {
    struct ASTNode* lvalue;
    struct ASTNode* rvalue;
} ASTAssignmentNode;

typedef struct {
    struct ASTNode* lvalue;
    struct ASTNode* rvalue;
    TokenKind op; 
} ASTCompoundAssignmentNode;

// Add to ASTNode union
union {
    // ... existing ...
    ASTAssignmentNode assignment;
    ASTCompoundAssignmentNode compound_assignment;
} as;

Phase 2: Logic Implementation (TypeChecker)

The following code must be implemented in type_checker.hpp and type_checker.cpp.
TypeChecker.h
C++

#include "compilation_unit.hpp"

class TypeChecker {
public:
    TypeChecker(CompilationUnit& unit) : unit(unit) {}
    void check(ASTNode* root);

private:
    CompilationUnit& unit;

    Type* visit(ASTNode* node);
    Type* visitAssignment(ASTAssignmentNode* node);
    Type* visitCompoundAssignment(ASTCompoundAssignmentNode* node);
    Type* visitIdentifier(ASTIdentifierNode* node);
    Type* visitBinaryOp(ASTBinaryOpNode* node);
    Type* visitUnaryOp(ASTUnaryOpNode* node);
    Type* visitArrayAccess(ASTArrayAccessNode* node);
    Type* visitFieldAccess(ASTFieldAccessNode* node);

    bool isLValueConst(ASTNode* node);
    Type* checkBinaryOpCompatibility(Type* left, Type* right, TokenKind op, SourceLocation loc);
    bool areTypesCompatible(Type* left, Type* right);
    void fatalError(const char* msg);
    Type* findStructField(Type* struct_type, const char* field_name);
};

TypeChecker.cpp

    Note: This implementation adheres to the provided specification, ensuring fatalError is used for Task 107 strict C89 compliance.

C++

#include "type_checker.hpp"
#include "ast.hpp"
#include "type_system.hpp"
#include <cstring>

void TypeChecker::check(ASTNode* root) {
    visit(root);
}

Type* TypeChecker::visit(ASTNode* node) {
    if (!node) return NULL;
    if (node->resolved_type) return node->resolved_type;

    Type* resolved_type = NULL;
    switch (node->type) {
        case NODE_ASSIGNMENT:
            resolved_type = visitAssignment(&node->as.assignment);
            break;
        case NODE_COMPOUND_ASSIGNMENT:
            resolved_type = visitCompoundAssignment(&node->as.compound_assignment);
            break;
        case NODE_IDENTIFIER:
            resolved_type = visitIdentifier(&node->as.identifier);
            break;
        case NODE_BINARY_OP:
            resolved_type = visitBinaryOp(&node->as.binary_op);
            break;
        case NODE_UNARY_OP:
            resolved_type = visitUnaryOp(&node->as.unary_op);
            break;
        case NODE_ARRAY_ACCESS:
            resolved_type = visitArrayAccess(&node->as.array_access);
            break;
        default: break;
    }

    node->resolved_type = resolved_type;
    return resolved_type;
}

Type* TypeChecker::visitAssignment(ASTAssignmentNode* node) {
    Type* lvalue_type = visit(node->lvalue);
    if (!lvalue_type) return NULL;

    if (isLValueConst(node->lvalue)) {
        char msg_buffer[256];
        snprintf(msg_buffer, sizeof(msg_buffer), "Cannot assign to const location");
        unit.getErrorHandler().report(ERR_INVALID_OPERATION, node->lvalue->loc, msg_buffer, &unit.getArena());
        fatalError("Assignment validation failed");
        return NULL;
    }

    Type* rvalue_type = visit(node->rvalue);
    if (!rvalue_type) return NULL;

    if (!areTypesCompatible(lvalue_type, rvalue_type)) {
        char msg_buffer[256];
        const char* ltype_str = lvalue_type->name ? lvalue_type->name : "unknown";
        const char* rtype_str = rvalue_type->name ? rvalue_type->name : "unknown";
        snprintf(msg_buffer, sizeof(msg_buffer), "incompatible types in assignment, cannot assign '%s' to '%s'", rtype_str, ltype_str);
        unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->rvalue->loc, msg_buffer, &unit.getArena());
        fatalError("Assignment validation failed");
        return NULL;
    }
    return lvalue_type;
}

Type* TypeChecker::visitCompoundAssignment(ASTCompoundAssignmentNode* node) {
    Type* lvalue_type = visit(node->lvalue);
    if (!lvalue_type || isLValueConst(node->lvalue)) {
        fatalError("Assignment validation failed");
        return NULL;
    }

    Type* rvalue_type = visit(node->rvalue);
    if (!rvalue_type) return NULL;

    TokenKind binary_op;
    switch (node->op) {
        case TOKEN_PLUS_EQUAL: binary_op = TOKEN_PLUS; break;
        case TOKEN_MINUS_EQUAL: binary_op = TOKEN_MINUS; break;
        case TOKEN_STAR_EQUAL: binary_op = TOKEN_STAR; break;
        case TOKEN_SLASH_EQUAL: binary_op = TOKEN_SLASH; break;
        case TOKEN_PERCENT_EQUAL: binary_op = TOKEN_PERCENT; break;
        default: fatalError("Unknown compound assignment operator"); return NULL;
    }

    Type* result_of_op_type = checkBinaryOpCompatibility(lvalue_type, rvalue_type, binary_op, node->rvalue->loc);
    if (!result_of_op_type || !areTypesCompatible(lvalue_type, result_of_op_type)) {
        fatalError("Assignment validation failed");
        return NULL;
    }
    return lvalue_type;
}

Type* TypeChecker::visitArrayAccess(ASTArrayAccessNode* node) {
    Type* array_type = visit(node->array);
    Type* index_type = visit(node->index);

    if (!array_type || !index_type) return NULL;
    if (array_type->kind != TYPE_ARRAY && array_type->kind != TYPE_POINTER) return NULL;
    if (index_type->kind < TYPE_I8 || index_type->kind > TYPE_USIZE) return NULL;

    return (array_type->kind == TYPE_ARRAY) ? array_type->as.array.element_type : array_type->as.pointer.base;
}

Type* TypeChecker::visitFieldAccess(ASTFieldAccessNode* node) {
    Type* container_type = visit(node->container);
    if (!container_type || (container_type->kind != TYPE_STRUCT && container_type->kind != TYPE_UNION)) return NULL;

    Type* field_type = findStructField(container_type, node->field_name);
    if (!field_type) return NULL;

    return field_type;
}

Type* TypeChecker::visitIdentifier(ASTIdentifierNode* node) {
    Symbol* symbol = unit.getSymbolTable().lookup(node->name);
    if (!symbol) return NULL;
    return symbol->symbol_type;
}

bool TypeChecker::isLValueConst(ASTNode* node) {
    if (!node) return false;
    switch (node->type) {
        case NODE_IDENTIFIER: {
            Symbol* symbol = unit.getSymbolTable().lookup(node->as.identifier.name);
            return (symbol && symbol->details && ((ASTVarDeclNode*)symbol->details)->is_const);
        }
        case NODE_UNARY_OP:
            if (node->as.unary_op.op == TOKEN_STAR) {
                Type* ptr_type = visit(node->as.unary_op.operand);
                return (ptr_type && ptr_type->kind == TYPE_POINTER && ptr_type->as.pointer.is_const);
            }
            return false;
        default: return false;
    }
}

Type* TypeChecker::checkBinaryOpCompatibility(Type* left, Type* right, TokenKind op, SourceLocation loc) {
    if ((left->kind >= TYPE_I8 && left->kind <= TYPE_F64) && (right->kind >= TYPE_I8 && right->kind <= TYPE_F64)) {
        return left; // Simplified promotion
    }
    return NULL;
}

bool TypeChecker::areTypesCompatible(Type* left, Type* right) {
    if (!left || !right) return false;
    return left->kind == right->kind; 
}

void TypeChecker::fatalError(const char* msg) {
#ifdef _WIN32
    OutputDebugStringA("TypeChecker Fatal Error: ");
    OutputDebugStringA(msg);
    OutputDebugStringA("\n");
#endif
    abort();
}

Type* TypeChecker::findStructField(Type* struct_type, const char* field_name) {
    if (struct_type->kind != TYPE_STRUCT) return NULL;
    // Placeholder for field lookup logic
    return NULL;
}

4. Test Refactoring Roadmap

To resolve the 300+ non-compiling tests, follow this grouped action plan. Each group represents a set of tests that must be updated to the new TypeChecker(CompilationUnit&) constructor and Parser* return type.
Group 1: Core Infrastructure (Highest Priority)

    Infrastructure: Update test_DynamicArray, test_ArenaAllocator, and test_SymbolTable.

    Action: Ensure memory safety is confirmed before proceeding to logic.

Group 2: Lexer Logic

    Float/Integer/String Literals: Refactor all test_Lexer_... to utilize the CompilationUnit for source management.

    Action: Update setup methods to create a CompilationUnit instance first.

Group 3: Parser & AST (Bulk Work)

    Postfix/Binary/Unary: Update tests in Group 3A and 3B.

    Declarations: Refactor Group 3C (Structs/Unions), 3D (Enums), and 3E (Functions).

    Control Flow: Fix Group 3F (If, For, Blocks).

# Tests Guide

This guide provides a structured approach to refactoring the test suite. The tests are grouped by functionality to allow for incremental updates. To disable a group, comment out the corresponding test functions in the `tests` array within `tests/main.cpp`.

## Group 1: Core Compiler Infrastructure & Memory

### Group 1A: Memory Management (`ArenaAllocator`, `DynamicArray`)
**To disable, comment out:**
```cpp
// test_DynamicArray_ShouldUseCopyConstructionOnReallocation,
// test_ArenaAllocator_AllocShouldReturn8ByteAligned,
// test_arena_alloc_out_of_memory,
// test_arena_alloc_zero_size,
// test_arena_alloc_aligned_out_of_memory,
// test_arena_alloc_aligned_overflow_check,
// test_basic_allocation,
// test_multiple_allocations,
// test_allocation_failure,
// test_reset,
// test_aligned_allocation,
// test_dynamic_array_append,
// test_dynamic_array_growth,
// test_dynamic_array_growth_from_zero,
// test_dynamic_array_non_pod_reallocation,
```

### Group 1B: Core Components (`StringInterner`, `SymbolTable`, `CompilationUnit`)
**To disable, comment out:**
```cpp
// test_string_interning,
// test_compilation_unit_creation,
// test_compilation_unit_var_decl,
// test_SymbolBuilder_BuildsCorrectly,
// test_SymbolTable_DuplicateDetection,
// test_SymbolTable_NestedScopes_And_Lookup,
// test_SymbolTable_HashTableResize,
```
---
## Group 2: Lexer

### Group 2A: Float Literals
**To disable, comment out:**
```cpp
// test_Lexer_FloatWithUnderscores_IntegerPart,
// test_Lexer_FloatWithUnderscores_FractionalPart,
// test_Lexer_FloatWithUnderscores_ExponentPart,
// test_Lexer_FloatWithUnderscores_AllParts,
// test_Lexer_FloatSimpleDecimal,
// test_Lexer_FloatNoFractionalPart,
// test_Lexer_FloatNoIntegerPart,
// test_Lexer_FloatWithExponent,
// test_Lexer_FloatWithNegativeExponent,
// test_Lexer_FloatExponentNoSign,
// test_Lexer_FloatIntegerWithExponent,
// test_Lexer_FloatExponentNoDigits,
// test_Lexer_FloatHexSimple,
// test_Lexer_FloatHexNoFractionalPart,
// test_Lexer_FloatHexNegativeExponent,
// test_Lexer_FloatHexInvalidFormat,
```

### Group 2B: Integer & String Literals
**To disable, comment out:**
```cpp
// test_lexer_integer_overflow,
// test_lexer_c_string_literal,
// test_lexer_handles_unicode_correctly,
// test_lexer_handles_unterminated_char_hex_escape,
// test_lexer_handles_unterminated_string_hex_escape,
// test_Lexer_HandlesU64Integer,
// test_Lexer_UnterminatedCharHexEscape,
// test_Lexer_UnterminatedStringHexEscape,
// test_Lexer_UnicodeInStringLiteral,
// test_IntegerLiterals,
// test_Lexer_StringLiteral_EscapedCharacters,
// test_Lexer_StringLiteral_LongString,
// test_IntegerLiteralParsing_UnsignedSuffix,
// test_IntegerLiteralParsing_LongSuffix,
// test_IntegerLiteralParsing_UnsignedLongSuffix,
```

### Group 2C: Operators & Delimiters
**To disable, comment out:**
```cpp
// test_single_char_tokens,
// test_multi_char_tokens,
// test_assignment_vs_equality,
// test_lex_arithmetic_and_bitwise_operators,
// test_Lexer_RangeExpression,
// test_lex_compound_assignment_operators,
// test_LexerSpecialOperators,
// test_LexerSpecialOperatorsMixed,
// test_Lexer_Delimiters,
// test_Lexer_DotOperators,
```

### Group 2D: Keywords & Comments
**To disable, comment out:**
```cpp
// test_skip_comments,
// test_nested_block_comments,
// test_unterminated_block_comment,
// test_lex_visibility_and_linkage_keywords,
// test_lex_compile_time_and_special_function_keywords,
// test_lex_miscellaneous_keywords,
// test_lex_missing_keywords,
```

### Group 2E: Identifiers, Integration & Edge Cases
**To disable, comment out:**
```cpp
// test_lexer_handles_tab_correctly,
// test_lexer_handles_long_identifier,
// test_Lexer_HandlesLongIdentifier,
// test_Lexer_NumericLookaheadSafety,
// test_token_fields_are_initialized,
// test_Lexer_ComprehensiveCrossGroup,
// test_Lexer_IdentifiersAndStrings,
// test_Lexer_ErrorConditions,
// test_IntegerRangeAmbiguity,
// test_Lexer_MultiLineIntegrationTest,
```

---
## Group 3: Parser & AST

### Group 3A: Basic AST Nodes & Primary Expressions
**To disable, comment out:**
```cpp
// test_ASTNode_IntegerLiteral,
// test_ASTNode_FloatLiteral,
// test_ASTNode_CharLiteral,
// test_ASTNode_StringLiteral,
// test_ASTNode_Identifier,
// test_ASTNode_UnaryOp,
// test_ASTNode_BinaryOp,
// test_Parser_ParsePrimaryExpr_IntegerLiteral,
// test_Parser_ParsePrimaryExpr_FloatLiteral,
// test_Parser_ParsePrimaryExpr_CharLiteral,
// test_Parser_ParsePrimaryExpr_StringLiteral,
// test_Parser_ParsePrimaryExpr_Identifier,
// test_Parser_ParsePrimaryExpr_ParenthesizedExpression,
```

### Group 3B: Postfix, Binary & Advanced Expressions
**To disable, comment out:**
```cpp
// test_Parser_FunctionCall_NoArgs,
// test_Parser_FunctionCall_WithArgs,
// test_Parser_FunctionCall_WithTrailingComma,
// test_Parser_ArrayAccess,
// test_Parser_ChainedPostfixOps,
// test_Parser_BinaryExpr_SimplePrecedence,
// test_Parser_BinaryExpr_LeftAssociativity,
// test_Parser_TryExpr_Simple,
// test_Parser_TryExpr_Chained,
// test_Parser_CatchExpression_Simple,
// test_Parser_CatchExpression_WithPayload,
// test_Parser_CatchExpression_RightAssociativity,
```

### Group 3C: Struct & Union Declarations
**To disable, comment out:**
```cpp
// test_ASTNode_ContainerDeclarations,
// test_Parser_Struct_Error_MissingLBrace,
// test_Parser_Struct_Error_MissingRBrace,
// test_Parser_Struct_Error_MissingColon,
// test_Parser_Struct_Error_MissingType,
// test_Parser_Struct_Error_InvalidField,
// test_Parser_StructDeclaration_Simple,
// test_Parser_StructDeclaration_Empty,
// test_Parser_StructDeclaration_MultipleFields,
// test_Parser_StructDeclaration_WithTrailingComma,
// test_Parser_StructDeclaration_ComplexFieldType,
// test_ParserBug_TopLevelUnion,
// test_ParserBug_TopLevelStruct,
// test_ParserBug_UnionFieldNodeType,
```

### Group 3D: Enum Declarations
**To disable, comment out:**
```cpp
// test_Parser_Enum_Empty,
// test_Parser_Enum_SimpleMembers,
// test_Parser_Enum_TrailingComma,
// test_Parser_Enum_WithValues,
// test_Parser_Enum_MixedMembers,
// test_Parser_Enum_WithBackingType,
// test_Parser_Enum_SyntaxError_MissingOpeningBrace,
// test_Parser_Enum_SyntaxError_MissingClosingBrace,
// test_Parser_Enum_SyntaxError_NoComma,
// test_Parser_Enum_SyntaxError_InvalidMember,
// test_Parser_Enum_SyntaxError_MissingInitializer,
// test_Parser_Enum_SyntaxError_BackingTypeNoParens,
// test_Parser_Enum_ComplexInitializer,
```

### Group 3E: Function & Variable Declarations
**To disable, comment out:**
```cpp
// test_Parser_FnDecl_ValidEmpty,
// test_Parser_FnDecl_Error_NonEmptyParams,
// test_Parser_FnDecl_Error_NonEmptyBody,
// test_Parser_FnDecl_Error_MissingArrow,
// test_Parser_FnDecl_Error_MissingReturnType,
// test_Parser_FnDecl_Error_MissingParens,
// test_Parser_NonEmptyFunctionBody,
// test_Parser_VarDecl_InsertsSymbolCorrectly,
// test_Parser_VarDecl_DetectsDuplicateSymbol,
// test_Parser_FnDecl_AndScopeManagement,
```

### Group 3F: Control Flow & Blocks
**To disable, comment out:**
```cpp
// test_ASTNode_ForStmt,
// test_ASTNode_SwitchExpr,
// test_Parser_IfStatement_Simple,
// test_Parser_IfStatement_WithElse,
// test_Parser_ParseEmptyBlock,
// test_Parser_ParseBlockWithEmptyStatement,
// test_Parser_ParseBlockWithMultipleEmptyStatements,
// test_Parser_ParseBlockWithNestedEmptyBlock,
// test_Parser_ParseBlockWithMultipleNestedEmptyBlocks,
// test_Parser_ParseBlockWithNestedBlockAndEmptyStatement,
// test_Parser_ErrDeferStatement_Simple,
// test_Parser_ComptimeBlock_Valid,
// test_Parser_NestedBlocks_AndShadowing,
// test_Parser_SymbolDoesNotLeakFromInnerScope,
```

### Group 3G: Parser Error Handling
**To disable, comment out:**
```cpp
// test_Parser_Error_OnUnexpectedToken,
// test_Parser_Error_OnMissingColon,
// test_Parser_IfStatement_Error_MissingLParen,
// test_Parser_IfStatement_Error_MissingRParen,
// test_Parser_IfStatement_Error_MissingThenBlock,
// test_Parser_IfStatement_Error_MissingElseBlock,
// test_Parser_BinaryExpr_Error_MissingRHS,
// test_Parser_TryExpr_InvalidSyntax,
// test_Parser_CatchExpression_Error_MissingElseExpr,
// test_Parser_CatchExpression_Error_IncompletePayload,
// test_Parser_CatchExpression_Error_MissingPipe,
// test_Parser_ErrDeferStatement_Error_MissingBlock,
// test_Parser_ComptimeBlock_Error_MissingExpression,
// test_Parser_ComptimeBlock_Error_MissingOpeningBrace,
// test_Parser_ComptimeBlock_Error_MissingClosingBrace,
```

### Group 3H: Integration, Bugs, and Edge Cases
**To disable, comment out:**
```cpp
// test_Parser_AbortOnAllocationFailure,
// test_Parser_TokenStreamLifetimeIsIndependentOfParserObject,
// test_ParserIntegration_VarDeclWithBinaryExpr,
// test_ParserIntegration_IfWithComplexCondition,
// test_ParserIntegration_WhileWithFunctionCall,
// test_ParserBug_LogicalOperatorSymbol,
// test_Parser_RecursionLimit,
// test_Parser_RecursionLimit_Unary,
// test_Parser_RecursionLimit_Binary,
// test_Parser_CopyIsSafeAndDoesNotDoubleFree,
// test_Parser_Bugfix_HandlesExpressionStatement,
```

---
## Group 4: Type Checker & C89 Compatibility

### Group 4A: Literal & Primitive Type Inference
**To disable, comment out:**
```cpp
// test_TypeChecker_IntegerLiteralInference,
// test_TypeChecker_FloatLiteralInference,
// test_TypeChecker_CharLiteralInference,
// test_TypeChecker_StringLiteralInference,
// test_TypeCheckerStringLiteralType,
// test_TypeCheckerIntegerLiteralType,
// test_TypeChecker_C89IntegerCompatibility,
// test_TypeResolution_ValidPrimitives,
// test_TypeResolution_InvalidOrUnsupported,
// test_TypeResolution_AllPrimitives,
// test_TypeChecker_BoolLiteral,
// test_TypeChecker_IntegerLiteral,
// test_TypeChecker_CharLiteral,
// test_TypeChecker_StringLiteral,
// test_TypeChecker_Identifier,
```

### Group 4B: Variable Declaration & Scope
**To disable, comment out:**
```cpp
// test_TypeCheckerValidDeclarations,
// test_TypeCheckerInvalidDeclarations,
// test_TypeCheckerUndeclaredVariable,
// test_TypeChecker_VarDecl_Valid_Simple,
// test_TypeChecker_VarDecl_Invalid_Mismatch,
// test_TypeChecker_VarDecl_Valid_Widening,
// test_TypeChecker_VarDecl_Multiple_Errors,
```

### Group 4C: Function Declarations & Return Validation
**To disable, comment out:**
```cpp
// test_ReturnTypeValidation_Valid,
// test_ReturnTypeValidation_Invalid,
// test_TypeCheckerFnDecl_ValidSimpleParams,
// test_TypeCheckerFnDecl_InvalidParamType,
// test_TypeCheckerVoidTests_ImplicitReturnInVoidFunction,
// test_TypeCheckerVoidTests_ExplicitReturnInVoidFunction,
// test_TypeCheckerVoidTests_ReturnValueInVoidFunction,
// test_TypeCheckerVoidTests_MissingReturnValueInNonVoidFunction,
// test_TypeCheckerVoidTests_ImplicitReturnInNonVoidFunction,
// test_TypeCheckerVoidTests_AllPathsReturnInNonVoidFunction,
```

### Group 4D: Pointer Operations
**To disable, comment out:**
```cpp
// test_TypeChecker_Dereference_ValidPointer,
// test_TypeChecker_Dereference_Invalid_NonPointer,
// test_TypeChecker_Dereference_ConstPointer,
// test_TypeChecker_AddressOf_Invalid_RValue,
// test_TypeChecker_AddressOf_Valid_LValues,
// test_TypeCheckerPointerOps_AddressOf_ValidLValue,
// test_TypeCheckerPointerOps_AddressOf_InvalidRValue,
// test_TypeCheckerPointerOps_Dereference_ValidPointer,
// test_TypeCheckerPointerOps_Dereference_InvalidNonPointer,
```

### Group 4E: Pointer Arithmetic
**To disable, comment out:**
```cpp
// test_TypeCheckerVoidTests_PointerAddition,
// test_TypeChecker_PointerIntegerAddition,
// test_TypeChecker_IntegerPointerAddition,
// test_TypeChecker_PointerIntegerSubtraction,
// test_TypeChecker_PointerPointerSubtraction,
// test_TypeChecker_Invalid_PointerPointerAddition,
// test_TypeChecker_Invalid_PointerPointerSubtraction_DifferentTypes,
// test_TypeChecker_Invalid_PointerMultiplication,
// test_TypeCheckerPointerOps_Arithmetic_PointerInteger,
// test_TypeCheckerPointerOps_Arithmetic_PointerPointer,
// test_TypeCheckerPointerOps_Arithmetic_InvalidOperations,
```

### Group 4F: Binary & Logical Operations
**To disable, comment out:**
```cpp
// test_TypeCheckerBinaryOps_PointerArithmetic,
// test_TypeCheckerBinaryOps_NumericArithmetic,
// test_TypeCheckerBinaryOps_Comparison,
// test_TypeCheckerBinaryOps_Bitwise,
// test_TypeCheckerBinaryOps_Logical,
// test_TypeChecker_Bool_ComparisonOps,
// test_TypeChecker_Bool_LogicalOps,
```

### Group 4G: Control Flow (`if`, `while`)
**To disable, comment out:**
```cpp
// test_TypeCheckerControlFlow_IfStatementWithBooleanCondition,
// test_TypeCheckerControlFlow_IfStatementWithIntegerCondition,
// test_TypeCheckerControlFlow_IfStatementWithPointerCondition,
// test_TypeCheckerControlFlow_IfStatementWithFloatCondition,
// test_TypeCheckerControlFlow_IfStatementWithVoidCondition,
// test_TypeCheckerControlFlow_WhileStatementWithBooleanCondition,
// test_TypeCheckerControlFlow_WhileStatementWithIntegerCondition,
// test_TypeCheckerControlFlow_WhileStatementWithPointerCondition,
// test_TypeCheckerControlFlow_WhileStatementWithFloatCondition,
// test_TypeCheckerControlFlow_WhileStatementWithVoidCondition,
```

### Group 4H: Container & Enum Validation
**To disable, comment out:**
```cpp
// test_TypeChecker_C89_StructFieldValidation_Slice,
// test_TypeChecker_C89_UnionFieldValidation_MultiLevelPointer,
// test_TypeChecker_C89_StructFieldValidation_ValidArray,
// test_TypeChecker_C89_UnionFieldValidation_ValidFields,
// test_TypeCheckerEnumTests_SignedIntegerOverflow,
// test_TypeCheckerEnumTests_SignedIntegerUnderflow,
// test_TypeCheckerEnumTests_UnsignedIntegerOverflow,
// test_TypeCheckerEnumTests_NegativeValueInUnsignedEnum,
// test_TypeCheckerEnumTests_AutoIncrementOverflow,
// test_TypeCheckerEnumTests_AutoIncrementSignedOverflow,
// test_TypeCheckerEnumTests_ValidValues,
```

### Group 4I: C89 Compatibility & Misc
**To disable, comment out:**
```cpp
// test_TypeChecker_RejectSlice,
// test_TypeChecker_RejectNonConstantArraySize,
// test_TypeChecker_AcceptsValidArrayDeclaration,
// test_TypeCheckerVoidTests_DisallowVoidVariableDeclaration,
// test_TypeCompatibility,
// test_TypeToString_Reentrancy,
// test_TypeCheckerC89Compat_RejectFunctionWithTooManyArgs,
// test_TypeChecker_Call_WrongArgumentCount,
// test_TypeChecker_Call_IncompatibleArgumentType,
// test_TypeCheckerC89Compat_FloatWidening,
// test_C89TypeMapping_Validation,
// test_C89Compat_FunctionTypeValidation,
// test_TypeChecker_Bool_Literals,
```

Phase 1: AST & Infrastructure Foundations

Goal: Prepare the data structures and prevent further memory corruption by enforcing the "No-Copy" rule.

    [ ] Task 1.1: Add NODE_ASSIGNMENT and NODE_COMPOUND_ASSIGNMENT to the NodeType enum in ast.hpp.

    [ ] Task 1.2: Define ASTAssignmentNode and ASTCompoundAssignmentNode structs in ast.hpp.

    [ ] Task 1.3: Update the ASTNode union in ast.hpp to include the two new assignment nodes.

    [ ] Task 1.4: In parser.hpp, move the Parser copy constructor and assignment operator to the private section to trigger compiler errors wherever copying occurs.

    [ ] Task 1.5: Change the return type of CompilationUnit::createParser() from Parser to Parser*.

    [ ] Task 1.6: Update createParser() implementation to allocate the Parser instance using the arena_.

Phase 2: TypeChecker Architecture Migration

Goal: Transition the TypeChecker from owning a parser to observing the CompilationUnit.

    [ ] Task 2.1: Modify the TypeChecker constructor in type_checker.hpp to accept CompilationUnit& unit.

    [ ] Task 2.2: Update the TypeChecker private member from Parser parser_ to CompilationUnit& unit.

    [ ] Task 2.3: Update the TypeChecker::visit dispatcher switch-case to include routes for NODE_ASSIGNMENT and NODE_COMPOUND_ASSIGNMENT.

    [ ] Task 2.4: Implement the fatalError wrapper using OutputDebugStringA and abort() for strict C89 compliance.

Phase 3: Assignment & L-Value Logic

Goal: Implement the specific semantic rules for Milestone 4 / Task 107.

    [ ] Task 3.1: Implement isLValueConst to check the is_const flag on Symbol metadata.

    [ ] Task 3.2: Implement visitAssignment with the 3-step check:

        Is L-value valid?

        Is it non-const?

        Are types compatible?

    [ ] Task 3.3: Implement visitCompoundAssignment with operator mapping (e.g., += → +).

    [ ] Task 3.4: Implement checkBinaryOpCompatibility for basic numeric types (I8 through F64).

    [ ] Task 3.5: Implement findStructField placeholder to allow the compiler to build (stubbed for now).

Phase 4: Incremental Test Refactoring (The 300+ Fix)

Goal: Restore the test suite by updating setup logic to the new pointer-based model.

    [ ] Task 4.1: Global Search & Replace: Identify all instances of TypeChecker tc(parser) and prepare to update them to TypeChecker tc(unit).

    [ ] Task 4.2: Group 1 Fix: Update all tests in Group 1A and 1B (Core Infrastructure). Verify they compile and pass.

    [ ] Task 4.3: Group 2 Fix: Update all Lexer tests. Since Lexers often don't need TypeChecker, ensure the Parser* update is applied correctly.

    [ ] Task 4.4: Group 3 Fix (Batch A): Update Group 3A (Basic AST) and 3B (Expressions).

    [ ] Task 4.5: Group 3 Fix (Batch B): Update Group 3C through 3G (Declarations and Control Flow).
    
    [ ] Task 4.6: Group 3 Fix (Batch B): Update Group 3H Integration, Bugs, and Edge Cases
    
    [ ] Task 4.7: Group 4 Fix (Batch A): Update Group 4A through 4D
    
    [ ] Task 4.8: Group 4 Fix (Batch B): Update Group 4E through 4G
    
    [ ] Task 4.9: Group 4 Fix (Batch B): Update Group 4H and 4I
    
    [ ] Task 4.10: Check if the full suite yet has errors and document which tests are remaining for fixes
    - **Blocked:** The test suite currently fails to compile, preventing a full run. The following tasks must be completed before this task can be executed.
        - The following test files failed to compile:
            - `tests/type_checker_tests.cpp`
            - `tests/type_checker_enum_tests.cpp`

    [ ] Task 4.11: Fix compilation errors in `tests/type_checker_tests.cpp`
    - This test file is failing to compile due to linker errors related to `test_framework` and `test_utils`.

    [ ] Task 4.12: Fix compilation errors in `tests/type_checker_enum_tests.cpp`
    - This test file is failing to compile due to an undefined reference to `expect_type_checker_abort`.

    [ ] Task 4.13: Fix Remaining tests (yet in isolation)

    [ ] Task 4.14: Run the full suite and ensure 0 compilation errors remain.

Phase 5: Documentation & Handover

Goal: Seal the task so the next AI agent or developer has full context.

    [ ] Task 5.1: Update AST_parser.md with the new node diagrams and struct layouts.

    [ ] Task 5.2: Add the "L-Value & Assignment" section to Bootstrap_type_system_and_semantics.md.

    [ ] Task 5.3: Update AI_tasks.md: Mark Task 107 as "Completed" and note the shift to the CompilationUnit reference model.
