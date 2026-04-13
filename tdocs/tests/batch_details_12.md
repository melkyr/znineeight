# Z98 Test Batch 12 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 89 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_BootstrapTypes_Allowed_Primitives`
- **Implementation Source**: `tests/test_bootstrap_types.cpp`
- **Zig Source Input (Test Case Context)**:
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
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(primitives[i]` is satisfied
  ```

### `test_BootstrapTypes_Allowed_Pointers`
- **Implementation Source**: `tests/test_bootstrap_types.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var a: *i32 = null;
var b: *const u8 = null;
var c: *void = null;
var d: **i32 = null;

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_BootstrapTypes_Allowed_Arrays`
- **Implementation Source**: `tests/test_bootstrap_types.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var a: [10]i32;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_BootstrapTypes_Allowed_Structs`
- **Implementation Source**: `tests/test_bootstrap_types.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { x: i32, y: f64 };
var s: S = S { .x = 1, .y = 2.0 };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_BootstrapTypes_Allowed_Enums`
- **Implementation Source**: `tests/test_bootstrap_types.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const E = enum { A, B, C };
var e: E = E.A;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_BootstrapTypes_Rejected_Slice`
- **Implementation Source**: `tests/test_bootstrap_types.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const arr: [5]u8 = undefined; var x: []u8 = arr[0..5];
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully("const arr: [5]u8 = undefined; var x: []u8 = arr[0..5];"` is satisfied
  ```

### `test_BootstrapTypes_Rejected_ErrorUnion`
- **Implementation Source**: `tests/test_bootstrap_types.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: !i32 = 0;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully("var x: !i32 = 0;"` is satisfied
  ```

### `test_BootstrapTypes_Rejected_Optional`
- **Implementation Source**: `tests/test_bootstrap_types.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: ?i32 = null;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully("var x: ?i32 = null;"` is satisfied
  ```

### `test_BootstrapTypes_Allowed_FunctionPointer`
- **Implementation Source**: `tests/test_bootstrap_types.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn f(p: fn(i32) void) void {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_BootstrapTypes_Allowed_ManyArgs`
- **Implementation Source**: `tests/test_bootstrap_types.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn f(a: i32, b: i32, c: i32, d: i32, e: i32) void {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_BootstrapTypes_Rejected_VoidVariable`
- **Implementation Source**: `tests/test_bootstrap_types.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: void;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_MsvcCompatibility_Int64Mapping`
- **Implementation Source**: `tests/test_msvc_types.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
, c89_type_map[i].c89_type_name);
            found_i64 = true;
        } else if (c89_type_map[i].zig_type_kind == TYPE_U64) {
            ASSERT_STREQ(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `found_i64` is satisfied
  2. Validate that `found_u64` is satisfied
  ```

### `test_MsvcCompatibility_TypeSizes`
- **Implementation Source**: `tests/test_msvc_types.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `get_g_type_i8` matches `1`
  2. Assert that `get_g_type_i16` matches `2`
  3. Assert that `get_g_type_i32` matches `4`
  4. Assert that `get_g_type_i64` matches `8`
  5. Assert that `get_g_type_f32` matches `4`
  6. Assert that `get_g_type_f64` matches `8`
  7. Assert that `get_g_type_bool` matches `4`
  ```

### `test_LiteralIntegration_IntegerDecimal`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() i32 { return 42; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_I32` and generates C code: `42`
  ```

### `test_LiteralIntegration_IntegerHex`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() i32 { return 0x1F; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_I32` and generates C code: `31`
  ```

### `test_LiteralIntegration_IntegerUnsigned`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() u32 { return 123u; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_U32` and generates C code: `123U`
  ```

### `test_LiteralIntegration_IntegerLong`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() i64 { return 123l; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_I64` and generates C code: `123LL`
  ```

### `test_LiteralIntegration_IntegerUnsignedLong`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() u64 { return 123ul; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_U64` and generates C code: `123ULL`
  ```

### `test_LiteralIntegration_FloatSimple`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() f64 { return 3.14; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_F64` and generates C code: `3.14`
  ```

### `test_LiteralIntegration_FloatScientific`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() f64 { return 2.0e1; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_F64` and generates C code: `20.0`
  ```

### `test_LiteralIntegration_FloatExplicitF64`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() f64 { return 1.5; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_F64` and generates C code: `1.5`
  ```

### `test_LiteralIntegration_CharBasic`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() u8 { return 'A'; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_U8` and generates C code: `'A'`
  ```

### `test_LiteralIntegration_CharEscape`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() u8 { return '\
'; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_U8` and generates C code: `'\\n'`
  ```

### `test_LiteralIntegration_StringBasic`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() *const u8 { return \
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_POINTER` and generates C code: `\"hello\"`
  ```

### `test_LiteralIntegration_StringEscape`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() *const u8 { return \
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_POINTER` and generates C code: `\"line1\\nline2\"`
  ```

### `test_LiteralIntegration_BoolTrue`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() bool { return true; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_BOOL` and generates C code: `1`
  ```

### `test_LiteralIntegration_BoolFalse`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() bool { return false; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_BOOL` and generates C code: `0`
  ```

### `test_LiteralIntegration_NullLiteral`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() *i32 { return null; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_NULL` and generates C code: `((void*)0)`
  ```

### `test_LiteralIntegration_ExpressionStatement`
- **Implementation Source**: `tests/integration/literal_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void { 3.14; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify literal resolves to type `TYPE_F64` and generates C code: `3.14`
  ```

### `test_VariableIntegration_BasicI32`
- **Implementation Source**: `tests/integration/variable_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: i32 = 42;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_VariableIntegration_BasicI32 and validate component behavior
  ```

### `test_VariableIntegration_BasicConstF64`
- **Implementation Source**: `tests/integration/variable_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const y: f64 = 3.14;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_VariableIntegration_BasicConstF64 and validate component behavior
  ```

### `test_VariableIntegration_GlobalVar`
- **Implementation Source**: `tests/integration/variable_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var global_val: u32 = 100u;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_VariableIntegration_GlobalVar and validate component behavior
  ```

### `test_VariableIntegration_LocalVar`
- **Implementation Source**: `tests/integration/variable_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {
    var local_val: i16 = 500;
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_VariableIntegration_LocalVar and validate component behavior
  ```

### `test_VariableIntegration_InferredInt`
- **Implementation Source**: `tests/integration/variable_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var x = 42;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_VariableIntegration_InferredInt and validate component behavior
  ```

### `test_VariableIntegration_InferredFloat`
- **Implementation Source**: `tests/integration/variable_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var y = 3.14;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_VariableIntegration_InferredFloat and validate component behavior
  ```

### `test_VariableIntegration_InferredBool`
- **Implementation Source**: `tests/integration/variable_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const b = true;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_VariableIntegration_InferredBool and validate component behavior
  ```

### `test_VariableIntegration_MangleKeyword`
- **Implementation Source**: `tests/integration/variable_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var int: i32 = 0;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_VariableIntegration_MangleKeyword and validate component behavior
  ```

### `test_VariableIntegration_MangleReserved`
- **Implementation Source**: `tests/integration/variable_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var __reserved: i32 = 1;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_VariableIntegration_MangleReserved and validate component behavior
  ```

### `test_VariableIntegration_MangleLongName`
- **Implementation Source**: `tests/integration/variable_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
this_is_a_very_long_variable_name_that_exceeds_31_chars
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_VariableIntegration_MangleLongName and validate component behavior
  ```

### `test_VariableIntegration_DuplicateNameError`
- **Implementation Source**: `tests/integration/variable_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: i32 = 1;
var x: i32 = 2;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_VariableIntegration_AllowSlice`
- **Implementation Source**: `tests/integration/variable_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var s: []u8 = undefined;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_VariableIntegration_PointerToVoid`
- **Implementation Source**: `tests/integration/variable_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var p: *void = null;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_VariableIntegration_PointerToVoid and validate component behavior
  ```

### `test_ArithmeticIntegration_IntAdd`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_I32` and emits `1 + 2`
  ```

### `test_ArithmeticIntegration_IntSub`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_I32` and emits `10 - 5`
  ```

### `test_ArithmeticIntegration_IntMul`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_I32` and emits `3 * 4`
  ```

### `test_ArithmeticIntegration_IntDiv`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_I32` and emits `20 / 4`
  ```

### `test_ArithmeticIntegration_IntMod`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_I32` and emits `7 % 3`
  ```

### `test_ArithmeticIntegration_FloatAdd`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_F64` and emits `1.5 + 2.5`
  ```

### `test_ArithmeticIntegration_FloatSub`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_F64` and emits `5.0 - 1.25`
  ```

### `test_ArithmeticIntegration_FloatMul`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_F64` and emits `2.0 * 3.14`
  ```

### `test_ArithmeticIntegration_FloatDiv`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_F64` and emits `10.0 / 4.0`
  ```

### `test_ArithmeticIntegration_IntEq`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_BOOL` and emits `1 == 1`
  ```

### `test_ArithmeticIntegration_IntNe`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_BOOL` and emits `1 != 2`
  ```

### `test_ArithmeticIntegration_IntLt`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_BOOL` and emits `5 < 10`
  ```

### `test_ArithmeticIntegration_IntLe`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_BOOL` and emits `5 <= 5`
  ```

### `test_ArithmeticIntegration_IntGt`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_BOOL` and emits `10 > 5`
  ```

### `test_ArithmeticIntegration_IntGe`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_BOOL` and emits `10 >= 10`
  ```

### `test_ArithmeticIntegration_LogicalAnd`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_BOOL` and emits `1 && 0`
  ```

### `test_ArithmeticIntegration_LogicalOr`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_BOOL` and emits `0 || 1`
  ```

### `test_ArithmeticIntegration_LogicalNot`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_BOOL` and emits `!1`
  ```

### `test_ArithmeticIntegration_UnaryMinus`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_I32` and emits `-42`
  ```

### `test_ArithmeticIntegration_Parentheses`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_I32` and emits `(1 + 2) * 3`
  ```

### `test_ArithmeticIntegration_NestedParentheses`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify arithmetic resolves to `TYPE_I32` and emits `((1 + 2) * (3 + 4))`
  ```

### `test_ArithmeticIntegration_Int8LiteralPromotion`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn arithmetic_func() void {
  ```
  ```zig
var a: i8 = 10;
  ```
  ```zig
, source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateExpressionType(TYPE_I8)) return false;
    if (!unit.validateExpressionEmission(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ArithmeticIntegration_TypeMismatchError`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn arithmetic_func() void { var x: i32 = 1; var y: f64 = 2.0; x + y; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ArithmeticIntegration_FloatModuloError`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn arithmetic_func() void { 3.14 % 2.0; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ArithmeticIntegration_BoolArithmeticError`
- **Implementation Source**: `tests/integration/arithmetic_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn arithmetic_func() void { true + false; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_FunctionIntegration_NoParams`
- **Implementation Source**: `tests/integration/function_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify function signature lowering: `void zF_0_foo(void)`
  ```

### `test_FunctionIntegration_FourParams`
- **Implementation Source**: `tests/integration/function_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn add4(a: i32, b: i32, c: i32, d: i32) i32 { return a + b + c + d; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_FunctionIntegration_FourParams and validate component behavior
  ```

### `test_FunctionIntegration_PointerTypes`
- **Implementation Source**: `tests/integration/function_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn ptr_func(p: *i32, s: *const u8) void {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_FunctionIntegration_PointerTypes and validate component behavior
  ```

### `test_FunctionIntegration_MangleKeyword`
- **Implementation Source**: `tests/integration/function_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn int() void {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Verify function signature lowering: `void zF_0_int(void)`
  ```

### `test_FunctionIntegration_MangleLongName`
- **Implementation Source**: `tests/integration/function_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
this_is_a_very_long_function_name_that_exceeds_31_chars
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_FunctionIntegration_MangleLongName and validate component behavior
  ```

### `test_FunctionIntegration_Recursion`
- **Implementation Source**: `tests/integration/function_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn factorial(n: i32) i32 {
    if (n <= 1) { return 1; }
    return (n * factorial(n - 1));
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_FunctionIntegration_Recursion and validate component behavior
  ```

### `test_FunctionIntegration_ForwardReference`
- **Implementation Source**: `tests/integration/function_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn first() void { zF_0_second(); }
fn zF_0_second() void {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_FunctionIntegration_ForwardReference and validate component behavior
  ```

### `test_FunctionIntegration_AllowFiveParams`
- **Implementation Source**: `tests/integration/function_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn many_params(a: i32, b: i32, c: i32, d: i32, e: i32) void {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_FunctionIntegration_RejectSliceReturn`
- **Implementation Source**: `tests/integration/function_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn get_slice() []u8 { return null; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_FunctionIntegration_AllowMultiLevelPointer`
- **Implementation Source**: `tests/integration/function_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn multi_ptr(p: **i32) void {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_FunctionIntegration_RejectDuplicateName`
- **Implementation Source**: `tests/integration/function_decl_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {}
fn foo() void {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_FunctionCallIntegration_NoParams`
- **Implementation Source**: `tests/integration/function_call_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {}
fn main_func() void { foo(); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_FunctionCallIntegration_NoParams and validate component behavior
  ```

### `test_FunctionCallIntegration_TwoArgs`
- **Implementation Source**: `tests/integration/function_call_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn add(a: i32, b: i32) i32 { return a + b; }
fn main_func() i32 { return add(1, 2); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_FunctionCallIntegration_TwoArgs and validate component behavior
  ```

### `test_FunctionCallIntegration_FourArgs`
- **Implementation Source**: `tests/integration/function_call_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn bar(a: i32, b: f64, c: bool, d: *i32) void {}
fn main_func(p: *i32) void { bar(1, 2.0, true, p); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_FunctionCallIntegration_FourArgs and validate component behavior
  ```

### `test_FunctionCallIntegration_Nested`
- **Implementation Source**: `tests/integration/function_call_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn inner() i32 { return 42; }
fn outer(a: i32) i32 { return a; }
fn main_func() i32 { return outer(inner()); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_FunctionCallIntegration_Nested and validate component behavior
  ```

### `test_FunctionCallIntegration_MangleKeyword`
- **Implementation Source**: `tests/integration/function_call_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn int() void {}
fn main_func() void { int(); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_FunctionCallIntegration_MangleKeyword and validate component behavior
  ```

### `test_FunctionCallIntegration_VoidStatement`
- **Implementation Source**: `tests/integration/function_call_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn do_work() void {}
fn main_func() void {
    do_work();
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_FunctionCallIntegration_VoidStatement and validate component behavior
  ```

### `test_FunctionCallIntegration_CallResolution`
- **Implementation Source**: `tests/integration/function_call_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn add(a: i32, b: i32) i32 { return a + b; }
fn main_func() void { var x = add(1, 2); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `unit.performTestPipeline(file_id` is satisfied
  ```

### `test_FunctionCallIntegration_AllowFiveArgs`
- **Implementation Source**: `tests/integration/function_call_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn many_args(a: i32, b: i32, c: i32, d: i32, e: i32) void {}
fn main_func() void { many_args(1, 2, 3, 4, 5); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `unit.performTestPipeline(file_id` is satisfied
  ```

### `test_FunctionCallIntegration_AllowFunctionPointer`
- **Implementation Source**: `tests/integration/function_call_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn target() void {}
fn main_func() void {
    var fp = target;
    fp();
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `unit.performTestPipeline(file_id` is satisfied
  ```

### `test_FunctionCallIntegration_TypeMismatch`
- **Implementation Source**: `tests/integration/function_call_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn take_int(a: i32) void {}
fn main_func() void { take_int(3.14); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_FunctionCallIntegration_UndefinedFunction`
- **Implementation Source**: `tests/integration/function_call_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main_func() void { undefined_func(); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Ensure that `unit.performTestPipeline(file_id` is false
  ```
