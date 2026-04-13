# Batch 50 Details: Multi-Module & Imports

## Focus
Multi-Module & Imports

This batch contains 5 test cases focusing on multi-module & imports.

## Test Case Details
### `test_RecursiveSlice_MultiModule`
- **Primary File**: `tests/integration/recursive_slice_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
const b = @import(\
  ```
  ```zig
pub const A = struct {
  ```
  ```zig
const a = @import(\
  ```
  ```zig
pub const B = struct {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Multi-Module & Imports environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_RecursiveSlice_SelfReference`
- **Primary File**: `tests/integration/recursive_slice_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo(v: JsonValue) usize {
  ```
  ```zig
const JsonValue = union(enum) {
  ```
  ```zig
String: []const u8,
  ```
  ```zig
const JsonField = struct {
  ```
  ```zig
name: []const u8,
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Multi-Module & Imports environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_RecursiveSlice_MutuallyRecursive`
- **Primary File**: `tests/integration/recursive_slice_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
pub fn main() void {
  ```
  ```zig
var a: A = undefined;
  ```
  ```zig
var b: B = undefined;
  ```
  ```zig
const A = struct {
  ```
  ```zig
const B = struct {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Multi-Module & Imports environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_RecursiveSlice_CrossModuleMutual`
- **Primary File**: `tests/integration/recursive_slice_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
const b = @import(\
  ```
  ```zig
pub const A = struct {
  ```
  ```zig
const a = @import(\
  ```
  ```zig
pub const B = struct {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Multi-Module & Imports environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_RecursiveSlice_InsideUnion`
- **Primary File**: `tests/integration/recursive_slice_tests.cpp`
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
pub fn main() void {
  ```
  ```zig
var v: JsonValue = undefined;
  ```
  ```zig
const JsonValue = union(enum) {
  ```
  ```zig
String: []const u8,
  ```
  ```zig
const JsonField = struct {
  ```
  ```zig
name: []const u8,
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Multi-Module & Imports environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Ensure execution completes without internal errors or crashes
  ```
