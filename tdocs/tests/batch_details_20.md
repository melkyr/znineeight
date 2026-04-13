# Z98 Test Batch 20 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 21 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_PtrCast_Basic`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(ptr: *i32) *u8 {
    return @ptrCast(*u8, ptr);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_PtrCast_Basic and validate component behavior
  ```

### `test_PtrCast_ToConst`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(ptr: *i32) *const i32 {
    return @ptrCast(*const i32, ptr);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_PtrCast_ToConst and validate component behavior
  ```

### `test_PtrCast_FromVoid`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(ptr: *void) *i32 {
    return @ptrCast(*i32, ptr);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_PtrCast_FromVoid and validate component behavior
  ```

### `test_PtrCast_ToVoid`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(ptr: *i32) *void {
    return @ptrCast(*void, ptr);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_PtrCast_ToVoid and validate component behavior
  ```

### `test_PtrCast_TargetNotPointer_Error`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(ptr: *i32) i32 {
    return @ptrCast(i32, ptr);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_PtrCast_TargetNotPointer_Error and validate component behavior
  ```

### `test_PtrCast_SourceNotPointer_Error`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(val: i32) *i32 {
    return @ptrCast(*i32, val);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_PtrCast_SourceNotPointer_Error and validate component behavior
  ```

### `test_PtrCast_Nested`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(ptr: *void) *u8 {
    return @ptrCast(*u8, @ptrCast(*i32, ptr));
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_PtrCast_Nested and validate component behavior
  ```

### `test_IntCast_Constant_Fold`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() u8 {
    return @intCast(u8, 100);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_IntCast_Constant_Fold and validate component behavior
  ```

### `test_IntCast_Constant_Overflow_Error`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() u8 {
    return @intCast(u8, 300);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_IntCast_Constant_Overflow_Error and validate component behavior
  ```

### `test_IntCast_Runtime`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: u32) i32 {
    return @intCast(i32, x);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_IntCast_Runtime and validate component behavior
  ```

### `test_IntCast_Widening`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: u8) i32 {
    return @intCast(i32, x);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_IntCast_Widening and validate component behavior
  ```

### `test_IntCast_Bool`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(b: bool) u8 {
    return @intCast(u8, b);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_IntCast_Bool and validate component behavior
  ```

### `test_FloatCast_Constant_Fold`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() f32 {
    return @floatCast(f32, 3.14);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_FloatCast_Constant_Fold and validate component behavior
  ```

### `test_FloatCast_Runtime_Widening`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: f32) f64 {
    return @floatCast(f64, x);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_FloatCast_Runtime_Widening and validate component behavior
  ```

### `test_FloatCast_Runtime_Narrowing`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: f64) f32 {
    return @floatCast(f32, x);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_FloatCast_Runtime_Narrowing and validate component behavior
  ```

### `test_Cast_Invalid_Types_Error`
- **Implementation Source**: `tests/integration/cast_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: f32) i32 {
    return @intCast(i32, x);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Cast_Invalid_Types_Error and validate component behavior
  ```

### `test_Codegen_IntCast_SafeWidening`
- **Implementation Source**: `tests/integration/codegen_cast_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(x: i32) i64 { return @intCast(i64, x); }
  ```
  ```zig
return (i64)x;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_IntCast_SafeWidening and validate component behavior
  ```

### `test_Codegen_IntCast_Narrowing`
- **Implementation Source**: `tests/integration/codegen_cast_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(x: i64) i32 { return @intCast(i32, x); }
  ```
  ```zig
return __bootstrap_i32_from_i64(x);
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_IntCast_Narrowing and validate component behavior
  ```

### `test_Codegen_IntCast_SignednessMismatch`
- **Implementation Source**: `tests/integration/codegen_cast_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(x: i32) u32 { return @intCast(u32, x); }
  ```
  ```zig
return __bootstrap_u32_from_i32(x);
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_IntCast_SignednessMismatch and validate component behavior
  ```

### `test_Codegen_FloatCast_SafeWidening`
- **Implementation Source**: `tests/integration/codegen_cast_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(x: f32) f64 { return @floatCast(f64, x); }
  ```
  ```zig
return (double)x;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_FloatCast_SafeWidening and validate component behavior
  ```

### `test_Codegen_FloatCast_Narrowing`
- **Implementation Source**: `tests/integration/codegen_cast_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(x: f64) f32 { return @floatCast(f32, x); }
  ```
  ```zig
return __bootstrap_f32_from_f64(x);
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_FloatCast_Narrowing and validate component behavior
  ```
