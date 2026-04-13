# Z98 Test Batch 28 Technical Specification

## High-Level Objective
Call Resolution and Site Tracking: Verifies function call resolution across modules, including mutual recursion, and rejection of unsupported indirect calls in the bootstrap phase.

This test batch comprises 4 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_Task168_MutualRecursion`
- **Implementation Source**: `tests/task_168_validation.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn a() void { b(); }
fn b() void { c(); }
fn c() void { a(); }

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Assert that `table.count` matches `3`
  4. Validate that `table.getEntry(i` is satisfied
  5. Assert that `table.getEntry(i` matches `CALL_DIRECT`
  ```

### `test_Task168_IndirectCallRejection`
- **Implementation Source**: `tests/task_168_validation.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {}
fn main() void {
    const f = foo;
    f();
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Assert that `unit.getIndirectCallCatalogue` matches `1`
  4. Assert that `unit.getIndirectCallCatalogue` matches `INDIRECT_VARIABLE`
  ```

### `test_Task168_GenericCallChain`
- **Implementation Source**: `tests/task_168_validation.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn max(comptime T: type, a: T, b: T) T { return a; }
fn main() void {
    const x: i32 = max(i32, 10, 20) + max(i32, 5, 15);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `table.getEntry(i` is satisfied
  3. Assert that `generic_calls` matches `2`
  ```

### `test_Task168_BuiltinCall`
- **Implementation Source**: `tests/task_168_validation.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() void {
  ```
  ```zig
const std = @import(\
  ```
  ```zig
);
    if (f) {
        fprintf(f,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Assert that `table.count` matches `0`
  ```
