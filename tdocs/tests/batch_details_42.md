# Z98 Test Batch 42 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 7 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_ForIntegration_Basic`
- **Implementation Source**: `tests/integration/for_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(arr: [5]i32) void {
    for (arr) |item| {
        var dummy = item;
    }
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ForIntegration_InvalidIterable`
- **Implementation Source**: `tests/integration/for_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {
    var x: bool = true;
    for (x) |item| {
        var dummy = item;
    }
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ForIntegration_ImmutableCapture`
- **Implementation Source**: `tests/integration/for_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(arr: [3]i32) void {
    for (arr) |item| {
        item = 10;
    }
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ForIntegration_DiscardCapture`
- **Implementation Source**: `tests/integration/for_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(arr: [3]i32) void {
    for (arr) |_, index| {
        var x: usize = index;
    }
    for (arr) |item, _| {
        var y: i32 = item;
    }
    for (0..10) |_| {
        var z: i32 = 1;
    }
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ForIntegration_Scoping`
- **Implementation Source**: `tests/integration/for_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(arr: [3]i32) void {
    for (arr) |item| {
        var x: i32 = item;
    }
    // item should not be visible here
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ParamIntegration_Immutable`
- **Implementation Source**: `tests/integration/param_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: i32) void {
    x = 10;
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ParamIntegration_MutablePointer`
- **Implementation Source**: `tests/integration/param_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(ptr: *i32) void {
    ptr.* = 10; // This should be allowed
    // ptr = @ptrCast(*i32, 0); // This should be forbidden
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```
