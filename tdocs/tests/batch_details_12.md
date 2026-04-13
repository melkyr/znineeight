# Batch 12 Details: Semantic Analysis (Type Checking)

## Focus
Semantic Analysis (Type Checking)

This batch contains 89 test cases focusing on semantic analysis (type checking).

## Test Case Details
### `test_BootstrapTypes_Allowed_Primitives`
- **Primary File**: `tests/test_bootstrap_types.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var a: i8 = 0;
  ```
  ```zig
var b: i16 = 0;
  ```
  ```zig
var c: i32 = 0;
  ```
  ```zig
var d: i64 = 0;
  ```
  ```zig
var e: u8 = 0;
  ```
  ```zig
var f: u16 = 0;
  ```
  ```zig
var g: u32 = 0;
  ```
  ```zig
var h: u64 = 0;
  ```
  ```zig
var i: f32 = 0;
  ```
  ```zig
var j: f64 = 0.0;
  ```
  ```zig
var k: bool = true;
  ```
  ```zig
var l: isize = 0;
  ```
  ```zig
var m: usize = 0;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_BootstrapTypes_Allowed_Pointers`
- **Primary File**: `tests/test_bootstrap_types.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var a: *i32 = null;
  ```
  ```zig
var b: *const u8 = null;
  ```
  ```zig
var c: *void = null;
  ```
  ```zig
var d: **i32 = null;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_BootstrapTypes_Allowed_Arrays`
- **Primary File**: `tests/test_bootstrap_types.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var a: [10]i32;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_BootstrapTypes_Allowed_Structs`
- **Primary File**: `tests/test_bootstrap_types.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var s: S = S { .x = 1, .y = 2.0 };
  ```
  ```zig
const S = struct { x: i32, y: f64 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_BootstrapTypes_Allowed_Enums`
- **Primary File**: `tests/test_bootstrap_types.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var e: E = E.A;
  ```
  ```zig
const E = enum { A, B, C };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_BootstrapTypes_Rejected_Slice`
- **Primary File**: `tests/test_bootstrap_types.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
const arr: [5]u8 = undefined; var x: []u8 = arr[0..5];
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_BootstrapTypes_Rejected_ErrorUnion`
- **Primary File**: `tests/test_bootstrap_types.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var x: !i32 = 0;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_BootstrapTypes_Rejected_Optional`
- **Primary File**: `tests/test_bootstrap_types.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var x: ?i32 = null;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_BootstrapTypes_Allowed_FunctionPointer`
- **Primary File**: `tests/test_bootstrap_types.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn f(p: fn(i32) void) void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_BootstrapTypes_Allowed_ManyArgs`
- **Primary File**: `tests/test_bootstrap_types.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn f(a: i32, b: i32, c: i32, d: i32, e: i32) void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_BootstrapTypes_Rejected_VoidVariable`
- **Primary File**: `tests/test_bootstrap_types.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var x: void;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_MsvcCompatibility_Int64Mapping`
- **Primary File**: `tests/test_msvc_types.cpp`
- **Verification Points**: 4 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_MsvcCompatibility_Int64Mapping specific test data structures
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_MsvcCompatibility_TypeSizes`
- **Primary File**: `tests/test_msvc_types.cpp`
- **Verification Points**: 7 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_MsvcCompatibility_TypeSizes specific test data structures
  4. Verify that the 7 semantic properties match expected values
  ```

