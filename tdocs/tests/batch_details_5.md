# Z98 Test Batch 5 Technical Specification

## High-Level Objective
Double Free and Memory Leak Analyzer: Data-flow analysis tracking allocation states across branches and defer scopes.

This test batch comprises 34 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_DoubleFree_SimpleDoubleFree`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {
    var p: *u8 = arena_alloc_default(100u);
    arena_free(p);
    arena_free(p);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `has_double_free` is satisfied
  ```

### `test_DoubleFree_BasicTracking`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {
    var p: *u8 = arena_alloc_default(100u);
    arena_free(p);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `has_relevant_diagnostics` is false
  ```

### `test_DoubleFree_UninitializedFree`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {
    var p: *u8;
    arena_free(p);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `has_warning` is satisfied
  ```

### `test_DoubleFree_MemoryLeak`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {
    var p: *u8 = arena_alloc_default(100u);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `has_leak` is satisfied
  ```

### `test_DoubleFree_DeferDoubleFree`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {
    var p: *u8 = arena_alloc_default(100u);
    defer { arena_free(p); }
    arena_free(p);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `has_double_free` is satisfied
  ```

### `test_DoubleFree_ReassignmentLeak`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `has_leak` is satisfied
  ```

### `test_DoubleFree_NullReassignmentLeak`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `has_leak` is satisfied
  ```

### `test_DoubleFree_ReturnExempt`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> *u8 {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
  ```zig
return p;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `has_leak` is false
  ```

### `test_DoubleFree_SwitchAnalysis`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func(x: i32) -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
  ```zig
switch (x) {
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `has_double_free` is false
  ```

