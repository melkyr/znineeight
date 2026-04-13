# Z98 Test Batch 40 Technical Specification

## High-Level Objective
Slices Support: Full integration testing for Zig slices ([]T), including implicit array-to-slice coercion, slicing syntax [start..end], and length property access.

This test batch comprises 11 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_SliceIntegration_Declaration`
- **Implementation Source**: `tests/integration/slice_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var global_slice: []i32 = undefined;
fn foo() void {
    var local_slice: []const u8 = undefined;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `global_sym not equals null` is satisfied
  3. Assert that `TYPE_SLICE` matches `global_sym.kind of symbol_type`
  4. Assert that `TYPE_I32` matches `global_sym.symbol_type.as.slice.kind of element_type`
  5. Ensure that `global_sym.symbol_type.as.slice.is_const` is false
  6. Validate that `fn not equals null` is satisfied
  ```

### `test_SliceIntegration_ParametersAndReturn`
- **Implementation Source**: `tests/integration/slice_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn process(s: []i32) []i32 {
    return s;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `fn_sym not equals null` is satisfied
  3. Assert that `TYPE_FUNCTION` matches `kind of fn_type`
  4. Assert that `1` matches `fn_type.as.function.params.length`
  5. Assert that `TYPE_SLICE` matches `*fn_type.as.function.params)[0].kind`
  6. Assert that `TYPE_SLICE` matches `fn_type.as.function.kind of return_type`
  ```

### `test_SliceIntegration_IndexingAndLength`
- **Implementation Source**: `tests/integration/slice_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(s: []i32) i32 {
    var len: usize = s.len;
    return s[0];
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `emission.find("s.len"` is satisfied
  3. Validate that `emission.find("s.ptr[0]"` is satisfied
  ```

### `test_SliceIntegration_SlicingArrays`
- **Implementation Source**: `tests/integration/slice_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var arr: [10]i32 = undefined;
fn foo() void {
    var s1 = arr[0..5];
    var s2 = arr[5..];
    var s3 = arr[..5];
    var s4 = arr[..];
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_SliceIntegration_SlicingSlices`
- **Implementation Source**: `tests/integration/slice_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(s: []i32) void {
    var s1 = s[1..4];
    var s2 = s[2..];
    var s3 = s[..3];
    var s4 = s[..];
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_SliceIntegration_SlicingPointers`
- **Implementation Source**: `tests/integration/slice_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(ptr: [*]i32) void {
    var s1 = ptr[0..10];
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_SliceIntegration_ArrayToSliceCoercion`
- **Implementation Source**: `tests/integration/slice_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn takeSlice(s: []const i32) void {}
fn foo() void {
    var arr: [5]i32 = undefined;
    takeSlice(arr);
    var s: []const i32 = arr;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_SliceIntegration_ConstCorrectness`
- **Implementation Source**: `tests/integration/slice_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(s: []const i32) void {
    s[0] = 42;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_SliceIntegration_CompileTimeBoundsChecks`
- **Implementation Source**: `tests/integration/slice_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {
    var arr: [10]i32 = undefined;
    var s = arr[5..11];
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_SliceIntegration_ManyItemPointerMissingIndices`
- **Implementation Source**: `tests/integration/slice_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(ptr: [*]i32) void {
    var s = ptr[0..];
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_SliceIntegration_ConstPointerToArraySlicing`
- **Implementation Source**: `tests/integration/slice_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(ptr: *const [10]i32) void {
    var s = ptr[0..5];
    // s should be []const i32
    // s[0] = 1; // would be error
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```
