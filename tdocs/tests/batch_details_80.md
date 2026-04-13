# Batch 80 Details: General Compiler Integration

## Focus
General Compiler Integration

This batch contains 3 test cases focusing on general compiler integration.

## Test Case Details
### `test_TaggedUnion_ArrayDecomposition`
- **Primary File**: `tests/integration/nested_expr_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
pub fn main() void {
  ```
  ```zig
var arr: [2]Cell = .{ .Alive, .Dead };
  ```
  ```zig
const Cell = union(enum) { Alive: void, Dead: void };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_TaggedUnion_NestedIfExpr`
- **Primary File**: `tests/integration/nested_expr_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
pub fn main() void {
  ```
  ```zig
var a = true;
  ```
  ```zig
var b = false;
  ```
  ```zig
var x: Cell = if (a) (if (b) .A else .B) else .C;
  ```
  ```zig
const Cell = union(enum) { A: void, B: void, C: void };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_TaggedUnion_NestedSwitchExpr`
- **Primary File**: `tests/integration/nested_expr_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
pub fn main() void {
  ```
  ```zig
var a = 1;
  ```
  ```zig
var x: Cell = switch (a) {
  ```
  ```zig
const Cell = union(enum) { A: void, B: void, C: void };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```
