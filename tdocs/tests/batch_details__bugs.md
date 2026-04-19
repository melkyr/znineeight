# Batch _bugs Details: Code Generation (C89)

## Focus
Code Generation (C89)

This batch contains 5 test cases focusing on code generation (c89).

## Test Case Details
### `test_SwitchLifter_NestedControlFlow`
- **Primary File**: `tests/integration/switch_lifter_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo(x: i32, cond: bool) i32 {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Code Generation (C89) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_StringSplit`
- **Primary File**: `tests/integration/string_split_tests.cpp`
- **Operations**: C89 Code Generation, Source Loading
- **Test Input (Zig)**:
  ```zig
pub const long_string = \
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Code Generation (C89) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute C89 Code Generation phase
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  5. Validate that emitted C code is syntactically correct C89
  ```

### `test_Codegen_ForPtrToArray`
- **Primary File**: `tests/integration/for_ptr_array_tests.cpp`
- **Operations**: C89 Code Generation, Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo(ptr: *[5]i32) void {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Code Generation (C89) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute C89 Code Generation phase
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  5. Validate that emitted C code is syntactically correct C89
  ```

### `test_ArrayProperty_Len`
- **Primary File**: `tests/integration/array_property_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo() void {
  ```
  ```zig
var arr: [5]i32 = undefined;
  ```
  ```zig
var x: usize = arr.len;
  ```
  ```zig
var ptr: *[10]u8 = undefined;
  ```
  ```zig
var y: usize = ptr.len;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Code Generation (C89) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_ArrayProperty_ComptimeLen`
- **Primary File**: `tests/integration/array_property_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo() void {
  ```
  ```zig
var buffer: [arr.len]i32 = undefined;
  ```
  ```zig
const arr = [3]i32{1, 2, 3};
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Code Generation (C89) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```
