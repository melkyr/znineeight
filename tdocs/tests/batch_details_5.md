# Batch 5 Details: Static Analysis

## Focus
Static Analysis

This batch contains 34 test cases focusing on static analysis.

## Test Case Details
### `test_DoubleFree_SimpleDoubleFree`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_BasicTracking`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_UninitializedFree`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8;
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

### `test_DoubleFree_MemoryLeak`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_DeferDoubleFree`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_ReassignmentLeak`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_NullReassignmentLeak`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_ReturnExempt`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> *u8 {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_SwitchAnalysis`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func(x: i32) -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_TryAnalysis`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn fallible() -> void {}
  ```
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_DoubleFree_TryAnalysisComplex`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn fallible() -> void {}
  ```
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_CatchAnalysis`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn fallible() -> *u8 { return null; }
  ```
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = fallible() catch arena_alloc_default(100u);
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

### `test_DoubleFree_BinaryOpAnalysis`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u) + 0u;
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

### `test_DoubleFree_LocationInLeakWarning`
- **Primary File**: `tests/test_double_free_locations.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_LocationInReassignmentLeak`
- **Primary File**: `tests/test_double_free_locations.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_LocationInDoubleFreeError`
- **Primary File**: `tests/test_double_free_locations.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_TransferTracking`
- **Primary File**: `tests/test_double_free_task_129.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn arena_alloc_default(size: usize) -> *void { return null; }
  ```
  ```zig
fn arena_create(initial_size: usize) -> *void { return null; }
  ```
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_DoubleFree_DeferContextInError`
- **Primary File**: `tests/test_double_free_task_129.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn arena_alloc_default(size: usize) -> *void { return null; }
  ```
  ```zig
fn arena_free(p: *void) -> void {}
  ```
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_ErrdeferContextInError`
- **Primary File**: `tests/test_double_free_task_129.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn arena_alloc_default(size: usize) -> *void { return null; }
  ```
  ```zig
fn arena_free(p: *void) -> void {}
  ```
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_IfElseBranching`
- **Primary File**: `tests/test_double_free_path_aware.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func(x: i32) -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_IfElseBothFree`
- **Primary File**: `tests/test_double_free_path_aware.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func(x: i32) -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_WhileConservative`
- **Primary File**: `tests/test_double_free_path_aware.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func(x: i32) -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_SwitchPathAware`
- **Primary File**: `tests/test_task_130_switch.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func(x: i32) -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_DoubleFree_SwitchBothFree`
- **Primary File**: `tests/test_task_130_switch.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func(x: i32) -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_DoubleFree_TryPathAware`
- **Primary File**: `tests/test_task_130_error_handling.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn mightFail() -> i32 {}
  ```
  ```zig
fn my_func(x: i32) -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_DoubleFree_CatchPathAware`
- **Primary File**: `tests/test_task_130_error_handling.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn mightFail() -> i32 {}
  ```
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_DoubleFree_OrelsePathAware`
- **Primary File**: `tests/test_task_130_error_handling.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn maybeAlloc() -> *u8 { return null; }
  ```
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
  ```zig
var q: *u8 = maybeAlloc() orelse arena_alloc_default(10u);
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_DoubleFree_LoopConservativeVerification`
- **Primary File**: `tests/test_task_130_loops.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func(x: i32) -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_DoubleFree_NestedDeferScopes`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
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

### `test_DoubleFree_PointerAliasing`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
  ```zig
var q: *u8 = p;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_DoubleFree_DeferInLoop`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func(x: i32) -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
  ```zig
var i: i32 = 0;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_DoubleFree_ConditionalAllocUnconditionalFree`
- **Primary File**: `tests/double_free_analysis_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn my_func(x: i32) -> void {
  ```
  ```zig
var p: *u8 = null;
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

### `test_Integration_FullPipeline`
- **Primary File**: `tests/integration_tests.cpp`
- **Verification Points**: 4 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn main() -> void {
  ```
  ```zig
fn leak_test() -> *i32 {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
  ```zig
var q: *i32 = null;
  ```
  ```zig
var x: i32 = 42;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_Integration_CorrectUsage`
- **Primary File**: `tests/integration_tests.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass
- **Test Input (Zig)**:
  ```zig
fn main() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Static Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  4. Verify that the 3 semantic properties match expected values
  ```