### `test_LiteralIntegration_IntegerDecimal`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() i32 { return 42; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_LiteralIntegration_IntegerHex`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() i32 { return 0x1F; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_LiteralIntegration_IntegerUnsigned`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() u32 { return 123u; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_LiteralIntegration_IntegerLong`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() i64 { return 123l; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_LiteralIntegration_IntegerUnsignedLong`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() u64 { return 123ul; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_LiteralIntegration_FloatSimple`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() f64 { return 3.14; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_LiteralIntegration_FloatScientific`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() f64 { return 2.0e1; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_LiteralIntegration_FloatExplicitF64`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() f64 { return 1.5; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_LiteralIntegration_CharBasic`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() u8 { return 'A'; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_LiteralIntegration_CharEscape`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() u8 { return '\
'; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_LiteralIntegration_StringBasic`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() *const u8 { return \
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_LiteralIntegration_StringEscape`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() *const u8 { return \
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_LiteralIntegration_BoolTrue`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() bool { return true; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_LiteralIntegration_BoolFalse`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() bool { return false; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_LiteralIntegration_NullLiteral`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() *i32 { return null; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_LiteralIntegration_ExpressionStatement`
- **Primary File**: `tests/integration/literal_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() void { 3.14; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_VariableIntegration_BasicI32`
- **Primary File**: `tests/integration/variable_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
var x: i32 = 42;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_VariableIntegration_BasicConstF64`
- **Primary File**: `tests/integration/variable_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
const y: f64 = 3.14;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_VariableIntegration_GlobalVar`
- **Primary File**: `tests/integration/variable_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
var global_val: u32 = 100u;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_VariableIntegration_LocalVar`
- **Primary File**: `tests/integration/variable_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() void {
  ```
  ```zig
var local_val: i16 = 500;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_VariableIntegration_InferredInt`
- **Primary File**: `tests/integration/variable_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
var x = 42;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_VariableIntegration_InferredFloat`
- **Primary File**: `tests/integration/variable_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
var y = 3.14;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_VariableIntegration_InferredBool`
- **Primary File**: `tests/integration/variable_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
const b = true;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_VariableIntegration_MangleKeyword`
- **Primary File**: `tests/integration/variable_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
var int: i32 = 0;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_VariableIntegration_MangleReserved`
- **Primary File**: `tests/integration/variable_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
var __reserved: i32 = 1;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_VariableIntegration_MangleLongName`
- **Primary File**: `tests/integration/variable_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
var this_is_a_very_long_variable_name_that_exceeds_31_chars: i32 = 1;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_VariableIntegration_DuplicateNameError`
- **Primary File**: `tests/integration/variable_decl_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
var x: i32 = 1;
  ```
  ```zig
var x: i32 = 2;
  ```
  ```zig
FAIL: Expected duplicate name error but pipeline succeeded
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_VariableIntegration_AllowSlice`
- **Primary File**: `tests/integration/variable_decl_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
var s: []u8 = undefined;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_VariableIntegration_PointerToVoid`
- **Primary File**: `tests/integration/variable_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
var p: *void = null;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_IntAdd`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_IntAdd specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_IntSub`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_IntSub specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_IntMul`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_IntMul specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_IntDiv`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_IntDiv specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_IntMod`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_IntMod specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_FloatAdd`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_FloatAdd specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_FloatSub`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_FloatSub specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_FloatMul`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_FloatMul specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_FloatDiv`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_FloatDiv specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_IntEq`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_IntEq specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_IntNe`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_IntNe specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_IntLt`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_IntLt specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_IntLe`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_IntLe specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_IntGt`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_IntGt specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_IntGe`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_IntGe specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_LogicalAnd`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_LogicalAnd specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_LogicalOr`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_LogicalOr specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_LogicalNot`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_LogicalNot specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_UnaryMinus`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_UnaryMinus specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_Parentheses`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_Parentheses specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_NestedParentheses`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Initialize test_ArithmeticIntegration_NestedParentheses specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_Int8LiteralPromotion`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn arithmetic_func() void {
  ```
  ```zig
var a: i8 = 10;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_TypeMismatchError`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn arithmetic_func() void { var x: i32 = 1; var y: f64 = 2.0; x + y; }
  ```
  ```zig
