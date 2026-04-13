# Batch 7_debug Details: Syntactic Analysis (Parser & AST)

## Focus
Syntactic Analysis (Parser & AST)

This batch contains 51 test cases focusing on syntactic analysis (parser & ast).

## Test Case Details
### `test_Task142_ErrorFunctionDetection`
- **Primary File**: `tests/test_task_142.cpp`
- **Verification Points**: 4 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn open() !File { return File{}; }
  ```
  ```zig
fn read() FileError!i32 { return 0; }
  ```
  ```zig
fn valid(a: i32) i32 { return a; }
  ```
  ```zig
const File = struct {};
  ```
  ```zig
const FileError = error{NotFound, Permission};
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_Task142_ErrorFunctionRejection`
- **Primary File**: `tests/test_task_142.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn open() !i32 { return 0; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_Task143_TryExpressionDetection_Contexts`
- **Primary File**: `tests/test_task_143.cpp`
- **Verification Points**: 5 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn mightFail() !i32 { return 42; }
  ```
  ```zig
fn doTest() void {
  ```
  ```zig
fn returnTry() !i32 {
  ```
  ```zig
var x: i32 = try mightFail();
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_Task143_TryExpressionDetection_Nested`
- **Primary File**: `tests/test_task_143.cpp`
- **Verification Points**: 6 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn inner() !i32 { return 1; }
  ```
  ```zig
fn doTest() void {
  ```
  ```zig
var x: i32 = try (try inner());
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_Task143_TryExpressionDetection_MultipleInStatement`
- **Primary File**: `tests/test_task_143.cpp`
- **Verification Points**: 4 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn a() !i32 { return 1; }
  ```
  ```zig
fn b() !i32 { return 2; }
  ```
  ```zig
fn doTest() void {
  ```
  ```zig
var x: i32 = try a() + try b();
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_CatchExpressionCatalogue_Basic`
- **Primary File**: `tests/test_catalogues_task_144.cpp`
- **Verification Points**: 8 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Initialize test_CatchExpressionCatalogue_Basic specific test data structures
  4. Verify that the 8 semantic properties match expected values
  ```

### `test_CatchExpressionCatalogue_Chaining`
- **Primary File**: `tests/test_catalogues_task_144.cpp`
- **Verification Points**: 5 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Initialize test_CatchExpressionCatalogue_Chaining specific test data structures
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_OrelseExpressionCatalogue_Basic`
- **Primary File**: `tests/test_catalogues_task_144.cpp`
- **Verification Points**: 4 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Initialize test_OrelseExpressionCatalogue_Basic specific test data structures
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_Task144_CatchExpressionDetection_Basic`
- **Primary File**: `tests/test_task_144_detection.cpp`
- **Verification Points**: 8 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn mightFail() !i32 { return 42; }
  ```
  ```zig
fn doTest() void {
  ```
  ```zig
var x: i32 = mightFail() catch 0;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 8 semantic properties match expected values
  ```

### `test_Task144_CatchExpressionDetection_Chained`
- **Primary File**: `tests/test_task_144_detection.cpp`
- **Verification Points**: 6 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn mightFail() !i32 { return 42; }
  ```
  ```zig
fn doTest() void {
  ```
  ```zig
var x: i32 = mightFail() catch mightFail() catch 0;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_Task144_OrelseExpressionDetection`
- **Primary File**: `tests/test_task_144_detection.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn maybeInt() ?i32 { return 42; }
  ```
  ```zig
fn doTest() void {
  ```
  ```zig
var x: i32 = maybeInt() orelse 0;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_TypeChecker_VarDecl_Inferred_Crash`
- **Primary File**: `tests/type_checker_inference_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking
- **Test Input (Zig)**:
  ```zig
fn myTest() void { var x = 42; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeChecker_VarDecl_Inferred_Loop`
- **Primary File**: `tests/type_checker_inference_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking
- **Test Input (Zig)**:
  ```zig
fn myTest() void { var i = 0; while (i < 10) { i = i + 1; } }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeChecker_VarDecl_Inferred_Multiple`
- **Primary File**: `tests/type_checker_inference_tests.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking
- **Test Input (Zig)**:
  ```zig
fn myTest() void { var x = 1; var y = 2.0; var z = true; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_C89Rejection_NestedTryInMemberAccess`
- **Primary File**: `tests/test_c89_rejection.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn getS() !S { return S { .f = 42 }; }
  ```
  ```zig
fn main() !void { var x = (try getS()).f; return; }
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_C89Rejection_NestedTryInStructInitializer`
- **Primary File**: `tests/test_c89_rejection.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn f() !i32 { return 42; }
  ```
  ```zig
fn main() !void { var s = S { .f = try f() }; return; }
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_C89Rejection_NestedTryInArrayAccess`
- **Primary File**: `tests/test_c89_rejection.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn getArr() ![5]i32 { return undefined; }
  ```
  ```zig
fn main() !void { var x = (try getArr())[0]; return; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_ExtractionAnalysis_StackStrategy`
- **Primary File**: `tests/extraction_analysis_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn f() !i32 { return 42; }
  ```
  ```zig
fn main() void { try f(); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_ExtractionAnalysis_ArenaStrategy_LargePayload`
- **Primary File**: `tests/extraction_analysis_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn f() !S { return undefined; }
  ```
  ```zig
fn main() void { try f(); }
  ```
  ```zig
const S = struct { a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64, i: i64 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_ExtractionAnalysis_ArenaStrategy_DeepNesting`
- **Primary File**: `tests/extraction_analysis_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn f() !S { return undefined; }
  ```
  ```zig
fn main() void {
  ```
  ```zig
const S = struct { a: i32, b: i32, c: i32, d: i32, e: i32, f: i32, g: i32, h: i32, i: i32, j: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_ExtractionAnalysis_OutParamStrategy`
- **Primary File**: `tests/extraction_analysis_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn f() !S { return undefined; }
  ```
  ```zig
fn main() void { try f(); }
  ```
  ```zig
const S = struct { a: [1025]u8 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_ExtractionAnalysis_ArenaStrategy_Alignment`
- **Primary File**: `tests/extraction_analysis_tests.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn f() !i64 { return 42; }
  ```
  ```zig
fn main() void { try f(); }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_ExtractionAnalysis_Linking`
- **Primary File**: `tests/extraction_analysis_tests.cpp`
- **Verification Points**: 5 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn f() !i32 { return 42; }
  ```
  ```zig
fn main() void {
  ```
  ```zig
var x = try f();
  ```
  ```zig
var y = f() catch 0;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_Task147_ErrDeferRejection`
- **Primary File**: `tests/test_c89_rejection.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn f() void { errdefer {}; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_Task147_AnyErrorRejection`
- **Primary File**: `tests/test_c89_rejection.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
var x: anyerror = 0;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_Task149_ErrorHandlingFeaturesCatalogued`
- **Primary File**: `tests/test_task_149.cpp`
- **Verification Points**: 6 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn my_test() !i32 {
  ```
  ```zig
fn foo() !i32 { return 0; }
  ```
  ```zig
fn bar() !i32 { return 0; }
  ```
  ```zig
fn maybe() ?i32 { return 0; }
  ```
  ```zig
const x = try foo();
  ```
  ```zig
const y = bar() catch 0;
  ```
  ```zig
const z = maybe() orelse 0;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_Task150_ErrorTypeEliminatedFromFinalTypeSystem`
- **Primary File**: `tests/test_task_150.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn main() void { var x: !i32 = 0; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_C89Rejection_GenericFnDecl_ShouldBeRejected`
- **Primary File**: `tests/test_task_150_extra.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo(comptime T: i32) void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_C89Rejection_DeferAndErrDefer`
- **Primary File**: `tests/test_c89_rejection.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn f() void { defer {}; errdefer {}; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_C89Rejection_ErrorTypeInParam_ShouldBeRejected`
- **Primary File**: `tests/test_task_150_extra.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo(x: !i32) void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_Task150_MoreComprehensiveElimination`
- **Primary File**: `tests/test_task_150_extra.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo(x: i32) !i32 { if (x > 0) { return x; } return 0; }
  ```
  ```zig
fn main() !void {
  ```
  ```zig
var res: i32 = foo(1) catch 0;
  ```
  ```zig
var res2: i32 = 0;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_C89Support_ArraySliceExpression`
- **Primary File**: `tests/test_task_150_extra.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn main() void { var a: [10]i32 = undefined; var b = a[0..5]; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_Task151_ErrorTypeRejection`
- **Primary File**: `tests/test_task_151.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn test_func() !i32 { return 0; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_Task151_OptionalTypeRejection`
- **Primary File**: `tests/test_task_151.cpp`
- **Verification Points**: 1 assertions
- **Test Input (Zig)**:
  ```zig
fn test_func(x: ?i32) void { _ = x; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_FunctionNameCollisionSameScope`
- **Primary File**: `tests/test_name_collision.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo() void {}
  ```
  ```zig
fn foo() i32 { return 0; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_FunctionVariableCollisionSameScope`
- **Primary File**: `tests/test_name_collision.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo() void {}
  ```
  ```zig
var foo: i32 = 5;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_ShadowingAllowed`
- **Primary File**: `tests/test_name_collision.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn foo() void {}
  ```
  ```zig
fn bar() void {
  ```
  ```zig
const foo: i32 = 5;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_SignatureAnalysisNonC89Types`
- **Primary File**: `tests/test_signature_analyzer.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass, Source Loading
- **Test Input (Zig)**:
  ```zig
fn bad2(a: !i32) void {}      // Error union - should reject
  ```
  ```zig
fn good(a: i32) void {}       // Simple type - should pass
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  3. Execute Source Loading phase
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_SignatureAnalysis_ManyParams_Accepted`
- **Primary File**: `tests/test_signature_analyzer.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass, Source Loading
- **Test Input (Zig)**:
  ```zig
fn manyParams(a: i32, b: i32, c: i32, d: i32, e: i32) void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_SignatureAnalysis_ExtremeParams_Accepted`
- **Primary File**: `tests/test_signature_analyzer.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass, Source Loading
- **Test Input (Zig)**:
  ```zig
fn extremeParams(p1: i32, p2: i32, p3: i32, p4: i32, p5: i32, p6: i32, p7: i32, p8: i32,
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_SignatureAnalysisMultiLevelPointers`
- **Primary File**: `tests/test_signature_analyzer.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass, Source Loading
- **Test Input (Zig)**:
  ```zig
fn multiPtr(a: * * i32) void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_SignatureAnalysisTypeAliasResolution`
- **Primary File**: `tests/test_signature_analyzer.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass, Source Loading
- **Test Input (Zig)**:
  ```zig
fn good(a: MyInt) void {}  // Should pass - resolves to i32
  ```
  ```zig
const MyInt = i32;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_SignatureAnalysisArrayParameterWarning`
- **Primary File**: `tests/test_signature_analyzer.cpp`
- **Verification Points**: 4 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass, Source Loading
- **Test Input (Zig)**:
  ```zig
fn arrayParam(a: [10]i32) void {}
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  3. Execute Source Loading phase
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_SignatureAnalysisReturnTypeRejection`
- **Primary File**: `tests/test_signature_analyzer.cpp`
- **Verification Points**: 3 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Static Analysis Pass, Source Loading
- **Test Input (Zig)**:
  ```zig
fn badRet() !i32 { return 0; }
  ```
  ```zig
fn goodRet() i32 { return 0; }
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Static Analysis Pass phase
  3. Execute Source Loading phase
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_TypeChecker_BreakContinue_InLoop`
- **Primary File**: `tests/test_break_continue.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn test_func() void {
  ```
  ```zig
var arr: [5]i32 = undefined;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_BreakOutsideLoop_Error`
- **Primary File**: `tests/test_break_continue.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn test_func() void {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeChecker_ContinueOutsideLoop_Error`
- **Primary File**: `tests/test_break_continue.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn test_func() void {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeChecker_BreakInDefer_Error`
- **Primary File**: `tests/test_break_continue.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn test_func() void {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_TypeChecker_BreakInSwitchInLoop`
- **Primary File**: `tests/test_break_continue.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
fn test_func(x: i32) void {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_ManyParams_FunctionPointer`
- **Primary File**: `tests/test_many_params.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
const fp: fn(i32, i32, i32, i32, i32, i32, i32, i32,
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_TypeChecker_ManyParams_GenericInstantiation`
- **Primary File**: `tests/test_many_params.cpp`
- **Verification Points**: 4 assertions
- **Operations**: Syntactic Parsing, Semantic Type Checking, Source Loading
- **Test Input (Zig)**:
  ```zig
fn generic(comptime T: type,
  ```
  ```zig
fn main() void {
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  3. Execute Semantic Type Checking phase
  3. Execute Source Loading phase
  4. Verify that the 4 semantic properties match expected values
  ```
