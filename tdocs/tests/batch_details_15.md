# Batch 15 Details: General Compiler Integration

## Focus
General Compiler Integration

This batch contains 12 test cases focusing on general compiler integration.

## Test Case Details
### `test_StructIntegration_BasicNamedStruct`
- **Primary File**: `tests/integration/struct_tests.cpp`
- **Test Input (Zig)**:
  ```zig
var p: Point = Point{ .x = 1, .y = 2 };
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

### `test_StructIntegration_MemberAccess`
- **Primary File**: `tests/integration/struct_tests.cpp`
- **Operations**: C89 Code Generation, Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo() i32 {
  ```
  ```zig
var p: Point = Point{ .x = 10, .y = 20 };
  ```
  ```zig
const Point = struct { x: i32, y: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute C89 Code Generation phase
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  5. Validate that emitted C code is syntactically correct C89
  ```

### `test_StructIntegration_NamedInitializerOrder`
- **Primary File**: `tests/integration/struct_tests.cpp`
- **Test Input (Zig)**:
  ```zig
var p: Point = Point{ .y = 20, .x = 10 };
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

### `test_StructIntegration_RejectAnonymousStruct`
- **Primary File**: `tests/integration/struct_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo() void {
  ```
  ```zig
var s: struct { x: i32 } = null;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_StructIntegration_RejectStructMethods`
- **Primary File**: `tests/integration/struct_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn length(self: *Point) i32 { return self.x; }
  ```
  ```zig
const Point = struct {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_StructIntegration_AllowSliceField`
- **Primary File**: `tests/integration/struct_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
const Buffer = struct {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_StructIntegration_AllowMultiLevelPointerField`
- **Primary File**: `tests/integration/struct_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
const Data = struct {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_TaggedUnion_BasicSwitch`
- **Primary File**: `tests/integration/tagged_union_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo(u: U) i32 {
  ```
  ```zig
const Tag = enum { a, b };
  ```
  ```zig
const U = union(Tag) { a: i32, b: f32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_TaggedUnion_ImplicitEnum`
- **Primary File**: `tests/integration/tagged_union_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo(u: U) i32 {
  ```
  ```zig
const U = union(enum) { a: i32, b: f32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_TaggedUnion_ElseProng`
- **Primary File**: `tests/integration/tagged_union_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo(u: U) i32 {
  ```
  ```zig
const U = union(enum) { a: i32, b: f32, c: bool };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_TaggedUnion_ExplicitEnumCustomValues`
- **Primary File**: `tests/integration/tagged_union_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo(u: U) i32 {
  ```
  ```zig
const Tag = enum(i32) { a = 100, b = 200 };
  ```
  ```zig
const U = union(Tag) { a: i32, b: f32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_TaggedUnion_CaptureImmutability`
- **Primary File**: `tests/integration/tagged_union_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo(u: U) void {
  ```
  ```zig
const U = union(enum) { a: i32 };
  ```
  ```zig
FAIL: Expected type error for immutable capture assignment, but succeeded.
  ```
  ```zig
FAIL: Did not find expected error message about immutable capture.
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup General Compiler Integration environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```
