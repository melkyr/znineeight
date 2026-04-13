# Z98 Test Batch _bugs Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 5 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_SwitchLifter_NestedControlFlow`
- **Implementation Source**: `tests/integration/switch_lifter_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: i32, cond: bool) i32 {
    return switch (x) {
        1 => if (cond) 10 else 20,
        else => 0,
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_Codegen_StringSplit`
- **Implementation Source**: `tests/integration/string_split_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
temp_string_split_test.c
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_Codegen_ForPtrToArray`
- **Implementation Source**: `tests/integration/for_ptr_array_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(ptr: *[5]i32) void {
    for (ptr) |item| {
        _ = item;
    }
}

  ```
  ```zig
temp_for_ptr_array_test.c
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ArrayProperty_Len`
- **Implementation Source**: `tests/integration/array_property_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {
    var arr: [5]i32 = undefined;
    var x: usize = arr.len;
    var ptr: *[10]u8 = undefined;
    var y: usize = ptr.len;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ArrayProperty_ComptimeLen`
- **Implementation Source**: `tests/integration/array_property_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {
    const arr = [3]i32{1, 2, 3};
    var buffer: [arr.len]i32 = undefined;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```