FAIL: Expected type mismatch error but pipeline succeeded.
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_FloatModuloError`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn arithmetic_func() void { 3.14 % 2.0; }
  ```
  ```zig
FAIL: Expected float modulo error but pipeline succeeded.
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArithmeticIntegration_BoolArithmeticError`
- **Primary File**: `tests/integration/arithmetic_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn arithmetic_func() void { true + false; }
  ```
  ```zig
FAIL: Expected boolean arithmetic error but pipeline succeeded.
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionIntegration_NoParams`
- **Primary File**: `tests/integration/function_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionIntegration_FourParams`
- **Primary File**: `tests/integration/function_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn add4(a: i32, b: i32, c: i32, d: i32) i32 { return a + b + c + d; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionIntegration_PointerTypes`
- **Primary File**: `tests/integration/function_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn ptr_func(p: *i32, s: *const u8) void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionIntegration_MangleKeyword`
- **Primary File**: `tests/integration/function_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn int() void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionIntegration_MangleLongName`
- **Primary File**: `tests/integration/function_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn this_is_a_very_long_function_name_that_exceeds_31_chars() void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionIntegration_Recursion`
- **Primary File**: `tests/integration/function_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn factorial(n: i32) i32 {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionIntegration_ForwardReference`
- **Primary File**: `tests/integration/function_decl_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn first() void { zF_0_second(); }
  ```
  ```zig
fn zF_0_second() void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionIntegration_AllowFiveParams`
- **Primary File**: `tests/integration/function_decl_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn many_params(a: i32, b: i32, c: i32, d: i32, e: i32) void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionIntegration_RejectSliceReturn`
- **Primary File**: `tests/integration/function_decl_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn get_slice() []u8 { return null; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionIntegration_AllowMultiLevelPointer`
- **Primary File**: `tests/integration/function_decl_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn multi_ptr(p: **i32) void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionIntegration_RejectDuplicateName`
- **Primary File**: `tests/integration/function_decl_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo() void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionCallIntegration_NoParams`
- **Primary File**: `tests/integration/function_call_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() void {}
  ```
  ```zig
fn main_func() void { foo(); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionCallIntegration_TwoArgs`
- **Primary File**: `tests/integration/function_call_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn add(a: i32, b: i32) i32 { return a + b; }
  ```
  ```zig
fn main_func() i32 { return add(1, 2); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionCallIntegration_FourArgs`
- **Primary File**: `tests/integration/function_call_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn bar(a: i32, b: f64, c: bool, d: *i32) void {}
  ```
  ```zig
fn main_func(p: *i32) void { bar(1, 2.0, true, p); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionCallIntegration_Nested`
- **Primary File**: `tests/integration/function_call_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn inner() i32 { return 42; }
  ```
  ```zig
fn outer(a: i32) i32 { return a; }
  ```
  ```zig
fn main_func() i32 { return outer(inner()); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionCallIntegration_MangleKeyword`
- **Primary File**: `tests/integration/function_call_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn int() void {}
  ```
  ```zig
fn main_func() void { int(); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionCallIntegration_VoidStatement`
- **Primary File**: `tests/integration/function_call_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn do_work() void {}
  ```
  ```zig
fn main_func() void {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_FunctionCallIntegration_CallResolution`
- **Primary File**: `tests/integration/function_call_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn add(a: i32, b: i32) i32 { return a + b; }
  ```
  ```zig
fn main_func() void { var x = add(1, 2); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_FunctionCallIntegration_AllowFiveArgs`
- **Primary File**: `tests/integration/function_call_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn many_args(a: i32, b: i32, c: i32, d: i32, e: i32) void {}
  ```
  ```zig
fn main_func() void { many_args(1, 2, 3, 4, 5); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_FunctionCallIntegration_AllowFunctionPointer`
- **Primary File**: `tests/integration/function_call_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn target() void {}
  ```
  ```zig
fn main_func() void {
  ```
  ```zig
var fp = target;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_FunctionCallIntegration_TypeMismatch`
- **Primary File**: `tests/integration/function_call_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn take_int(a: i32) void {}
  ```
  ```zig
fn main_func() void { take_int(3.14); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_FunctionCallIntegration_UndefinedFunction`
- **Primary File**: `tests/integration/function_call_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn main_func() void { undefined_func(); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Semantic Analysis (Type Checking) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```
