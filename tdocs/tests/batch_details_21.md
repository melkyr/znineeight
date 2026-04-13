# Z98 Test Batch 21 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 15 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_SizeOf_Primitive`
- **Implementation Source**: `tests/integration/builtin_size_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() usize { return @sizeOf(i32); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_SizeOf_Primitive and validate component behavior
  ```

### `test_SizeOf_Struct`
- **Implementation Source**: `tests/integration/builtin_size_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { a: i32, b: i32 };
fn foo() usize { return @sizeOf(S); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_SizeOf_Struct and validate component behavior
  ```

### `test_SizeOf_Array`
- **Implementation Source**: `tests/integration/builtin_size_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() usize { return @sizeOf([10]i32); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_SizeOf_Array and validate component behavior
  ```

### `test_SizeOf_Pointer`
- **Implementation Source**: `tests/integration/builtin_size_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() usize { return @sizeOf(*i32); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_SizeOf_Pointer and validate component behavior
  ```

### `test_SizeOf_Incomplete_Error`
- **Implementation Source**: `tests/integration/builtin_size_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_SizeOf_Incomplete_Error and validate component behavior
  ```

### `test_AlignOf_Primitive`
- **Implementation Source**: `tests/integration/builtin_size_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() usize { return @alignOf(i64); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_AlignOf_Primitive and validate component behavior
  ```

### `test_AlignOf_Struct`
- **Implementation Source**: `tests/integration/builtin_size_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { a: u8, b: i64 };
fn foo() usize { return @alignOf(S); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_AlignOf_Struct and validate component behavior
  ```

### `test_PointerArithmetic_SizeOfUSize`
- **Implementation Source**: `tests/integration/pointer_arithmetic_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() usize {
    return @sizeOf(usize);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_PointerArithmetic_SizeOfUSize and validate component behavior
  ```

### `test_PointerArithmetic_AlignOfISize`
- **Implementation Source**: `tests/integration/pointer_arithmetic_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() usize {
    return @alignOf(isize);
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_PointerArithmetic_AlignOfISize and validate component behavior
  ```

### `test_BuiltinOffsetOf_StructBasic`
- **Implementation Source**: `tests/integration/builtin_offsetof_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Point = struct { x: i32, y: i32 };
  ```
  ```zig
fn foo() usize {
  ```
  ```zig
return @offsetOf(Point, \
  ```
  ```zig
;
    // x is at 0, y is at 4 (size of i32)
    return run_offsetof_test(source,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_BuiltinOffsetOf_StructBasic and validate component behavior
  ```

### `test_BuiltinOffsetOf_StructPadding`
- **Implementation Source**: `tests/integration/builtin_offsetof_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { a: u8, b: i32 };
  ```
  ```zig
fn foo() usize {
  ```
  ```zig
return @offsetOf(S, \
  ```
  ```zig
;
    // a is at 0 (size 1), b needs 4-byte alignment, so b is at 4.
    return run_offsetof_test(source,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_BuiltinOffsetOf_StructPadding and validate component behavior
  ```

### `test_BuiltinOffsetOf_Union`
- **Implementation Source**: `tests/integration/builtin_offsetof_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const U = union { a: u8, b: i32 };
  ```
  ```zig
fn foo() usize {
  ```
  ```zig
return @offsetOf(U, \
  ```
  ```zig
;
    // In a union, all fields start at offset 0.
    return run_offsetof_test(source,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_BuiltinOffsetOf_Union and validate component behavior
  ```

### `test_BuiltinOffsetOf_NonAggregate_Error`
- **Implementation Source**: `tests/integration/builtin_offsetof_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() usize {
  ```
  ```zig
return @offsetOf(i32, \
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_BuiltinOffsetOf_NonAggregate_Error and validate component behavior
  ```

### `test_BuiltinOffsetOf_FieldNotFound_Error`
- **Implementation Source**: `tests/integration/builtin_offsetof_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Point = struct { x: i32, y: i32 };
  ```
  ```zig
fn foo() usize {
  ```
  ```zig
return @offsetOf(Point, \
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_BuiltinOffsetOf_FieldNotFound_Error and validate component behavior
  ```

### `test_BuiltinOffsetOf_IncompleteType_Error`
- **Implementation Source**: `tests/integration/builtin_offsetof_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_BuiltinOffsetOf_IncompleteType_Error and validate component behavior
  ```
