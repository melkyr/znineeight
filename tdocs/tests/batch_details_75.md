# Z98 Test Batch 75 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 5 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_DoubleFree_StructFieldTracking`
- **Implementation Source**: `tests/double_free_aggregate_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { ptr: *u8 };
  ```
  ```zig
fn my_func() -> void {
  ```
  ```zig
var s: S = undefined;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `has_double_free` is satisfied
  ```

### `test_DoubleFree_StructFieldLeak`
- **Implementation Source**: `tests/double_free_aggregate_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { ptr: *u8 };
fn my_func() -> void {
    var s: S = undefined;
    s.ptr = arena_alloc_default(100u);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `has_leak` is satisfied
  ```

### `test_DoubleFree_ArrayCollapseTracking`
- **Implementation Source**: `tests/double_free_aggregate_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var arr: [2]*u8 = undefined;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `has_double_free` is satisfied
  ```

### `test_DoubleFree_ErrorUnionAllocation`
- **Implementation Source**: `tests/double_free_aggregate_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn alloc() -> !*u8 { return error.Fail; }
  ```
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = alloc() catch return;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `has_double_free` is satisfied
  ```

### `test_DoubleFree_LoopMergingPreservesUnmodified`
- **Implementation Source**: `tests/double_free_aggregate_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func(cond: bool) -> void {
    var p: *u8 = arena_alloc_default(100u);
    var q: *u8 = arena_alloc_default(100u);
    while (cond) {
        arena_free(p);
    }
    arena_free(p); // Should be a double free risk
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `q_leaked` is satisfied
  ```