### `test_DoubleFree_TryAnalysis`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn fallible() -> void {}
fn my_func() -> void {
    var p: *u8 = arena_alloc_default(100u);
    try fallible();
    arena_free(p);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  ```

### `test_DoubleFree_TryAnalysisComplex`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn fallible() -> void {}
  ```
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
  ```zig
try fallible();
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `has_double_free` is false
  ```

### `test_DoubleFree_CatchAnalysis`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn fallible() -> *u8 { return null; }
fn my_func() -> void {
    var p: *u8 = fallible() catch arena_alloc_default(100u);
    arena_free(p);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `has_uninit_warning` is false
  ```

### `test_DoubleFree_BinaryOpAnalysis`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u) + 0u;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `has_uninit_warning` is false
  ```

### `test_DoubleFree_LocationInLeakWarning`
- **Implementation Source**: `tests/test_double_free_locations.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
  ```zig
;

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool found_leak_with_loc = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_MEMORY_LEAK) {
            // Check if message contains allocation info.
            // We expect something like
  ```
  ```zig
if (contains(warnings[i].message,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `found_leak_with_loc` is satisfied
  ```

### `test_DoubleFree_LocationInReassignmentLeak`
- **Implementation Source**: `tests/test_double_free_locations.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
  ```zig
;

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool found_leak_with_loc = false;
    const DynamicArray<WarningReport>& warnings = ctx.getCompilationUnit().getErrorHandler().getWarnings();
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == WARN_MEMORY_LEAK) {
            if (contains(warnings[i].message,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `found_leak_with_loc` is satisfied
  ```

### `test_DoubleFree_LocationInDoubleFreeError`
- **Implementation Source**: `tests/test_double_free_locations.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
  ```zig
;

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool found_double_free_with_loc = false;
    const DynamicArray<ErrorReport>& errors = ctx.getCompilationUnit().getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_DOUBLE_FREE) {
            // Check if hint contains allocation AND first free info.
            if (errors[i].hint &&
                contains(errors[i].hint,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `found_double_free_with_loc` is satisfied
  ```

### `test_DoubleFree_TransferTracking`
- **Implementation Source**: `tests/test_double_free_task_129.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
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
  ```zig
// Use whitelisted function for transfer
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `has_leak` is false
  3. Validate that `has_transfer_warning` is satisfied
  ```

### `test_DoubleFree_DeferContextInError`
- **Implementation Source**: `tests/test_double_free_task_129.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
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
  ```zig
;

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool found_double_free_with_defer = false;
    const DynamicArray<ErrorReport>& errors = ctx.getCompilationUnit().getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_DOUBLE_FREE) {
            // Check in hint
            if (errors[i].hint &&
                contains_substring(errors[i].hint,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `found_double_free_with_defer` is satisfied
  ```

### `test_DoubleFree_ErrdeferContextInError`
- **Implementation Source**: `tests/test_double_free_task_129.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
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
  ```zig
;

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(ctx.getCompilationUnit());
    type_checker.check(ast);

    DoubleFreeAnalyzer analyzer(ctx.getCompilationUnit());
    analyzer.analyze(ast);

    bool found_double_free_with_errdefer = false;
    const DynamicArray<ErrorReport>& errors = ctx.getCompilationUnit().getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_DOUBLE_FREE) {
            // Check in hint
            if (errors[i].hint &&
                contains_substring(errors[i].hint,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `found_double_free_with_errdefer` is satisfied
  ```

### `test_DoubleFree_IfElseBranching`
- **Implementation Source**: `tests/test_double_free_path_aware.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func(x: i32) -> void {
    var p: *u8 = arena_alloc_default(100u);
    if (x > 0) {
        arena_free(p);
    } else {
        // p NOT freed
    }
    // After if/else, p should be AS_UNKNOWN
    arena_free(p);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `has_double_free` is false
  ```

### `test_DoubleFree_IfElseBothFree`
- **Implementation Source**: `tests/test_double_free_path_aware.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func(x: i32) -> void {
    var p: *u8 = arena_alloc_default(100u);
    if (x > 0) {
        arena_free(p);
    } else {
        arena_free(p);
    }
    // After if/else, p should be AS_FREED
    arena_free(p);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `has_double_free` is satisfied
  ```

### `test_DoubleFree_WhileConservative`
- **Implementation Source**: `tests/test_double_free_path_aware.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func(x: i32) -> void {
    var p: *u8 = arena_alloc_default(100u);
    while (x > 0) {
        arena_free(p);
        p = arena_alloc_default(200u);
    }
    // p is AS_UNKNOWN here
    arena_free(p);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `has_double_free` is false
  ```

### `test_DoubleFree_SwitchPathAware`
- **Implementation Source**: `tests/test_task_130_switch.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func(x: i32) -> void {
    var p: *u8 = arena_alloc_default(100u);
    switch (x) {
        1 => arena_free(p),
        else => {},
    }
    // After switch, p should be AS_UNKNOWN
    arena_free(p); // Should NOT be a definite double free error
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `ctx.getCompilationUnit` is false
  3. Ensure that `has_double_free` is false
  ```

### `test_DoubleFree_SwitchBothFree`
- **Implementation Source**: `tests/test_task_130_switch.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func(x: i32) -> void {
    var p: *u8 = arena_alloc_default(100u);
    switch (x) {
        1 => arena_free(p),
        else => arena_free(p),
    }
    // After switch, p should be AS_FREED
    arena_free(p); // Should be a double free error
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `ctx.getCompilationUnit` is false
  3. Validate that `has_double_free` is satisfied
  ```

### `test_DoubleFree_TryPathAware`
- **Implementation Source**: `tests/test_task_130_error_handling.cpp`
- **Sub-system Coverage**: Static Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn mightFail() -> i32 {}
fn my_func(x: i32) -> void {
    var p: *u8 = arena_alloc_default(100u);
    try mightFail();
    // After try, p should be AS_UNKNOWN
    arena_free(p); // Should NOT be a definite double free error
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `has_double_free` is false
  ```

### `test_DoubleFree_CatchPathAware`
- **Implementation Source**: `tests/test_task_130_error_handling.cpp`
- **Sub-system Coverage**: Static Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn mightFail() -> i32 {}
fn my_func() -> void {
    var p: *u8 = arena_alloc_default(100u);
    // Use a simple expression for catch body
    mightFail() catch arena_free(p);
    // On success path, p is still AS_ALLOCATED
    // On failure path, p is AS_FREED
    // Merged state should be AS_UNKNOWN
    arena_free(p); // Should NOT be a definite double free error
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `has_double_free` is false
  ```

### `test_DoubleFree_OrelsePathAware`
- **Implementation Source**: `tests/test_task_130_error_handling.cpp`
- **Sub-system Coverage**: Static Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn maybeAlloc() -> *u8 { return null; }
fn my_func() -> void {
    var p: *u8 = arena_alloc_default(100u);
    // Use a simple expression for orelse body
    var q: *u8 = maybeAlloc() orelse arena_alloc_default(10u);
    // In both paths p is still AS_ALLOCATED
    arena_free(p);
    arena_free(q);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `has_double_free` is false
  ```

### `test_DoubleFree_LoopConservativeVerification`
- **Implementation Source**: `tests/test_task_130_loops.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func(x: i32) -> void {
    var p: *u8 = arena_alloc_default(100u);
    while (x > 0) {
        arena_free(p);
        p = arena_alloc_default(200u);
    }
    // p should be AS_UNKNOWN here because it was modified in the loop
    arena_free(p); // Should NOT be a definite double free error
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `ctx.getCompilationUnit` is false
  3. Ensure that `has_double_free` is false
  ```

### `test_DoubleFree_NestedDeferScopes`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `has_double_free` is satisfied
  ```

### `test_DoubleFree_PointerAliasing`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void {
  ```
  ```zig
var p: *u8 = arena_alloc_default(100u);
  ```
  ```zig
var q: *u8 = p;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `has_double_free` is false
  3. Validate that `has_uninit_free` is satisfied
  ```

### `test_DoubleFree_DeferInLoop`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func(x: i32) -> void {
    var p: *u8 = arena_alloc_default(100u);
    var i: i32 = 0;
    while (i < x) {
        defer { arena_free(p); }
        i = i + 1;
    }
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  ```

### `test_DoubleFree_ConditionalAllocUnconditionalFree`
- **Implementation Source**: `tests/double_free_analysis_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func(x: i32) -> void {
  ```
  ```zig
var p: *u8 = null;
  ```
  ```zig
if (x > 0) {
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `has_warning` is false
  ```

### `test_Integration_FullPipeline`
- **Implementation Source**: `tests/integration_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> void {
    var p: *u8 = arena_alloc_default(100u);
    arena_free(p);
    arena_free(p);  // Double free
    var q: *i32 = null;
    q.* = 10;       // Null dereference
}
fn leak_test() -> *i32 {
    var x: i32 = 42;
    return &x;      // Lifetime violation
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Validate that `has_double_free` is satisfied
  3. Validate that `has_null_deref` is satisfied
  4. Validate that `has_lifetime_violation` is satisfied
  ```

### `test_Integration_CorrectUsage`
- **Implementation Source**: `tests/integration_tests.cpp`
- **Sub-system Coverage**: Static Analysis, Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> void {
    var p: *u8 = arena_alloc_default(100u);
    arena_free(p);  // Correct usage
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `unit.getErrorHandler` is false
  ```
