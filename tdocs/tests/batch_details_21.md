# Batch 21 Details: General Compiler Integration

## Focus
General Compiler Integration

This batch contains 15 test cases focusing on general compiler integration.

## Test Case Details
### `test_SizeOf_Primitive`
- **Primary File**: `tests/integration/builtin_size_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() usize { return @sizeOf(i32); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_SizeOf_Struct`
- **Primary File**: `tests/integration/builtin_size_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() usize { return @sizeOf(S); }
  ```
  ```zig
const S = struct { a: i32, b: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_SizeOf_Array`
- **Primary File**: `tests/integration/builtin_size_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() usize { return @sizeOf([10]i32); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_SizeOf_Pointer`
- **Primary File**: `tests/integration/builtin_size_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() usize { return @sizeOf(*i32); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_SizeOf_Incomplete_Error`
- **Primary File**: `tests/integration/builtin_size_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Initialize test_SizeOf_Incomplete_Error specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_AlignOf_Primitive`
- **Primary File**: `tests/integration/builtin_size_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() usize { return @alignOf(i64); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_AlignOf_Struct`
- **Primary File**: `tests/integration/builtin_size_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() usize { return @alignOf(S); }
  ```
  ```zig
const S = struct { a: u8, b: i64 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_PointerArithmetic_SizeOfUSize`
- **Primary File**: `tests/integration/pointer_arithmetic_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() usize {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_PointerArithmetic_AlignOfISize`
- **Primary File**: `tests/integration/pointer_arithmetic_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() usize {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_BuiltinOffsetOf_StructBasic`
- **Primary File**: `tests/integration/builtin_offsetof_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() usize {
  ```
  ```zig
const Point = struct { x: i32, y: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_BuiltinOffsetOf_StructPadding`
- **Primary File**: `tests/integration/builtin_offsetof_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() usize {
  ```
  ```zig
const S = struct { a: u8, b: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_BuiltinOffsetOf_Union`
- **Primary File**: `tests/integration/builtin_offsetof_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() usize {
  ```
  ```zig
const U = union { a: u8, b: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_BuiltinOffsetOf_NonAggregate_Error`
- **Primary File**: `tests/integration/builtin_offsetof_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() usize {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_BuiltinOffsetOf_FieldNotFound_Error`
- **Primary File**: `tests/integration/builtin_offsetof_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo() usize {
  ```
  ```zig
const Point = struct { x: i32, y: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_BuiltinOffsetOf_IncompleteType_Error`
- **Primary File**: `tests/integration/builtin_offsetof_tests.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Initialize test_BuiltinOffsetOf_IncompleteType_Error specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```
