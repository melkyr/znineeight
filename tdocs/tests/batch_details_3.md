# Z98 Test Batch 3 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 115 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_TypeChecker_IntegerLiteralInference`
- **Implementation Source**: `tests/type_checker_literals.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `type not equals null` is satisfied
  2. Assert that `TYPE_I32` matches `kind of type`
  3. Assert that `TYPE_U32` matches `kind of type`
  4. Assert that `TYPE_I64` matches `kind of type`
  5. Assert that `TYPE_U64` matches `kind of type`
  ```

### `test_TypeChecker_FloatLiteralInference`
- **Implementation Source**: `tests/type_checker_literals.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `type_f64 not equals null` is satisfied
  2. Assert that `TYPE_F64` matches `kind of type_f64`
  ```

### `test_TypeChecker_CharLiteralInference`
- **Implementation Source**: `tests/type_checker_literals.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `type_u8 not equals null` is satisfied
  2. Assert that `TYPE_U8` matches `kind of type_u8`
  ```

### `test_TypeChecker_StringLiteralInference`
- **Implementation Source**: `tests/type_checker_literals.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `type_ptr_const_u8 not equals null` is satisfied
  2. Assert that `TYPE_POINTER` matches `kind of type_ptr_const_u8`
  3. Assert that `TYPE_ARRAY` matches `type_ptr_const_u8.as.pointer.kind of base`
  4. Assert that `TYPE_U8` matches `type_ptr_const_u8.as.pointer.base.as.array.kind of element_type`
  5. Validate that `type_ptr_const_u8.as.pointer.is_const` is satisfied
  ```

### `test_TypeCheckerStringLiteralType`
- **Implementation Source**: `tests/type_checker_tests.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void { \
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_STRING_LITERAL` matches `string_literal_node.type`
  2. Validate that `result_type not equals null` is satisfied
  3. Assert that `TYPE_POINTER` matches `kind of result_type`
  4. Validate that `result_type.as.pointer.base not equals null` is satisfied
  5. Assert that `TYPE_ARRAY` matches `result_type.as.pointer.kind of base`
  6. Assert that `TYPE_U8` matches `result_type.as.pointer.base.as.array.kind of element_type`
  ```

### `test_TypeCheckerIntegerLiteralType`
- **Implementation Source**: `tests/type_checker_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TYPE_I32` matches `kind of type_i32_max`
  2. Assert that `TYPE_I64` matches `kind of type_i32_min`
  3. Assert that `TYPE_I64` matches `kind of type_i64_over`
  4. Assert that `TYPE_I64` matches `kind of type_i64_under`
  ```

