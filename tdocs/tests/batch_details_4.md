# Z98 Test Batch 4 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 37 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_MemoryStability_TokenSupplierDanglingPointer`
- **Implementation Source**: `tests/memory_stability_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var v1 = 1; var v2 = 2; var v3 = 3;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `parser not equals null` is satisfied
  2. Validate that `true` is satisfied
  ```

### `test_C89Rejection_Slice`
- **Implementation Source**: `tests/test_c89_rejection.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var my_slice: []u8 = undefined;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Ensure that `expect_type_checker_abort(source` is false
  ```

### `test_C89Rejection_TryExpression`
- **Implementation Source**: `tests/test_c89_rejection.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn f() !void { return; }
 fn main() !void { try f(); return; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_C89Rejection_CatchExpression`
- **Implementation Source**: `tests/test_c89_rejection.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn f() !void { return; }
 fn main() void { f() catch {}; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_C89Rejection_OrelseExpression`
- **Implementation Source**: `tests/test_c89_rejection.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn f() ?*i32 { return null; }
 fn main() void { var x = f() orelse null; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_TypeChecker_AllowSliceExpression`
- **Implementation Source**: `tests/type_checker_slice_expression_test.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var my_array: [16]i32; var x = my_array[0..4];
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Ensure that `expect_type_checker_abort(source` is false
  ```

### `test_dynamic_array_destructor_fix`
- **Implementation Source**: `tests/bug_test_memory.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `DestructorTracker::destructor_call_count equals 17` is satisfied
  ```

### `test_Task119_DetectMalloc`
- **Implementation Source**: `tests/task_119_test.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() { malloc(10); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_Task119_DetectCalloc`
- **Implementation Source**: `tests/task_119_test.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() { calloc(1, 10); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_Task119_DetectRealloc`
- **Implementation Source**: `tests/task_119_test.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() { realloc(null, 10); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_Task119_DetectFree`
- **Implementation Source**: `tests/task_119_test.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() { free(null); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_Task119_DetectAlignedAlloc`
- **Implementation Source**: `tests/task_119_test.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() { aligned_alloc(16, 1024); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_Task119_DetectStrdup`
- **Implementation Source**: `tests/task_119_test.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() { strdup(\
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_Task119_DetectMemcpy`
- **Implementation Source**: `tests/task_119_test.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() { memcpy(null, null, 0); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_Task119_DetectMemset`
- **Implementation Source**: `tests/task_119_test.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() { memset(null, 0, 0); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_Task119_DetectStrcpy`
- **Implementation Source**: `tests/task_119_test.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() { strcpy(null, null); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_SymbolFlags_GlobalVariable`
- **Implementation Source**: `tests/test_symbol_flags.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
var global_x: i32 = 42;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `root not equals null` is satisfied
  2. Validate that `sym not equals null` is satisfied
  3. Validate that `sym.flags & SYMBOL_FLAG_GLOBAL` is satisfied
  4. Ensure that `sym.flags & SYMBOL_FLAG_LOCAL` is false
  ```

### `test_SymbolFlags_SymbolBuilder`
- **Implementation Source**: `tests/test_symbol_flags.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `sym.flags & SYMBOL_FLAG_LOCAL` is satisfied
  2. Validate that `sym.flags & SYMBOL_FLAG_PARAM` is satisfied
  3. Ensure that `sym.flags & SYMBOL_FLAG_GLOBAL` is false
  ```

### `test_safe_append_null_termination`
- **Implementation Source**: `tests/test_utils_bug.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `buffer[3] equals '\0'` is satisfied
  2. Validate that `remaining equals 7` is satisfied
  3. Validate that `dest equals buffer + 3` is satisfied
  4. Validate that `buffer[9] equals '\0'` is satisfied
  5. Validate that `remaining equals 0` is satisfied
  6. Validate that `dest equals buffer + 9` is satisfied
  ```

### `test_safe_append_explicit_check`
- **Implementation Source**: `tests/test_utils_bug.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `buf[0] equals 'L'` is satisfied
  2. Validate that `buf[1] equals 'O'` is satisfied
  3. Validate that `buf[2] equals 'N'` is satisfied
  4. Validate that `buf[3] equals '\0'` is satisfied
  5. Validate that `buf[3] not equals '0'` is satisfied
  6. Validate that `len equals 3` is satisfied
  ```

### `test_plat_itoa_null_termination`
- **Implementation Source**: `tests/test_utils_bug.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
-> buffer[0]='1', [1]='2', [2]='3', [3]='\0'
    ASSERT_TRUE(buffer[3] == '\0');
    if (buffer[3] == '0') return false; // Bug detection
    ASSERT_TRUE(strcmp(buffer,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `buffer[0] equals '0'` is satisfied
  2. Validate that `buffer[1] equals '\0'` is satisfied
  3. Validate that `buffer[3] equals '\0'` is satisfied
  4. Validate that `strcmp(buffer, "123"` is satisfied
  5. Validate that `strcmp(buffer, "-456"` is satisfied
  6. Validate that `buffer[4] equals '\0'` is satisfied
  ```

### `test_Lifetime_DirectReturnLocalAddress`
- **Implementation Source**: `tests/lifetime_analysis_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn bad() -> *i32 {
  var x: i32 = 42;
  return &x;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_lifetime_analyzer_test(source, ERR_LIFETIME_VIOLATION` is satisfied
  ```

### `test_Lifetime_ReturnLocalPointer`
- **Implementation Source**: `tests/lifetime_analysis_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn bad() -> *i32 {
  var x: i32 = 42;
  var p: *i32 = &x;
  return p;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_lifetime_analyzer_test(source, ERR_LIFETIME_VIOLATION` is satisfied
  ```

### `test_Lifetime_ReturnParamOK`
- **Implementation Source**: `tests/lifetime_analysis_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn ok(p: *i32) -> *i32 {
  var x: i32 = 42;
  p = &x;
  return p;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_lifetime_analyzer_test(source, ERR_LIFETIME_VIOLATION` is satisfied
  ```

### `test_Lifetime_ReturnAddrOfParam`
- **Implementation Source**: `tests/lifetime_analysis_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn bad(p: i32) -> *i32 {
  return &p;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_lifetime_analyzer_test(source, ERR_LIFETIME_VIOLATION` is satisfied
  ```

### `test_Lifetime_ReturnGlobalOK`
- **Implementation Source**: `tests/lifetime_analysis_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var y: i32 = 100;
fn ok() -> *i32 {
  return &y;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_lifetime_analyzer_test(source` is satisfied
  ```

### `test_Lifetime_ReassignedPointerOK`
- **Implementation Source**: `tests/lifetime_analysis_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var g: i32 = 0;
fn ok() -> *i32 {
  var x: i32 = 42;
  var p: *i32 = &x;
  p = &g;
  return p;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_lifetime_analyzer_test(source` is satisfied
  ```

### `test_NullPointerAnalyzer_BasicTracking`
- **Implementation Source**: `tests/null_pointer_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {
    var x: i32 = 0;
    var p: *i32 = &x;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `!ctx.getCompilationUnit` is satisfied
  ```

### `test_NullPointerAnalyzer_PersistentStateTracking`
- **Implementation Source**: `tests/null_pointer_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {
    var x: i32 = 0;
    var p: *i32 = null;
    {
        p = &x;
    }
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `!ctx.getCompilationUnit` is satisfied
  ```

### `test_NullPointerAnalyzer_AssignmentTracking`
- **Implementation Source**: `tests/null_pointer_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {
    var p: *i32 = null;
    p = null;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `!ctx.getCompilationUnit` is satisfied
  ```

### `test_NullPointerAnalyzer_IfNullGuard`
- **Implementation Source**: `tests/null_pointer_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {
  ```
  ```zig
var p: *i32 = null;
  ```
  ```zig
if (p != null) {
  ```
  ```zig
var x: i32 = p.*;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `!ctx.getCompilationUnit` is satisfied
  ```

### `test_NullPointerAnalyzer_IfElseMerge`
- **Implementation Source**: `tests/null_pointer_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {
  ```
  ```zig
var x: i32 = 0;
  ```
  ```zig
var p: *i32 = null;
  ```
  ```zig
if (p == null) {
  ```
  ```zig
// p is safe here too if it wasn't null
  ```
  ```zig
var y: i32 = p.*;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `!ctx.getCompilationUnit` is satisfied
  ```

### `test_NullPointerAnalyzer_WhileGuard`
- **Implementation Source**: `tests/null_pointer_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {
  ```
  ```zig
var p: *i32 = null;
  ```
  ```zig
while (p != null) {
  ```
  ```zig
var x: i32 = p.*;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `!ctx.getCompilationUnit` is satisfied
  ```

### `test_NullPointerAnalyzer_WhileConservativeReset`
- **Implementation Source**: `tests/null_pointer_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {
  ```
  ```zig
var x: i32 = 0;
  ```
  ```zig
var p: *i32 = &x;
  ```
  ```zig
while (p != null) {
  ```
  ```zig
var y: i32 = p.*;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `ctx.getCompilationUnit` is satisfied
  ```

### `test_NullPointerAnalyzer_Shadowing`
- **Implementation Source**: `tests/null_pointer_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {
  ```
  ```zig
var x: i32 = 0;
  ```
  ```zig
var p: *i32 = null;
  ```
  ```zig
var p: *i32 = &x;
  ```
  ```zig
var y: i32 = p.*;
  ```
  ```zig
var z: i32 = p.*;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `ctx.getCompilationUnit` is satisfied
  ```

### `test_NullPointerAnalyzer_NoLeakage`
- **Implementation Source**: `tests/null_pointer_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {
    var x: i32 = 0;
    if (true) {
        var inner: *i32 = &x;
        var a: i32 = inner.*;
    }
    // inner should not exist here
    // var b: i32 = inner.*; // This would be a type error
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `!ctx.getCompilationUnit` is satisfied
  ```

### `test_NullPointerAnalyzer_SliceIndexingSafe`
- **Implementation Source**: `tests/null_pointer_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(s: []const u8) u8 {
    return s[0];
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `!ctx.getCompilationUnit` is satisfied
  ```
