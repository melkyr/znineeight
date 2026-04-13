# Batch 3 Details: Semantic Analysis (Type Checking)

## Focus
Semantic Analysis (Type Checking)

This batch contains 115 test cases focusing on semantic analysis (type checking).

## Test Case Details
### `test_TypeChecker_IntegerLiteralInference`
- **Primary File**: `tests/type_checker_literals.cpp`
- **Verification Points**: 18 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_IntegerLiteralInference specific test data structures
  4. Verify that the 18 semantic properties match expected values
  ```

### `test_TypeChecker_FloatLiteralInference`
- **Primary File**: `tests/type_checker_literals.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_FloatLiteralInference specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeChecker_CharLiteralInference`
- **Primary File**: `tests/type_checker_literals.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_CharLiteralInference specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeChecker_StringLiteralInference`
- **Primary File**: `tests/type_checker_literals.cpp`
- **Verification Points**: 5 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_StringLiteralInference specific test data structures
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_TypeCheckerStringLiteralType`
- **Primary File**: `tests/type_checker_tests.cpp`
- **Verification Points**: 6 assertions
- **Operations**: Syntactic Parsing
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void { \
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_TypeCheckerIntegerLiteralType`
- **Primary File**: `tests/type_checker_tests.cpp`
- **Verification Points**: 4 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeCheckerIntegerLiteralType specific test data structures
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_TypeChecker_C89IntegerCompatibility`
- **Primary File**: `tests/type_checker_tests.cpp`
- **Verification Points**: 6 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_C89IntegerCompatibility specific test data structures
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_TypeResolution_ValidPrimitives`
- **Primary File**: `tests/type_system_tests.cpp`
- **Verification Points**: 12 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeResolution_ValidPrimitives specific test data structures
  4. Verify that the 12 semantic properties match expected values
  ```

### `test_TypeResolution_InvalidOrUnsupported`
- **Primary File**: `tests/type_system_tests.cpp`
- **Verification Points**: 3 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeResolution_InvalidOrUnsupported specific test data structures
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_TypeResolution_AllPrimitives`
- **Primary File**: `tests/type_system_tests.cpp`
- **Verification Points**: 14 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeResolution_AllPrimitives specific test data structures
  4. Verify that the 14 semantic properties match expected values
  ```

### `test_TypeChecker_BoolLiteral`
- **Primary File**: `tests/type_checker_expressions.cpp`
- **Verification Points**: 4 assertions
- **Operations**: Syntactic Parsing
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_BoolLiteral specific test data structures
  3. Execute Syntactic Parsing phase
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_TypeChecker_IntegerLiteral`
- **Primary File**: `tests/type_checker_expressions.cpp`
- **Verification Points**: 4 assertions
- **Operations**: Syntactic Parsing
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_IntegerLiteral specific test data structures
  3. Execute Syntactic Parsing phase
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_TypeChecker_CharLiteral`
- **Primary File**: `tests/type_checker_expressions.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_CharLiteral specific test data structures
  3. Execute Syntactic Parsing phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeChecker_StringLiteral`
- **Primary File**: `tests/type_checker_expressions.cpp`
- **Verification Points**: 5 assertions
- **Operations**: Syntactic Parsing
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_StringLiteral specific test data structures
  3. Execute Syntactic Parsing phase
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_TypeChecker_Identifier`
- **Primary File**: `tests/type_checker_expressions.cpp`
- **Verification Points**: 6 assertions
- **Operations**: Syntactic Parsing
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_Identifier specific test data structures
  3. Execute Syntactic Parsing phase
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_TypeCheckerValidDeclarations`
- **Primary File**: `tests/type_checker_tests.cpp`
- **Verification Points**: 3 assertions
- **Test Input (Zig)**:
  ```zig
var x: i32 = 10;
  ```
  ```zig
var y: i64 = 3000000000;
  ```
  ```zig
var z: bool = true;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_TypeCheckerInvalidDeclarations`
- **Primary File**: `tests/type_checker_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking
- **Test Input (Zig)**:
  ```zig
var x: i32 = \
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerUndeclaredVariable`
- **Primary File**: `tests/type_checker_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking
- **Test Input (Zig)**:
  ```zig
var x: i32 = y;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_VarDecl_Valid_Simple`
- **Primary File**: `tests/type_checker_var_decl.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking
- **Test Input (Zig)**:
  ```zig
const x: i32 = 42;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeChecker_VarDecl_Invalid_Mismatch`
- **Primary File**: `tests/type_checker_var_decl.cpp`
- **Verification Points**: 5 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking
- **Test Input (Zig)**:
  ```zig
const x: i32 = \
  ```
  ```zig
Incompatible assignment: '*const [5]u8' to 'i32'
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_TypeChecker_VarDecl_Invalid_Widening`
- **Primary File**: `tests/type_checker_var_decl.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking
- **Test Input (Zig)**:
  ```zig
const x: i64 = 42;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeChecker_VarDecl_Multiple_Errors`
- **Primary File**: `tests/type_checker_var_decl.cpp`
- **Verification Points**: 5 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking
- **Test Input (Zig)**:
  ```zig
const x: i32 = \
  ```
  ```zig
; const y: f32 = 12;
  ```
  ```zig
Incompatible assignment: '*const [5]u8' to 'i32'
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_ReturnTypeValidation_Valid`
- **Primary File**: `tests/return_type_validation_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking
- **Test Input (Zig)**:
  ```zig
fn test_fn() -> i32 { return 10; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_ReturnTypeValidation_Invalid`
- **Primary File**: `tests/return_type_validation_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking
- **Test Input (Zig)**:
  ```zig
fn test_fn() -> i32 { return true; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerFnDecl_ValidSimpleParams`
- **Primary File**: `tests/type_checker_fn_decl.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking
- **Test Input (Zig)**:
  ```zig
fn add(a: i32, b: i32) -> i32 { return a + b; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeCheckerFnDecl_InvalidParamType`
- **Primary File**: `tests/type_checker_fn_decl.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking
- **Test Input (Zig)**:
  ```zig
fn sub(a: NotARealType, b: i32) -> i32 { return a - b; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_TypeCheckerVoidTests_ImplicitReturnInVoidFunction`
- **Primary File**: `tests/type_checker_void_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn main() -> void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerVoidTests_ExplicitReturnInVoidFunction`
- **Primary File**: `tests/type_checker_void_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn main() -> void { return; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerVoidTests_ReturnValueInVoidFunction`
- **Primary File**: `tests/type_checker_void_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn main() -> void { return 123; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeCheckerVoidTests_MissingReturnValueInNonVoidFunction`
- **Primary File**: `tests/type_checker_void_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn main() -> i32 { return; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeCheckerVoidTests_ImplicitReturnInNonVoidFunction`
- **Primary File**: `tests/type_checker_void_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn main() -> i32 {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeCheckerVoidTests_AllPathsReturnInNonVoidFunction`
- **Primary File**: `tests/type_checker_void_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn main(a: i32) -> i32 { const zero: i32 = 0; if (a > zero) { return 1; } else { return 0; } }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_AddressOf_RValueLiteral`
- **Primary File**: `tests/type_checker_address_of.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn main() -> i32 { var x: *i32 = &10; return 0; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_AddressOf_RValueExpression`
- **Primary File**: `tests/type_checker_address_of.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn main() -> i32 { var x: i32; var y: i32; var z: *i32 = &(x + y); return 0; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_Dereference_ValidPointer`
- **Primary File**: `tests/type_checker_pointers.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Syntactic Parsing, Source Loading
- **Test Input (Zig)**:
  ```zig
const x: i32 = 0; const p: *i32 = &x;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Source Loading phase
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_TypeChecker_Dereference_Invalid_NonPointer`
- **Primary File**: `tests/type_checker_pointers.cpp`
- **Verification Points**: 7 assertions
- **Operations**: Syntactic Parsing, Source Loading
- **Test Input (Zig)**:
  ```zig
const x: i32 = 42;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Source Loading phase
  4. Verify that the 7 semantic properties match expected values
  ```

### `test_TypeChecker_Dereference_VoidPointer`
- **Primary File**: `tests/type_checker_pointers.cpp`
- **Verification Points**: 7 assertions
- **Operations**: Syntactic Parsing, Source Loading
- **Test Input (Zig)**:
  ```zig
const p: *void = null;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Source Loading phase
  4. Verify that the 7 semantic properties match expected values
  ```

### `test_TypeChecker_Dereference_NullLiteral`
- **Primary File**: `tests/type_checker_pointers.cpp`
- **Verification Points**: 5 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_Dereference_NullLiteral specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_TypeChecker_Dereference_ZeroLiteral`
- **Primary File**: `tests/type_checker_pointers.cpp`
- **Verification Points**: 5 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_Dereference_ZeroLiteral specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_TypeChecker_Dereference_NestedPointer_ALLOW`
- **Primary File**: `tests/type_checker_pointers.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
var x: i32 = 0; var p1: *i32 = &x; var p2: **i32 = &p1; var y: i32 = p2.*.*;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_Dereference_ConstPointer`
- **Primary File**: `tests/type_checker_pointers.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_Dereference_ConstPointer specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeChecker_AddressOf_Valid_LValues`
- **Primary File**: `tests/type_checker_pointers.cpp`
- **Verification Points**: 7 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_AddressOf_Valid_LValues specific test data structures
  4. Verify that the 7 semantic properties match expected values
  ```

### `test_TypeCheckerPointerOps_AddressOf_ValidLValue`
- **Primary File**: `tests/type_checker_pointer_operations.cpp`
- **Verification Points**: 4 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeCheckerPointerOps_AddressOf_ValidLValue specific test data structures
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_TypeCheckerPointerOps_Dereference_ValidPointer`
- **Primary File**: `tests/type_checker_pointer_operations.cpp`
- **Verification Points**: 3 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeCheckerPointerOps_Dereference_ValidPointer specific test data structures
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_TypeCheckerPointerOps_Dereference_InvalidNonPointer`
- **Primary File**: `tests/type_checker_pointer_operations.cpp`
- **Verification Points**: 4 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeCheckerPointerOps_Dereference_InvalidNonPointer specific test data structures
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_TypeChecker_PointerArithmetic_ValidCases_ExplicitTyping`
- **Primary File**: `tests/pointer_arithmetic_test.cpp`
- **Verification Points**: 4 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
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
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_TypeChecker_PointerArithmetic_InvalidCases_ExplicitTyping`
- **Primary File**: `tests/pointer_arithmetic_test.cpp`
- **Verification Points**: 10 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
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
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 10 semantic properties match expected values
  ```

### `test_TypeCheckerVoidTests_PointerAddition`
- **Primary File**: `tests/type_checker_void_tests.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeCheckerVoidTests_PointerAddition specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeCheckerPointerOps_Arithmetic_PointerInteger`
- **Primary File**: `tests/type_checker_pointer_operations.cpp`
- **Verification Points**: 4 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeCheckerPointerOps_Arithmetic_PointerInteger specific test data structures
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_TypeCheckerPointerOps_Arithmetic_PointerPointer`
- **Primary File**: `tests/type_checker_pointer_operations.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeCheckerPointerOps_Arithmetic_PointerPointer specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeCheckerPointerOps_Arithmetic_InvalidOperations`
- **Primary File**: `tests/type_checker_pointer_operations.cpp`
- **Verification Points**: 5 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeCheckerPointerOps_Arithmetic_InvalidOperations specific test data structures
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_TypeCheckerBinaryOps_PointerArithmetic`
- **Primary File**: `tests/type_checker_binary_ops.cpp`
- **Verification Points**: 21 assertions
- **Test Input (Zig)**:
  ```zig
fn test_fn() {
  ```
  ```zig
var p_i32: [*]i32;
  ```
  ```zig
var p_const_i32: [*]const i32;
  ```
  ```zig
var p2_i32: [*]i32;
  ```
  ```zig
var p_u8: [*]u8;
  ```
  ```zig
var p_void: *void;
  ```
  ```zig
var i: usize = 0u;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 21 semantic properties match expected values
  ```

### `test_TypeCheckerBinaryOps_NumericArithmetic`
- **Primary File**: `tests/type_checker_binary_ops.cpp`
- **Verification Points**: 6 assertions
- **Test Input (Zig)**:
  ```zig
fn test_fn() {
  ```
  ```zig
var a_i32: i32;
  ```
  ```zig
var b_i32: i32;
  ```
  ```zig
var a_i16: i16;
  ```
  ```zig
var a_f64: f64;
  ```
  ```zig
var b_f64: f64;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_TypeCheckerBinaryOps_Comparison`
- **Primary File**: `tests/type_checker_binary_ops.cpp`
- **Verification Points**: 7 assertions
- **Test Input (Zig)**:
  ```zig
fn test_fn() {
  ```
  ```zig
var a_i32: i32;
  ```
  ```zig
var b_i32: i32;
  ```
  ```zig
var a_i16: i16;
  ```
  ```zig
var p_i32: *i32;
  ```
  ```zig
var p_u8: *u8;
  ```
  ```zig
var a_bool: bool;
  ```
  ```zig
var b_bool: bool;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 7 semantic properties match expected values
  ```

### `test_TypeCheckerBinaryOps_Bitwise`
- **Primary File**: `tests/type_checker_binary_ops.cpp`
- **Verification Points**: 6 assertions
- **Test Input (Zig)**:
  ```zig
fn test_fn() {
  ```
  ```zig
var a_u32: u32 = 3000000000u;
  ```
  ```zig
var b_u32: u32 = 3000000001u;
  ```
  ```zig
var a_i32: i32 = 3;
  ```
  ```zig
var a_bool: bool = true;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_TypeCheckerBinaryOps_Logical`
- **Primary File**: `tests/type_checker_binary_ops.cpp`
- **Verification Points**: 6 assertions
- **Test Input (Zig)**:
  ```zig
fn test_fn() {
  ```
  ```zig
var a_bool: bool = true;
  ```
  ```zig
var b_bool: bool = false;
  ```
  ```zig
var a_i32: i32 = 1;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_TypeChecker_Bool_ComparisonOps`
- **Primary File**: `tests/type_checker_bool_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_Bool_ComparisonOps specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_TypeChecker_Bool_LogicalOps`
- **Primary File**: `tests/type_checker_bool_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_Bool_LogicalOps specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_TypeCheckerControlFlow_IfStatementWithBooleanCondition`
- **Primary File**: `tests/type_checker_control_flow.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn main() -> void { if (true) {} }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerControlFlow_IfStatementWithIntegerCondition`
- **Primary File**: `tests/type_checker_control_flow.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn main() -> void { if (1) {} }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerControlFlow_IfStatementWithPointerCondition`
- **Primary File**: `tests/type_checker_control_flow.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn main() -> void { var x: i32 = 0; if (&x) {} }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerControlFlow_IfStatementWithFloatCondition`
- **Primary File**: `tests/type_checker_control_flow.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn main() -> void { if (1.0) {} }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerControlFlow_IfStatementWithVoidCondition`
- **Primary File**: `tests/type_checker_control_flow.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {} fn main() -> void { if (my_func()) {} }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerControlFlow_WhileStatementWithBooleanCondition`
- **Primary File**: `tests/type_checker_control_flow.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn main() -> void { while (true) {} }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerControlFlow_WhileStatementWithIntegerCondition`
- **Primary File**: `tests/type_checker_control_flow.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn main() -> void { while (1) {} }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerControlFlow_WhileStatementWithPointerCondition`
- **Primary File**: `tests/type_checker_control_flow.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn main() -> void { var x: i32 = 0; while (&x) {} }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerControlFlow_WhileStatementWithFloatCondition`
- **Primary File**: `tests/type_checker_control_flow.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn main() -> void { while (1.0) {} }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerControlFlow_WhileStatementWithVoidCondition`
- **Primary File**: `tests/type_checker_control_flow.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {} fn main() -> void { while (my_func()) {} }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_C89_StructFieldValidation_Slice`
- **Primary File**: `tests/type_checker_c89_compat_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
const S = struct { field: []u8 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_C89_UnionFieldValidation_MultiLevelPointer`
- **Primary File**: `tests/type_checker_c89_compat_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
const U = union { field: * * i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_C89_StructFieldValidation_ValidArray`
- **Primary File**: `tests/type_checker_c89_compat_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
const S = struct { field: [8]u8 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_C89_UnionFieldValidation_ValidFields`
- **Primary File**: `tests/type_checker_c89_compat_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
const U = struct { a: i32, b: *u8, c: [4]f64 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerEnumTests_SignedIntegerOverflow`
- **Primary File**: `tests/type_checker_enum_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
const x: enum(i8) { A = 128 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerEnumTests_SignedIntegerUnderflow`
- **Primary File**: `tests/type_checker_enum_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
const x: enum(i8) { A = -129 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerEnumTests_UnsignedIntegerOverflow`
- **Primary File**: `tests/type_checker_enum_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
const x: enum(u8) { A = 256 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerEnumTests_NegativeValueInUnsignedEnum`
- **Primary File**: `tests/type_checker_enum_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
const x: enum(u8) { A = -1 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerEnumTests_AutoIncrementOverflow`
- **Primary File**: `tests/type_checker_enum_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
const x: enum(u8) { Y = 254, Z, Over };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerEnumTests_AutoIncrementSignedOverflow`
- **Primary File**: `tests/type_checker_enum_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
const x: enum(i8) { Y = 126, Z, Over };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerEnumTests_ValidValues`
- **Primary File**: `tests/type_checker_enum_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
const x: enum(i8) {
  ```
  ```zig
const y: enum(u8) {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_ArrayAccessInBoundsWithNamedConstant`
- **Primary File**: `tests/type_checker_array_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
const A_CONST: i32 = 15; var my_array: [16]i32; var x: i32 = my_array[A_CONST];
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_RejectSlice`
- **Primary File**: `tests/type_checker_array_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var my_slice: []u8 = undefined;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_ArrayAccessInBounds`
- **Primary File**: `tests/type_checker_array_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var my_array: [16]i32; var x: i32 = my_array[15];
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_ArrayAccessOutOfBoundsPositive`
- **Primary File**: `tests/type_checker_array_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var my_array: [16]i32; var x: i32 = my_array[16];
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_ArrayAccessOutOfBoundsNegative`
- **Primary File**: `tests/type_checker_array_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var my_array: [16]i32; var x: i32 = my_array[-1];
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_ArrayAccessOutOfBoundsExpression`
- **Primary File**: `tests/type_checker_array_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var my_array: [16]i32; var x: i32 = my_array[10 + 6];
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_ArrayAccessWithVariable`
- **Primary File**: `tests/type_checker_array_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var my_array: [16]i32; var i: i32 = 10; var x: i32 = my_array[i];
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_IndexingNonArray`
- **Primary File**: `tests/type_checker_array_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var my_var: i32; var x: i32 = my_var[0];
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_ArrayAccessWithNamedConstant`
- **Primary File**: `tests/type_checker_array_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
const A_CONST: i32 = 16; var my_array: [16]i32; var x: i32 = my_array[A_CONST];
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_Assignment_IncompatiblePointers_Invalid`
- **Primary File**: `tests/test_assignment_compatibility.cpp`
- **Verification Points**: 4 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_Assignment_IncompatiblePointers_Invalid specific test data structures
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_Assignment_ConstPointerToPointer_Invalid`
- **Primary File**: `tests/test_assignment_compatibility.cpp`
- **Verification Points**: 4 assertions
- **Test Input (Zig)**:
  ```zig
Cannot assign const pointer to non-const
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_Assignment_PointerToConstPointer_Valid`
- **Primary File**: `tests/test_assignment_compatibility.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_Assignment_PointerToConstPointer_Valid specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Assignment_VoidPointerToPointer_Valid`
- **Primary File**: `tests/test_assignment_compatibility.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_Assignment_VoidPointerToPointer_Valid specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Assignment_PointerToVoidPointer_Valid`
- **Primary File**: `tests/test_assignment_compatibility.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_Assignment_PointerToVoidPointer_Valid specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Assignment_PointerExactMatch_Valid`
- **Primary File**: `tests/test_assignment_compatibility.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_Assignment_PointerExactMatch_Valid specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Assignment_NullToPointer_Valid`
- **Primary File**: `tests/test_assignment_compatibility.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_Assignment_NullToPointer_Valid specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Assignment_NumericWidening_Fails`
- **Primary File**: `tests/test_assignment_compatibility.cpp`
- **Verification Points**: 4 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_Assignment_NumericWidening_Fails specific test data structures
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_Assignment_ExactNumericMatch`
- **Primary File**: `tests/test_assignment_compatibility.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_Assignment_ExactNumericMatch specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeChecker_RejectNonConstantArraySize`
- **Primary File**: `tests/type_checker_array_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var x: i32 = 8; var my_array: [x]u8;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_AcceptsValidArrayDeclaration`
- **Primary File**: `tests/type_checker_array_tests.cpp`
- **Verification Points**: 10 assertions
- **Operations**: Syntactic Parsing, Source Loading
- **Test Input (Zig)**:
  ```zig
var my_array: [16]i32;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Source Loading phase
  4. Verify that the 10 semantic properties match expected values
  ```

### `test_TypeCheckerVoidTests_DisallowVoidVariableDeclaration`
- **Primary File**: `tests/type_checker_void_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn main() -> void { var x: void = 0; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeCompatibility`
- **Primary File**: `tests/type_compatibility_tests.cpp`
- **Verification Points**: 12 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeCompatibility specific test data structures
  4. Verify that the 12 semantic properties match expected values
  ```

### `test_TypeToString_Reentrancy`
- **Primary File**: `tests/type_to_string_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
Type 1: *i32, Type 2: *const i64
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerC89Compat_AllowFunctionWithManyArgs`
- **Primary File**: `tests/type_checker_c89_compat_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn five_args(a: i32, b: i32, c: i32, d: i32, e: i32) void {}
  ```
  ```zig
fn main() void {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_Call_WrongArgumentCount`
- **Primary File**: `tests/type_checker_c89_compat_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn five_args(a: i32, b: i32, c: i32, d: i32, e: i32) void {}
  ```
  ```zig
fn main() void {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_Call_IncompatibleArgumentType`
- **Primary File**: `tests/type_checker_c89_compat_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn five_args(a: i32, b: i32, c: i32, d: i32, e: i32) void {}
  ```
  ```zig
fn main() void {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeCheckerC89Compat_FloatWidening_Fails`
- **Primary File**: `tests/type_checker_float_c89_compat_tests.cpp`
- **Verification Points**: 8 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking
- **Test Input (Zig)**:
  ```zig
fn test_fn(x: f32) -> void {
  ```
  ```zig
fn test_fn(x: f64) -> void {
  ```
  ```zig
var y: f64 = x;
  ```
  ```zig
var y: f32 = x;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  4. Verify that the 8 semantic properties match expected values
  ```

### `test_C89TypeMapping_Validation`
- **Primary File**: `tests/c89_type_mapping_tests.cpp`
- **Verification Points**: 22 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_C89TypeMapping_Validation specific test data structures
  4. Verify that the 22 semantic properties match expected values
  ```

### `test_C89Compat_FunctionTypeValidation`
- **Primary File**: `tests/c89_type_compat_tests.cpp`
- **Verification Points**: 7 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_C89Compat_FunctionTypeValidation specific test data structures
  4. Verify that the 7 semantic properties match expected values
  ```

### `test_TypeChecker_Bool_Literals`
- **Primary File**: `tests/type_checker_bool_tests.cpp`
- **Verification Points**: 4 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_TypeChecker_Bool_Literals specific test data structures
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_TypeChecker_CompoundAssignment_Valid`
- **Primary File**: `tests/test_type_checker_compound_assignment.cpp`
- **Test Input (Zig)**:
  ```zig
fn main() void {
  ```
  ```zig
var x: i32 = 10;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_TypeChecker_CompoundAssignment_InvalidLValue`
- **Primary File**: `tests/test_type_checker_compound_assignment.cpp`
- **Test Input (Zig)**:
  ```zig
fn main() void {
  ```
  ```zig
const x: i32 = 10;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_TypeChecker_CompoundAssignment_Bitwise`
- **Primary File**: `tests/test_type_checker_compound_assignment.cpp`
- **Test Input (Zig)**:
  ```zig
fn main() void {
  ```
  ```zig
var x: u32 = 240u;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_TypeChecker_CompoundAssignment_PointerArithmetic`
- **Primary File**: `tests/test_type_checker_compound_assignment.cpp`
- **Test Input (Zig)**:
  ```zig
fn main() void {
  ```
  ```zig
var x: [10]i32;
  ```
  ```zig
var p: [*]i32 = @ptrCast([*]i32, &x[0]);
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_TypeChecker_CompoundAssignment_InvalidTypes`
- **Primary File**: `tests/test_type_checker_compound_assignment.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing, Source Loading
- **Test Input (Zig)**:
  ```zig
fn main() void {
  ```
  ```zig
var b: bool = true;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_DoubleFreeAnalyzer_CompoundAssignment`
- **Primary File**: `tests/test_type_checker_compound_assignment.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing, Static Analysis Pass, Source Loading
- **Test Input (Zig)**:
  ```zig
fn my_ptr_test() void {
  ```
  ```zig
var p: [*]u8 = @ptrCast([*]u8, arena_alloc_default(100u));
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Static Analysis Pass phase
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```