### `test_TypeChecker_C89IntegerCompatibility`
- **Implementation Source**: `tests/type_checker_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `&node1` matches `checker.visitIntegerLiteral(null`
  2. Assert that `&node2` matches `checker.visitIntegerLiteral(null`
  3. Assert that `&node3` matches `checker.visitIntegerLiteral(null`
  4. Assert that `&node4` matches `checker.visitIntegerLiteral(null`
  5. Assert that `&node5` matches `checker.visitIntegerLiteral(null`
  6. Assert that `&node6` matches `checker.visitIntegerLiteral(null`
  ```

### `test_TypeResolution_ValidPrimitives`
- **Implementation Source**: `tests/type_system_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `t_i32 not equals null` is satisfied
  2. Assert that `TYPE_I32` matches `kind of t_i32`
  3. Assert that `4` matches `t_i32.size`
  4. Assert that `4` matches `t_i32.alignment`
  5. Validate that `t_bool not equals null` is satisfied
  6. Assert that `TYPE_BOOL` matches `kind of t_bool`
  7. Assert that `4` matches `t_bool.size`
  8. Assert that `4` matches `t_bool.alignment`
  9. Validate that `t_f64 not equals null` is satisfied
  10. Assert that `TYPE_F64` matches `kind of t_f64`
  11. Assert that `8` matches `t_f64.size`
  12. Assert that `8` matches `t_f64.alignment`
  ```

### `test_TypeResolution_InvalidOrUnsupported`
- **Implementation Source**: `tests/type_system_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `t_invalid equals null` is satisfied
  2. Validate that `t_almost equals null` is satisfied
  3. Validate that `t_empty equals null` is satisfied
  ```

### `test_TypeResolution_AllPrimitives`
- **Implementation Source**: `tests/type_system_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `resolvePrimitiveTypeName("void"` is satisfied
  2. Validate that `resolvePrimitiveTypeName("bool"` is satisfied
  3. Validate that `resolvePrimitiveTypeName("i8"` is satisfied
  4. Validate that `resolvePrimitiveTypeName("i16"` is satisfied
  5. Validate that `resolvePrimitiveTypeName("i32"` is satisfied
  6. Validate that `resolvePrimitiveTypeName("i64"` is satisfied
  7. Validate that `resolvePrimitiveTypeName("u8"` is satisfied
  8. Validate that `resolvePrimitiveTypeName("u16"` is satisfied
  9. Validate that `resolvePrimitiveTypeName("u32"` is satisfied
  10. Validate that `resolvePrimitiveTypeName("u64"` is satisfied
  11. Validate that `resolvePrimitiveTypeName("isize"` is satisfied
  12. Validate that `resolvePrimitiveTypeName("usize"` is satisfied
  13. Validate that `resolvePrimitiveTypeName("f32"` is satisfied
  14. Validate that `resolvePrimitiveTypeName("f64"` is satisfied
  ```

### `test_TypeChecker_BoolLiteral`
- **Implementation Source**: `tests/type_checker_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `type not equals null` is satisfied
  2. Assert that `TYPE_BOOL` matches `kind of type`
  ```

### `test_TypeChecker_IntegerLiteral`
- **Implementation Source**: `tests/type_checker_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `type not equals null` is satisfied
  2. Assert that `TYPE_I32` matches `kind of type`
  3. Assert that `TYPE_I64` matches `kind of type`
  ```

### `test_TypeChecker_CharLiteral`
- **Implementation Source**: `tests/type_checker_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `type not equals null` is satisfied
  2. Assert that `TYPE_U8` matches `kind of type`
  ```

### `test_TypeChecker_StringLiteral`
- **Implementation Source**: `tests/type_checker_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `type not equals null` is satisfied
  2. Assert that `TYPE_POINTER` matches `kind of type`
  3. Validate that `type.as.pointer.is_const` is satisfied
  4. Assert that `TYPE_ARRAY` matches `type.as.pointer.kind of base`
  5. Assert that `TYPE_U8` matches `type.as.pointer.base.as.array.kind of element_type`
  ```

### `test_TypeChecker_Identifier`
- **Implementation Source**: `tests/type_checker_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `type not equals null` is satisfied
  2. Assert that `TYPE_I32` matches `kind of type`
  3. Ensure that `unit.getErrorHandler` is false
  4. Validate that `type equals null` is satisfied
  5. Validate that `unit.getErrorHandler` is satisfied
  6. Assert that `ERR_UNDEFINED_VARIABLE` matches `unit.getErrorHandler().getErrors()[0].code`
  ```

### `test_TypeCheckerValidDeclarations`
- **Implementation Source**: `tests/type_checker_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: i32 = 10;
  ```
  ```zig
var y: i64 = 3000000000;
  ```
  ```zig
var z: bool = true;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `context_i32.getCompilationUnit` is false
  2. Ensure that `context_i64.getCompilationUnit` is false
  3. Ensure that `context_bool.getCompilationUnit` is false
  ```

### `test_TypeCheckerInvalidDeclarations`
- **Implementation Source**: `tests/type_checker_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: i32 = \
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `context.getCompilationUnit` is satisfied
  ```

### `test_TypeCheckerUndeclaredVariable`
- **Implementation Source**: `tests/type_checker_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: i32 = y;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `context.getCompilationUnit` is satisfied
  ```

### `test_TypeChecker_VarDecl_Valid_Simple`
- **Implementation Source**: `tests/type_checker_var_decl.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: i32 = 42;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `root not equals null` is satisfied
  2. Ensure that `ctx.getCompilationUnit` is false
  ```

### `test_TypeChecker_VarDecl_Invalid_Mismatch`
- **Implementation Source**: `tests/type_checker_var_decl.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: i32 = \
  ```
  ```zig
;
    ParserTestContext ctx(source, arena, interner);
    TypeChecker type_checker(ctx.getCompilationUnit());

    ASTNode* root = ctx.getParser()->parse();
    ASSERT_TRUE(root != NULL);

    type_checker.check(root);

    ErrorHandler& eh = ctx.getCompilationUnit().getErrorHandler();
    ASSERT_TRUE(eh.hasErrors());

    const DynamicArray<ErrorReport>& errors = eh.getErrors();
    ASSERT_TRUE(errors.length() >= 1);
    ASSERT_STREQ(errors[0].message,
  ```
  ```zig
Incompatible assignment: '*const [5]u8' to 'i32'
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `root not equals null` is satisfied
  2. Validate that `eh.hasErrors` is satisfied
  3. Validate that `errors.length` is satisfied
  4. Validate that `errors[0].hint not equals null && (strstr(errors[0].hint, "Incompatible assignment: '*const [5]u8' to 'i32'"` is satisfied
  ```

### `test_TypeChecker_VarDecl_Invalid_Widening`
- **Implementation Source**: `tests/type_checker_var_decl.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: i64 = 42;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `root not equals null` is satisfied
  2. Ensure that `eh.hasErrors` is false
  ```

### `test_TypeChecker_VarDecl_Multiple_Errors`
- **Implementation Source**: `tests/type_checker_var_decl.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: i32 = \
  ```
  ```zig
; const y: f32 = 12;
  ```
  ```zig
Incompatible assignment: '*const [5]u8' to 'i32'
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `root not equals null` is satisfied
  2. Validate that `eh.hasErrors` is satisfied
  3. Validate that `errors.length` is satisfied
  4. Validate that `errors[0].hint not equals null && (strstr(errors[0].hint, "Incompatible assignment: '*const [5]u8' to 'i32'"` is satisfied
  ```

### `test_ReturnTypeValidation_Valid`
- **Implementation Source**: `tests/return_type_validation_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn test_fn() -> i32 { return 10; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `context.getCompilationUnit` is false
  ```

### `test_ReturnTypeValidation_Invalid`
- **Implementation Source**: `tests/return_type_validation_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn test_fn() -> i32 { return true; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `context.getCompilationUnit` is satisfied
  ```

### `test_TypeCheckerFnDecl_ValidSimpleParams`
- **Implementation Source**: `tests/type_checker_fn_decl.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn add(a: i32, b: i32) -> i32 { return a + b; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `root not equals null` is satisfied
  2. Ensure that `context.getCompilationUnit` is false
  ```

### `test_TypeCheckerFnDecl_InvalidParamType`
- **Implementation Source**: `tests/type_checker_fn_decl.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn sub(a: NotARealType, b: i32) -> i32 { return a - b; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `root not equals null` is satisfied
  2. Validate that `context.getCompilationUnit` is satisfied
  3. Assert that `err.code` matches `ERR_UNDECLARED_TYPE`
  ```

### `test_TypeCheckerVoidTests_ImplicitReturnInVoidFunction`
- **Implementation Source**: `tests/type_checker_void_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> void {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `comp_unit.getErrorHandler` is false
  ```

### `test_TypeCheckerVoidTests_ExplicitReturnInVoidFunction`
- **Implementation Source**: `tests/type_checker_void_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> void { return; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `comp_unit.getErrorHandler` is false
  ```

### `test_TypeCheckerVoidTests_ReturnValueInVoidFunction`
- **Implementation Source**: `tests/type_checker_void_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> void { return 123; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `error_handler.hasErrors` is satisfied
  2. Validate that `found_error` is satisfied
  ```

### `test_TypeCheckerVoidTests_MissingReturnValueInNonVoidFunction`
- **Implementation Source**: `tests/type_checker_void_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> i32 { return; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `error_handler.hasErrors` is satisfied
  2. Validate that `found_error` is satisfied
  ```

### `test_TypeCheckerVoidTests_ImplicitReturnInNonVoidFunction`
- **Implementation Source**: `tests/type_checker_void_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> i32 {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `error_handler.hasErrors` is satisfied
  2. Validate that `found_error` is satisfied
  ```

### `test_TypeCheckerVoidTests_AllPathsReturnInNonVoidFunction`
- **Implementation Source**: `tests/type_checker_void_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main(a: i32) -> i32 { const zero: i32 = 0; if (a > zero) { return 1; } else { return 0; } }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `comp_unit.getErrorHandler` is false
  ```

### `test_TypeChecker_AddressOf_RValueLiteral`
- **Implementation Source**: `tests/type_checker_address_of.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> i32 { var x: *i32 = &10; return 0; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_TypeChecker_AddressOf_RValueExpression`
- **Implementation Source**: `tests/type_checker_address_of.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> i32 { var x: i32; var y: i32; var z: *i32 = &(x + y); return 0; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_TypeChecker_Dereference_ValidPointer`
- **Implementation Source**: `tests/type_checker_pointers.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: i32 = 0; const p: *i32 = &x;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `result_type not equals null` is satisfied
  3. Assert that `kind of result_type` matches `kind of i32_type`
  ```

### `test_TypeChecker_Dereference_Invalid_NonPointer`
- **Implementation Source**: `tests/type_checker_pointers.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: i32 = 42;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `result_type equals null` is satisfied
  3. Validate that `comp_unit.getErrorHandler` is satisfied
  4. Assert that `comp_unit.getErrorHandler` matches `1`
  5. Assert that `err.code` matches `ERR_TYPE_MISMATCH`
  6. Validate that `err.hint not equals null && strstr(err.hint, "Cannot dereference a non-pointer type 'i32'"` is satisfied
  ```

### `test_TypeChecker_Dereference_VoidPointer`
- **Implementation Source**: `tests/type_checker_pointers.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const p: *void = null;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `result_type equals null` is satisfied
  3. Validate that `comp_unit.getErrorHandler` is satisfied
  4. Assert that `comp_unit.getErrorHandler` matches `1`
  5. Assert that `err.code` matches `ERR_TYPE_MISMATCH`
  6. Validate that `err.hint not equals null && strstr(err.hint, "Cannot dereference a void pointer"` is satisfied
  ```

### `test_TypeChecker_Dereference_NullLiteral`
- **Implementation Source**: `tests/type_checker_pointers.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
);
    TypeChecker type_checker(comp_unit);

    // Manually create a '*null' expression
    ASTNode* null_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(null_node, 0, sizeof(ASTNode));
    null_node->type = NODE_NULL_LITERAL;
    SourceLocation loc;
    loc.file_id = file_id;
    loc.line = 1;
    loc.column = 2;
    null_node->loc = loc;

    ASTNode* deref_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(deref_node, 0, sizeof(ASTNode));
    deref_node->type = NODE_UNARY_OP;
    deref_node->as.unary_op.op = TOKEN_STAR;
    deref_node->as.unary_op.operand = null_node;
    deref_node->loc = loc;

... (truncated)
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `comp_unit.getErrorHandler` is false
  2. Validate that `comp_unit.getErrorHandler` is satisfied
  3. Assert that `comp_unit.getErrorHandler` matches `1`
  4. Assert that `warn.code` matches `WARN_null_DEREFERENCE`
  5. Validate that `strcmp(warn.message, "Dereferencing null pointer may cause undefined behavior"` is satisfied
  ```

### `test_TypeChecker_Dereference_ZeroLiteral`
- **Implementation Source**: `tests/type_checker_pointers.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
);
    TypeChecker type_checker(comp_unit);

    // Manually create a '*0' expression
    ASTNode* zero_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(zero_node, 0, sizeof(ASTNode));
    zero_node->type = NODE_INTEGER_LITERAL;
    zero_node->as.integer_literal.value = 0;
    SourceLocation loc;
    loc.file_id = file_id;
    loc.line = 1;
    loc.column = 2;
    zero_node->loc = loc;

    ASTNode* deref_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(deref_node, 0, sizeof(ASTNode));
    deref_node->type = NODE_UNARY_OP;
    deref_node->as.unary_op.op = TOKEN_STAR;
    deref_node->as.unary_op.operand = zero_node;
    deref_node->loc = loc;
... (truncated)
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `comp_unit.getErrorHandler` is false
  2. Validate that `comp_unit.getErrorHandler` is satisfied
  3. Assert that `comp_unit.getErrorHandler` matches `1`
  4. Assert that `warn.code` matches `WARN_null_DEREFERENCE`
  5. Validate that `strcmp(warn.message, "Dereferencing null pointer may cause undefined behavior"` is satisfied
  ```

### `test_TypeChecker_Dereference_NestedPointer_ALLOW`
- **Implementation Source**: `tests/type_checker_pointers.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: i32 = 0; var p1: *i32 = &x; var p2: **i32 = &p1; var y: i32 = p2.*.*;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `unit.getErrorHandler` is false
  ```

### `test_TypeChecker_Dereference_ConstPointer`
- **Implementation Source**: `tests/type_checker_pointers.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
);
    Type* p_type = createPointerType(arena, i32_type, true); // is_const = true
    Symbol p_symbol = SymbolBuilder(arena)
        .withName(interner.intern(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `result_type not equals null` is satisfied
  2. Assert that `kind of result_type` matches `kind of i32_type`
  ```

### `test_TypeChecker_AddressOf_Valid_LValues`
- **Implementation Source**: `tests/type_checker_pointers.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `result1 not equals null` is satisfied
  2. Assert that `kind of result1` matches `TYPE_POINTER`
  3. Assert that `result1.as.pointer.base` matches `i32_type`
  4. Validate that `result2 not equals null` is satisfied
  5. Assert that `kind of result2` matches `TYPE_POINTER`
  6. Assert that `result2.as.pointer.base` matches `i32_type`
  7. Ensure that `comp_unit.getErrorHandler` is false
  ```

### `test_TypeCheckerPointerOps_AddressOf_ValidLValue`
- **Implementation Source**: `tests/type_checker_pointer_operations.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `result_type not equals null` is satisfied
  2. Assert that `TYPE_POINTER` matches `kind of result_type`
  3. Validate that `result_type.as.pointer.base equals get_g_type_i32` is satisfied
  4. Ensure that `comp_unit.getErrorHandler` is false
  ```

### `test_TypeCheckerPointerOps_Dereference_ValidPointer`
- **Implementation Source**: `tests/type_checker_pointer_operations.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `result_type not equals null` is satisfied
  2. Validate that `result_type equals get_g_type_i32` is satisfied
  3. Ensure that `comp_unit.getErrorHandler` is false
  ```

### `test_TypeCheckerPointerOps_Dereference_InvalidNonPointer`
- **Implementation Source**: `tests/type_checker_pointer_operations.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `result_type equals null` is satisfied
  2. Validate that `comp_unit.getErrorHandler` is satisfied
  3. Assert that `1` matches `length of errors`
  4. Assert that `ERR_TYPE_MISMATCH` matches `errors[0].code`
  ```

### `test_TypeChecker_PointerArithmetic_ValidCases_ExplicitTyping`
- **Implementation Source**: `tests/pointer_arithmetic_test.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() { var p: [*]i32; var i: usize; var res: [*]i32 = p + i; }
  ```
  ```zig
fn main() { var p: [*]i32; var i: usize; var res: [*]i32 = i + p; }
  ```
  ```zig
fn main() { var p: [*]i32; var i: usize; var res: [*]i32 = p - i; }
  ```
  ```zig
fn main() { var p1: [*]i32; var p2: [*]i32; var res: isize = p1 - p2; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `comp_unit.getErrorHandler` is false
  ```

### `test_TypeChecker_PointerArithmetic_InvalidCases_ExplicitTyping`
- **Implementation Source**: `tests/pointer_arithmetic_test.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() { var p1: *i32; var p2: *i32; var res: *i32 = p1 + p2; }
  ```
  ```zig
fn main() { var p: *i32; var i: usize; var res: *i32 = p * i; }
  ```
  ```zig
fn main() { var p: *i32; var i: usize; var res: *i32 = p / i; }
  ```
  ```zig
fn main() { var p: *i32; var i: usize; var res: *i32 = p % i; }
  ```
  ```zig
fn main() { var p1: [*]i32; var p2: [*]u8; var res: isize = p1 - p2; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `comp_unit.getErrorHandler` is satisfied
  2. Assert that `ERR_POINTER_ARITHMETIC_INVALID_OPERATOR` matches `comp_unit.getErrorHandler().getErrors()[0].code`
  3. Assert that `ERR_POINTER_SUBTRACTION_INCOMPATIBLE` matches `comp_unit.getErrorHandler().getErrors()[0].code`
  ```

### `test_TypeCheckerVoidTests_PointerAddition`
- **Implementation Source**: `tests/type_checker_void_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `error_handler.hasErrors` is satisfied
  2. Validate that `found_error` is satisfied
  ```

### `test_TypeCheckerPointerOps_Arithmetic_PointerInteger`
- **Implementation Source**: `tests/type_checker_pointer_operations.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `result equals ptr_type` is satisfied
  2. Ensure that `comp_unit.getErrorHandler` is false
  ```

### `test_TypeCheckerPointerOps_Arithmetic_PointerPointer`
- **Implementation Source**: `tests/type_checker_pointer_operations.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `result equals resolvePrimitiveTypeName("isize"` is satisfied
  2. Ensure that `comp_unit.getErrorHandler` is false
  ```

### `test_TypeCheckerPointerOps_Arithmetic_InvalidOperations`
- **Implementation Source**: `tests/type_checker_pointer_operations.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `comp_unit.getErrorHandler` is satisfied
  2. Assert that `ERR_POINTER_ARITHMETIC_INVALID_OPERATOR` matches `comp_unit.getErrorHandler().getErrors()[0].code`
  3. Assert that `ERR_POINTER_SUBTRACTION_INCOMPATIBLE` matches `comp_unit.getErrorHandler().getErrors()[0].code`
  ```

### `test_TypeCheckerBinaryOps_PointerArithmetic`
- **Implementation Source**: `tests/type_checker_binary_ops.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn test_fn() {
    var p_i32: [*]i32;
    var p_const_i32: [*]const i32;
    var p2_i32: [*]i32;
    var p_u8: [*]u8;
    var p_void: *void;
    var i: usize = 0u;
    %s;
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `result_type not equals null` is satisfied
  2. Assert that `TYPE_POINTER` matches `kind of result_type`
  3. Assert that `TYPE_I32` matches `result_type.as.pointer.kind of base`
  4. Ensure that `result_type.as.pointer.is_const` is false
  5. Assert that `TYPE_ISIZE` matches `kind of result_type`
  6. Validate that `check_binary_op_error(base_source, "p_void + i", ERR_INVALID_VOID_POINTER_ARITHMETIC, arena` is satisfied
  7. Validate that `check_binary_op_error(base_source, "i + p_void", ERR_INVALID_VOID_POINTER_ARITHMETIC, arena` is satisfied
  8. Validate that `check_binary_op_error(base_source, "p_void - i", ERR_INVALID_VOID_POINTER_ARITHMETIC, arena` is satisfied
  9. Validate that `check_binary_op_error(base_source, "p_i32 - p_u8", ERR_POINTER_SUBTRACTION_INCOMPATIBLE, arena` is satisfied
  10. Validate that `check_binary_op_error(base_source, "p_i32 + p2_i32", ERR_POINTER_ARITHMETIC_INVALID_OPERATOR, arena` is satisfied
  ```

### `test_TypeCheckerBinaryOps_NumericArithmetic`
- **Implementation Source**: `tests/type_checker_binary_ops.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn test_fn() {
    var a_i32: i32;
    var b_i32: i32;
    var a_i16: i16;
    var a_f64: f64;
    var b_f64: f64;
    %s;
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `result_type not equals null` is satisfied
  2. Assert that `TYPE_I32` matches `kind of result_type`
  3. Assert that `TYPE_F64` matches `kind of result_type`
  4. Validate that `check_binary_op_error(base_source, "a_i32 + a_i16", ERR_TYPE_MISMATCH, arena` is satisfied
  5. Validate that `check_binary_op_error(base_source, "a_i32 / a_f64", ERR_TYPE_MISMATCH, arena` is satisfied
  ```

### `test_TypeCheckerBinaryOps_Comparison`
- **Implementation Source**: `tests/type_checker_binary_ops.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn test_fn() {
    var a_i32: i32;
    var b_i32: i32;
    var a_i16: i16;
    var p_i32: *i32;
    var p_u8: *u8;
    var a_bool: bool;
    var b_bool: bool;
    %s;
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `result_type not equals null` is satisfied
  2. Assert that `TYPE_BOOL` matches `kind of result_type`
  3. Validate that `check_binary_op_error(base_source, "a_i32 > a_i16", ERR_TYPE_MISMATCH, arena` is satisfied
  4. Validate that `check_binary_op_error(base_source, "p_i32 equals p_u8", ERR_TYPE_MISMATCH, arena` is satisfied
  5. Validate that `check_binary_op_error(base_source, "a_i32 <= a_bool", ERR_TYPE_MISMATCH, arena` is satisfied
  ```

### `test_TypeCheckerBinaryOps_Bitwise`
- **Implementation Source**: `tests/type_checker_binary_ops.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn test_fn() {
    var a_u32: u32 = 3000000000u;
    var b_u32: u32 = 3000000001u;
    var a_i32: i32 = 3;
    var a_bool: bool = true;
    %s;
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `result_type not equals null` is satisfied
  2. Assert that `TYPE_U32` matches `kind of result_type`
  3. Validate that `check_binary_op_error(base_source, "a_u32 | a_i32", ERR_TYPE_MISMATCH, arena` is satisfied
  4. Validate that `check_binary_op_error(base_source, "a_u32 ^ a_bool", ERR_TYPE_MISMATCH, arena` is satisfied
  ```

### `test_TypeCheckerBinaryOps_Logical`
- **Implementation Source**: `tests/type_checker_binary_ops.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn test_fn() {
    var a_bool: bool = true;
    var b_bool: bool = false;
    var a_i32: i32 = 1;
    %s;
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `result_type not equals null` is satisfied
  2. Assert that `TYPE_BOOL` matches `kind of result_type`
  3. Validate that `check_binary_op_error(base_source, "a_bool and a_i32", ERR_TYPE_MISMATCH, arena` is satisfied
  4. Validate that `check_binary_op_error(base_source, "a_i32 or b_bool", ERR_TYPE_MISMATCH, arena` is satisfied
  ```

### `test_TypeChecker_Bool_ComparisonOps`
- **Implementation Source**: `tests/type_checker_bool_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_TypeChecker_Bool_ComparisonOps and validate component behavior
  ```

### `test_TypeChecker_Bool_LogicalOps`
- **Implementation Source**: `tests/type_checker_bool_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_TypeChecker_Bool_LogicalOps and validate component behavior
  ```

### `test_TypeCheckerControlFlow_IfStatementWithBooleanCondition`
- **Implementation Source**: `tests/type_checker_control_flow.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> void { if (true) {} }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `typeCheckTest(source` is satisfied
  ```

### `test_TypeCheckerControlFlow_IfStatementWithIntegerCondition`
- **Implementation Source**: `tests/type_checker_control_flow.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> void { if (1) {} }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `typeCheckTest(source` is satisfied
  ```

### `test_TypeCheckerControlFlow_IfStatementWithPointerCondition`
- **Implementation Source**: `tests/type_checker_control_flow.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> void { var x: i32 = 0; if (&x) {} }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `typeCheckTest(source` is satisfied
  ```

### `test_TypeCheckerControlFlow_IfStatementWithFloatCondition`
- **Implementation Source**: `tests/type_checker_control_flow.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> void { if (1.0) {} }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `typeCheckTest(source` is false
  ```

### `test_TypeCheckerControlFlow_IfStatementWithVoidCondition`
- **Implementation Source**: `tests/type_checker_control_flow.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {} fn main() -> void { if (my_func()) {} }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `typeCheckTest(source` is false
  ```

### `test_TypeCheckerControlFlow_WhileStatementWithBooleanCondition`
- **Implementation Source**: `tests/type_checker_control_flow.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> void { while (true) {} }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `typeCheckTest(source` is satisfied
  ```

### `test_TypeCheckerControlFlow_WhileStatementWithIntegerCondition`
- **Implementation Source**: `tests/type_checker_control_flow.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> void { while (1) {} }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `typeCheckTest(source` is satisfied
  ```

### `test_TypeCheckerControlFlow_WhileStatementWithPointerCondition`
- **Implementation Source**: `tests/type_checker_control_flow.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> void { var x: i32 = 0; while (&x) {} }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `typeCheckTest(source` is satisfied
  ```

### `test_TypeCheckerControlFlow_WhileStatementWithFloatCondition`
- **Implementation Source**: `tests/type_checker_control_flow.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> void { while (1.0) {} }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `typeCheckTest(source` is false
  ```

### `test_TypeCheckerControlFlow_WhileStatementWithVoidCondition`
- **Implementation Source**: `tests/type_checker_control_flow.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {} fn main() -> void { while (my_func()) {} }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `typeCheckTest(source` is false
  ```

### `test_TypeChecker_C89_StructFieldValidation_Slice`
- **Implementation Source**: `tests/type_checker_c89_compat_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { field: []u8 };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Ensure that `expect_type_checker_abort(source` is false
  ```

### `test_TypeChecker_C89_UnionFieldValidation_MultiLevelPointer`
- **Implementation Source**: `tests/type_checker_c89_compat_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const U = union { field: * * i32 };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `unit.getErrorHandler` is false
  ```

### `test_TypeChecker_C89_StructFieldValidation_ValidArray`
- **Implementation Source**: `tests/type_checker_c89_compat_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { field: [8]u8 };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `unit.getErrorHandler` is false
  ```

### `test_TypeChecker_C89_UnionFieldValidation_ValidFields`
- **Implementation Source**: `tests/type_checker_c89_compat_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const U = struct { a: i32, b: *u8, c: [4]f64 };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `unit.getErrorHandler` is false
  ```

### `test_TypeCheckerEnumTests_SignedIntegerOverflow`
- **Implementation Source**: `tests/type_checker_enum_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: enum(i8) { A = 128 };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_TypeCheckerEnumTests_SignedIntegerUnderflow`
- **Implementation Source**: `tests/type_checker_enum_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: enum(i8) { A = -129 };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_TypeCheckerEnumTests_UnsignedIntegerOverflow`
- **Implementation Source**: `tests/type_checker_enum_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: enum(u8) { A = 256 };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_TypeCheckerEnumTests_NegativeValueInUnsignedEnum`
- **Implementation Source**: `tests/type_checker_enum_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: enum(u8) { A = -1 };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_TypeCheckerEnumTests_AutoIncrementOverflow`
- **Implementation Source**: `tests/type_checker_enum_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: enum(u8) { Y = 254, Z, Over };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_TypeCheckerEnumTests_AutoIncrementSignedOverflow`
- **Implementation Source**: `tests/type_checker_enum_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: enum(i8) { Y = 126, Z, Over };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_TypeCheckerEnumTests_ValidValues`
- **Implementation Source**: `tests/type_checker_enum_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: enum(i8) {    Min = -128,    Max = 127};const y: enum(u8) {    Min = 0,    Max = 255};
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Ensure that `expect_type_checker_abort(source` is false
  ```

### `test_TypeChecker_ArrayAccessInBoundsWithNamedConstant`
- **Implementation Source**: `tests/type_checker_array_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const A_CONST: i32 = 15; var my_array: [16]i32; var x: i32 = my_array[A_CONST];
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Ensure that `expect_type_checker_abort(source` is false
  ```

### `test_TypeChecker_RejectSlice`
- **Implementation Source**: `tests/type_checker_array_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var my_slice: []u8 = undefined;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Ensure that `expect_type_checker_abort(source` is false
  ```

### `test_TypeChecker_ArrayAccessInBounds`
- **Implementation Source**: `tests/type_checker_array_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var my_array: [16]i32; var x: i32 = my_array[15];
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Ensure that `expect_type_checker_abort(source` is false
  ```

### `test_TypeChecker_ArrayAccessOutOfBoundsPositive`
- **Implementation Source**: `tests/type_checker_array_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var my_array: [16]i32; var x: i32 = my_array[16];
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_TypeChecker_ArrayAccessOutOfBoundsNegative`
- **Implementation Source**: `tests/type_checker_array_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var my_array: [16]i32; var x: i32 = my_array[-1];
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_TypeChecker_ArrayAccessOutOfBoundsExpression`
- **Implementation Source**: `tests/type_checker_array_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var my_array: [16]i32; var x: i32 = my_array[10 + 6];
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_TypeChecker_ArrayAccessWithVariable`
- **Implementation Source**: `tests/type_checker_array_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var my_array: [16]i32; var i: i32 = 10; var x: i32 = my_array[i];
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Ensure that `expect_type_checker_abort(source` is false
  ```

### `test_TypeChecker_IndexingNonArray`
- **Implementation Source**: `tests/type_checker_array_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var my_var: i32; var x: i32 = my_var[0];
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_TypeChecker_ArrayAccessWithNamedConstant`
- **Implementation Source**: `tests/type_checker_array_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const A_CONST: i32 = 16; var my_array: [16]i32; var x: i32 = my_array[A_CONST];
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_Assignment_IncompatiblePointers_Invalid`
- **Implementation Source**: `tests/test_assignment_compatibility.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `checker.IsTypeAssignableTo(ptr_i32, ptr_f32, loc` is false
  2. Validate that `eh.hasErrors` is satisfied
  3. Validate that `eh.getErrors` is satisfied
  ```

### `test_Assignment_ConstPointerToPointer_Invalid`
- **Implementation Source**: `tests/test_assignment_compatibility.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
Cannot assign const pointer to non-const
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `checker.IsTypeAssignableTo(ptr_i32_const, ptr_i32_mut, loc` is false
  2. Validate that `eh.hasErrors` is satisfied
  3. Validate that `eh.getErrors` is satisfied
  ```

### `test_Assignment_PointerToConstPointer_Valid`
- **Implementation Source**: `tests/test_assignment_compatibility.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
), false);
    Type* ptr_i32_const = createPointerType(arena, resolvePrimitiveTypeName(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `checker.IsTypeAssignableTo(ptr_i32_mut, ptr_i32_const, loc` is satisfied
  2. Ensure that `unit.getErrorHandler` is false
  ```

### `test_Assignment_VoidPointerToPointer_Valid`
- **Implementation Source**: `tests/test_assignment_compatibility.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `checker.IsTypeAssignableTo(ptr_void_type, ptr_i32_type, loc` is satisfied
  2. Ensure that `unit.getErrorHandler` is false
  ```

### `test_Assignment_PointerToVoidPointer_Valid`
- **Implementation Source**: `tests/test_assignment_compatibility.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `checker.IsTypeAssignableTo(ptr_i32_type, ptr_void_type, loc` is satisfied
  2. Ensure that `unit.getErrorHandler` is false
  ```

### `test_Assignment_PointerExactMatch_Valid`
- **Implementation Source**: `tests/test_assignment_compatibility.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `checker.IsTypeAssignableTo(ptr_i32_type, ptr_i32_type, loc` is satisfied
  2. Ensure that `unit.getErrorHandler` is false
  ```

### `test_Assignment_NullToPointer_Valid`
- **Implementation Source**: `tests/test_assignment_compatibility.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `checker.IsTypeAssignableTo(null_type, ptr_i32_type, loc` is satisfied
  2. Ensure that `unit.getErrorHandler` is false
  ```

### `test_Assignment_NumericWidening_Fails`
- **Implementation Source**: `tests/test_assignment_compatibility.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `checker.IsTypeAssignableTo(i32_type, i64_type, loc` is false
  2. Validate that `eh.hasErrors` is satisfied
  3. Validate that `eh.getErrors` is satisfied
  ```

### `test_Assignment_ExactNumericMatch`
- **Implementation Source**: `tests/test_assignment_compatibility.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `checker.IsTypeAssignableTo(i32_type, i32_type, loc` is satisfied
  2. Ensure that `unit.getErrorHandler` is false
  ```

### `test_TypeChecker_RejectNonConstantArraySize`
- **Implementation Source**: `tests/type_checker_array_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: i32 = 8; var my_array: [x]u8;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_TypeChecker_AcceptsValidArrayDeclaration`
- **Implementation Source**: `tests/type_checker_array_tests.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
var my_array: [16]i32;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_BLOCK_STMT` matches `ast.type`
  2. Assert that `1` matches `ast.as.block_stmt.statements.length`
  3. Assert that `NODE_VAR_DECL` matches `var_decl_node.type`
  4. Ensure that `comp_unit.getErrorHandler` is false
  5. Validate that `sym not equals null` is satisfied
  6. Validate that `sym.symbol_type not equals null` is satisfied
  7. Assert that `TYPE_ARRAY` matches `sym.kind of symbol_type`
  8. Assert that `16` matches `sym.symbol_type.as.array.size`
  9. Validate that `sym.symbol_type.as.array.element_type not equals null` is satisfied
  10. Assert that `TYPE_I32` matches `sym.symbol_type.as.array.kind of element_type`
  ```

### `test_TypeCheckerVoidTests_DisallowVoidVariableDeclaration`
- **Implementation Source**: `tests/type_checker_void_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> void { var x: void = 0; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `error_handler.hasErrors` is satisfied
  2. Validate that `found_error` is satisfied
  ```

### `test_TypeCompatibility`
- **Implementation Source**: `tests/type_compatibility_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `checker.areTypesCompatible(i16_t, i8_t` is satisfied
  2. Validate that `checker.areTypesCompatible(i32_t, i16_t` is satisfied
  3. Validate that `checker.areTypesCompatible(i64_t, i32_t` is satisfied
  4. Validate that `checker.areTypesCompatible(f64_t, f32_t` is satisfied
  5. Validate that `checker.areTypesCompatible(i32_t, i32_t` is satisfied
  6. Ensure that `checker.areTypesCompatible(i16_t, i32_t` is false
  7. Ensure that `checker.areTypesCompatible(i32_t, u32_t` is false
  8. Ensure that `checker.areTypesCompatible(i32_t, f32_t` is false
  9. Validate that `checker.areTypesCompatible(ptr_i32_mut, ptr_i32_mut` is satisfied
  10. Validate that `checker.areTypesCompatible(ptr_i32_const, ptr_i32_mut` is satisfied
  11. Ensure that `checker.areTypesCompatible(ptr_i32_mut, ptr_i32_const` is false
  12. Ensure that `checker.areTypesCompatible(ptr_i32_mut, ptr_u32_mut` is false
  ```

### `test_TypeToString_Reentrancy`
- **Implementation Source**: `tests/type_to_string_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
Type 1: *i32, Type 2: *const i64
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `strcmp(final_buffer, expected` is satisfied
  ```

### `test_TypeCheckerC89Compat_AllowFunctionWithManyArgs`
- **Implementation Source**: `tests/type_checker_c89_compat_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn five_args(a: i32, b: i32, c: i32, d: i32, e: i32) void {}
fn main() void {
    five_args(1, 2, 3, 4, 5);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_TypeChecker_Call_WrongArgumentCount`
- **Implementation Source**: `tests/type_checker_c89_compat_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn five_args(a: i32, b: i32, c: i32, d: i32, e: i32) void {}
fn main() void {
    five_args(1, 2, 3, 4, 5);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_TypeChecker_Call_IncompatibleArgumentType`
- **Implementation Source**: `tests/type_checker_c89_compat_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn five_args(a: i32, b: i32, c: i32, d: i32, e: i32) void {}
fn main() void {
    five_args(1, 2, 3, 4, 5);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_TypeCheckerC89Compat_FloatWidening_Fails`
- **Implementation Source**: `tests/type_checker_float_c89_compat_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn test_fn(x: f32) -> void {
    var y: f64 = x;
}

  ```
  ```zig
fn test_fn(x: f64) -> void {
    var y: f32 = x;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `eh.hasErrors` is satisfied
  2. Assert that `1` matches `length of errors`
  3. Validate that `errors[0].hint not equals null && strstr(errors[0].hint, "C89 assignment requires identical types: 'f32' to 'f64'"` is satisfied
  4. Validate that `errors[0].hint not equals null && strstr(errors[0].hint, "C89 assignment requires identical types: 'f64' to 'f32'"` is satisfied
  ```

### `test_C89TypeMapping_Validation`
- **Implementation Source**: `tests/c89_type_mapping_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
);
    const size_t map_size = sizeof(c89_type_map) / sizeof(c89_type_map[0]);
    for (size_t i = 0; i < map_size; ++i) {
        printf(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `is_c89_compatible(get_g_type_void` is satisfied
  2. Validate that `is_c89_compatible(get_g_type_bool` is satisfied
  3. Validate that `is_c89_compatible(get_g_type_i8` is satisfied
  4. Validate that `is_c89_compatible(get_g_type_i16` is satisfied
  5. Validate that `is_c89_compatible(get_g_type_i32` is satisfied
  6. Validate that `is_c89_compatible(get_g_type_i64` is satisfied
  7. Validate that `is_c89_compatible(get_g_type_u8` is satisfied
  8. Validate that `is_c89_compatible(get_g_type_u16` is satisfied
  9. Validate that `is_c89_compatible(get_g_type_u32` is satisfied
  10. Validate that `is_c89_compatible(get_g_type_u64` is satisfied
  11. Validate that `is_c89_compatible(get_g_type_f32` is satisfied
  12. Validate that `is_c89_compatible(get_g_type_f64` is satisfied
  13. Validate that `is_c89_compatible(ptr_to_i32` is satisfied
  14. Validate that `is_c89_compatible(const_ptr_to_u8` is satisfied
  15. Validate that `is_c89_compatible(ptr_to_void` is satisfied
  16. Ensure that `is_c89_compatible(null` is false
  17. Validate that `is_c89_compatible(get_g_type_isize` is satisfied
  18. Validate that `is_c89_compatible(get_g_type_usize` is satisfied
  19. Ensure that `is_c89_compatible(&func_type` is false
  20. ... (additional verification assertions)
  ```

### `test_C89Compat_FunctionTypeValidation`
- **Implementation Source**: `tests/c89_type_compat_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `is_c89_compatible(func_type` is satisfied
  2. Ensure that `is_c89_compatible(outer_func_type` is false
  ```

### `test_TypeChecker_Bool_Literals`
- **Implementation Source**: `tests/type_checker_bool_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `true_type not equals null` is satisfied
  2. Assert that `TYPE_BOOL` matches `kind of true_type`
  3. Validate that `false_type not equals null` is satisfied
  4. Assert that `TYPE_BOOL` matches `kind of false_type`
  ```

### `test_TypeChecker_CompoundAssignment_Valid`
- **Implementation Source**: `tests/test_type_checker_compound_assignment.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() void {  var x: i32 = 10;  x += 5;  x -= 2;  x *= 3;  x /= 4;  x %= 3;}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_TypeChecker_CompoundAssignment_Valid and validate component behavior
  ```

### `test_TypeChecker_CompoundAssignment_InvalidLValue`
- **Implementation Source**: `tests/test_type_checker_compound_assignment.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() void {  const x: i32 = 10;  x += 5;}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  ```

### `test_TypeChecker_CompoundAssignment_Bitwise`
- **Implementation Source**: `tests/test_type_checker_compound_assignment.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() void {
  ```
  ```zig
var x: u32 = 240u;
  ```
  ```zig
;
    if (!run_type_checker_test_successfully(source)) {
        printf(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_TypeChecker_CompoundAssignment_Bitwise and validate component behavior
  ```

### `test_TypeChecker_CompoundAssignment_PointerArithmetic`
- **Implementation Source**: `tests/test_type_checker_compound_assignment.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() void {  var x: [10]i32;  var p: [*]i32 = @ptrCast([*]i32, &x[0]);  p += 1u;  p -= 1u;}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_TypeChecker_CompoundAssignment_PointerArithmetic and validate component behavior
  ```

### `test_TypeChecker_CompoundAssignment_InvalidTypes`
- **Implementation Source**: `tests/test_type_checker_compound_assignment.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() void {  var b: bool = true;  b += 1;}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `unit.getErrorHandler` is satisfied
  ```

### `test_DoubleFreeAnalyzer_CompoundAssignment`
- **Implementation Source**: `tests/test_type_checker_compound_assignment.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_ptr_test() void {
    var p: [*]u8 = @ptrCast([*]u8, arena_alloc_default(100u));
    p += 10u;
    arena_free(@ptrCast(*u8, p));
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `found_leak` is satisfied
  ```
