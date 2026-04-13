# Batch 75 Details: Static Analysis

## Focus
Static Analysis

This batch contains 5 test cases focusing on static analysis.

## Test Case Details
### `test_DoubleFree_StructFieldTracking`
- **Primary File**: `tests/double_free_aggregate_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var s: S = undefined;
  ```
  ```zig
const S = struct { ptr: *u8 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_DoubleFree_StructFieldLeak`
- **Primary File**: `tests/double_free_aggregate_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var s: S = undefined;
  ```
  ```zig
const S = struct { ptr: *u8 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_DoubleFree_ArrayCollapseTracking`
- **Primary File**: `tests/double_free_aggregate_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var arr: [2]*u8 = undefined;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_DoubleFree_ErrorUnionAllocation`
- **Primary File**: `tests/double_free_aggregate_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn alloc() -> !*u8 { return error.Fail; }
  ```
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = alloc() catch return;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_DoubleFree_LoopMergingPreservesUnmodified`
- **Primary File**: `tests/double_free_aggregate_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func(cond: bool) -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
  ```zig
var q: *u8 = arena_alloc_default(100u);
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 2 semantic properties match expected values
  ```
