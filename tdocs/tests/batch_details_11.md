# Batch 11 Details: Lexical Analysis

## Focus
Lexical Analysis

This batch contains 30 test cases focusing on lexical analysis.

## Test Case Details
### `test_Milestone4_Lexer_Tokens`
- **Primary File**: `tests/test_milestone4_lexer_parser.cpp`
- **Verification Points**: 13 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Milestone4_Lexer_Tokens specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 13 semantic properties match expected values
  ```

### `test_Milestone4_Parser_AST`
- **Primary File**: `tests/test_milestone4_lexer_parser.cpp`
- **Verification Points**: 8 assertions
- **Operations**: Syntactic Parsing, Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Milestone4_Parser_AST specific test data structures
  3. Execute Syntactic Parsing phase
  3. Execute Source Loading phase
  4. Verify that the 8 semantic properties match expected values
  ```

### `test_OptionalType_Creation`
- **Primary File**: `tests/test_optional_type.cpp`
- **Verification Points**: 5 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_OptionalType_Creation specific test data structures
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_OptionalType_ToString`
- **Primary File**: `tests/test_optional_type.cpp`
- **Verification Points**: 1 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_OptionalType_ToString specific test data structures
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_OptionalType`
- **Primary File**: `tests/test_optional_type_checker.cpp`
- **Verification Points**: 5 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking
- **Test Input (Zig)**:
  ```zig
var x: ?i32 = null;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_NameMangler_Milestone4Types`
- **Primary File**: `tests/test_milestone4_name_mangling.cpp`
- **Verification Points**: 4 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_NameMangler_Milestone4Types specific test data structures
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_CallSiteLookupTable_Basic`
- **Primary File**: `tests/test_call_site_lookup.cpp`
- **Verification Points**: 6 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_CallSiteLookupTable_Basic specific test data structures
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_CallSiteLookupTable_Unresolved`
- **Primary File**: `tests/test_call_site_lookup.cpp`
- **Verification Points**: 4 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_CallSiteLookupTable_Unresolved specific test data structures
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_TypeChecker_CallSiteRecording_Direct`
- **Primary File**: `tests/type_checker_call_site_tests.cpp`
- **Verification Points**: 6 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo() void {}
  ```
  ```zig
fn main() void { foo(); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_TypeChecker_CallSiteRecording_Recursive`
- **Primary File**: `tests/type_checker_call_site_tests.cpp`
- **Verification Points**: 5 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn factorial(n: i32) i32 {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_TypeChecker_CallSiteRecording_Generic`
- **Primary File**: `tests/type_checker_call_site_tests.cpp`
- **Verification Points**: 5 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn identity(comptime T: type, x: T) T { return x; }
  ```
  ```zig
fn main() void {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_Task165_ForwardReference`
- **Primary File**: `tests/test_task_165_resolution.cpp`
- **Verification Points**: 6 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn main() void { foo(); }
  ```
  ```zig
fn foo() void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_Task165_BuiltinRejection`
- **Primary File**: `tests/test_task_165_resolution.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Task165_BuiltinRejection specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Task165_C89Incompatible`
- **Primary File**: `tests/test_task_165_resolution.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Static Analysis Pass, Source Loading
- **Test Input (Zig)**:
  ```zig
fn takeIncompatible(e: test_incompatible) void {}
  ```
  ```zig
fn main() void { takeIncompatible(undefined); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Static Analysis Pass phase
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_IndirectCall_Variable`
- **Primary File**: `tests/test_indirect_calls.cpp`
- **Verification Points**: 4 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo() void {}
  ```
  ```zig
fn main() void { fp(); }
  ```
  ```zig
const fp = foo;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_IndirectCall_Member`
- **Primary File**: `tests/test_indirect_calls.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn main() void {
  ```
  ```zig
var s: S = undefined;
  ```
  ```zig
const S = struct { f: fn() void };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_IndirectCall_Array`
- **Primary File**: `tests/test_indirect_calls.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn main() void {
  ```
  ```zig
const funcs: [2]fn() void = undefined;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_IndirectCall_Returned`
- **Primary File**: `tests/test_indirect_calls.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn getFunc() fn() void { return undefined; }
  ```
  ```zig
fn main() void {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_IndirectCall_Complex`
- **Primary File**: `tests/test_indirect_calls.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo() void {}
  ```
  ```zig
fn main() void {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_ForwardReference_GlobalVariable`
- **Primary File**: `tests/test_forward_reference.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn main() i32 { return x; }
  ```
  ```zig
const x: i32 = 42;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_ForwardReference_MutualFunction`
- **Primary File**: `tests/test_forward_reference.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn a() void { b(); }
  ```
  ```zig
fn b() void { a(); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_ForwardReference_StructType`
- **Primary File**: `tests/test_forward_reference.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
const p: Point = Point { .x = 1, .y = 2 };
  ```
  ```zig
const Point = struct { x: i32, y: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_Recursive_Factorial`
- **Primary File**: `tests/test_recursive_calls.cpp`
- **Verification Points**: 10 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn factorial(n: i32) i32 {
  ```
  ```zig
fn main() void {
  ```
  ```zig
var x: i32 = factorial(5);
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 10 semantic properties match expected values
  ```

### `test_Recursive_Mutual_Mangled`
- **Primary File**: `tests/test_recursive_calls.cpp`
- **Verification Points**: 8 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn isEven(n: i32) bool {
  ```
  ```zig
fn isOdd(n: i32) bool {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 8 semantic properties match expected values
  ```

### `test_Recursive_Forward_Mangled`
- **Primary File**: `tests/test_recursive_calls.cpp`
- **Verification Points**: 8 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn start() void { later(); }
  ```
  ```zig
fn later() void { start(); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 8 semantic properties match expected values
  ```

### `test_CallSyntax_AtImport`
- **Primary File**: `tests/test_call_syntax.cpp`
- **Verification Points**: 7 assertions
- **Operations**: Syntactic Parsing, Source Loading
- **Test Input (Zig)**:
  ```zig
const std = @import(\
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Source Loading phase
  4. Verify that the 7 semantic properties match expected values
  ```

### `test_CallSyntax_AtImport_Pipeline`
- **Primary File**: `tests/test_call_syntax.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
const std = @import(\
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_CallSyntax_ComplexPostfix`
- **Primary File**: `tests/test_call_syntax.cpp`
- **Verification Points**: 13 assertions
- **Operations**: Syntactic Parsing, Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo() void { a().b().c(); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Source Loading phase
  4. Verify that the 13 semantic properties match expected values
  ```

### `test_CallSyntax_MethodCall`
- **Primary File**: `tests/test_call_syntax.cpp`
- **Verification Points**: 4 assertions
- **Operations**: Syntactic Parsing, Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo() void { s.method(); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Source Loading phase
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_Task168_ComplexContexts`
- **Primary File**: `tests/task_168_validation.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn getInt() i32 { return 42; }
  ```
  ```zig
fn process(n: i32) void {}
  ```
  ```zig
fn doubleInt(n: i32) i32 { return n * 2; }
  ```
  ```zig
fn main() void {
  ```
  ```zig
const S = struct { f: i32 };
  ```
  ```zig
const s: S = S { .f = getInt() };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```
