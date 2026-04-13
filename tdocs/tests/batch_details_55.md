# Z98 Test Batch 55 Technical Specification

## High-Level Objective
AST ControlFlowLifter: Validates the mandatory transformation pass that hoists expression-based control flow (if/switch/try/catch) into statement blocks to satisfy C89 constraints.

This test batch comprises 9 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_ASTLifter_BasicIf`
- **Implementation Source**: `tests/integration/ast_lifter_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
extern fn foo(arg: i32) void;
fn test_lifter_1() void {
    foo(if (true) 1 else 2);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `unit.getErrorHandler` is false
  3. Validate that `mod not equals null` is satisfied
  4. Assert that `NODE_FN_DECL` matches `fn_node.type`
  5. Assert that `stmts.length` matches `3`
  6. Assert that `stmt1.type` matches `NODE_VAR_DECL`
  7. Validate that `strstr(stmt1.as.var_decl.name, "__tmp_if_"` is satisfied
  8. Assert that `stmt2.type` matches `NODE_IF_STMT`
  9. Assert that `stmt3.type` matches `NODE_EXPRESSION_STMT`
  10. Validate that `call not equals (void*` is satisfied
  11. Assert that `call.type` matches `NODE_FUNCTION_CALL`
  12. Validate that `call.as.function_call not equals null` is satisfied
  13. Validate that `call.as.function_call.args not equals null` is satisfied
  14. Assert that `call.as.function_call.args.length` matches `1`
  15. Assert that `arg.type` matches `NODE_IDENTIFIER`
  ```

### `test_ASTLifter_Nested`
- **Implementation Source**: `tests/integration/ast_lifter_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
extern fn foo(arg: i32) void;
extern fn bar(arg: i32) !i32;
fn test_lifter_2() !void {
    foo(try bar(if (true) 1 else 2));
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `unit.getErrorHandler` is false
  2. Assert that `NODE_FN_DECL` matches `fn_node.type`
  3. Assert that `stmts.length` matches `7`
  4. Assert that `*stmts` matches `NODE_VAR_DECL`
  5. Validate that `strstr((*stmts` is satisfied
  6. Assert that `*stmts` matches `NODE_IF_STMT`
  7. Assert that `*stmts` matches `NODE_EXPRESSION_STMT`
  ```

### `test_ASTLifter_ComplexAssignment`
- **Implementation Source**: `tests/integration/ast_lifter_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
extern fn getIndex() usize;
fn test_lifter_3(arr: []i32) void {
    arr[getIndex()] = if (true) 1 else 2;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `unit.getErrorHandler` is false
  2. Validate that `fn_node not equals null` is satisfied
  3. Assert that `NODE_FN_DECL` matches `fn_node.type`
  4. Assert that `stmts.length` matches `3`
  5. Assert that `*stmts` matches `NODE_VAR_DECL`
  6. Validate that `strstr((*stmts` is satisfied
  7. Assert that `*stmts` matches `NODE_IF_STMT`
  8. Assert that `*stmts` matches `NODE_EXPRESSION_STMT`
  9. Validate that `assign not equals (void*` is satisfied
  10. Assert that `assign.type` matches `NODE_ASSIGNMENT`
  11. Assert that `assign.as.assignment.rvalue.type` matches `NODE_IDENTIFIER`
  ```

### `test_ASTLifter_CompoundAssignment`
- **Implementation Source**: `tests/integration/ast_lifter_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn test_lifter_4(x: *i32) void {
    x.* += if (true) 1 else 2;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `unit.getErrorHandler` is false
  2. Validate that `fn_node not equals null` is satisfied
  3. Assert that `NODE_FN_DECL` matches `fn_node.type`
  4. Assert that `stmts.length` matches `3`
  5. Assert that `*stmts` matches `NODE_VAR_DECL`
  6. Assert that `*stmts` matches `NODE_IF_STMT`
  7. Assert that `*stmts` matches `NODE_EXPRESSION_STMT`
  8. Validate that `assign not equals (void*` is satisfied
  9. Assert that `assign.type` matches `NODE_COMPOUND_ASSIGNMENT`
  10. Assert that `assign.as.compound_assignment.rvalue.type` matches `NODE_IDENTIFIER`
  ```

### `test_ASTLifter_Unified`
- **Implementation Source**: `tests/integration/unified_lifting_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
extern fn foo(arg: i32) void;
extern fn bar(arg: i32) !i32;
fn test_lifter_unified(c: bool, opt: ?i32) void {
    foo(if (c) 1 else 2);
    foo(switch (c) { true => 1, else => 2 });
    _ = bar(10) catch 0;
    foo(opt orelse 30);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `unit.getErrorHandler` is false
  3. Assert that `14` matches `stmts.length`
  4. Validate that `strstr((*stmts` is satisfied
  5. Assert that `NODE_IF_STMT` matches `*stmts)[1].type`
  6. Assert that `NODE_SWITCH_STMT` matches `*stmts)[4].type`
  ```

### `test_ASTLifter_MemoryStressTest`
- **Implementation Source**: `tests/integration/unified_lifting_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn test_stress(c: bool) i32 {
    return
  ```
  ```zig
if (c) 1 else (
  ```
  ```zig
;
    for (int i = 0; i < depth; ++i) {
        source +=
  ```
  ```zig
);
    mod->ast_root = ast;

    size_t after_parse = arena.getOffset();

    TypeChecker checker(unit);
    checker.check(ast);
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    size_t after_typecheck = arena.getOffset();

    ControlFlowLifter lifter(&arena, &interner, &unit.getErrorHandler());
    lifter.lift(&unit);

    size_t after_lift = arena.getOffset();
    size_t peak = arena.getPeakAllocated();

    // Assertions
    ASSERT_TRUE(peak < 16 * 1024 * 1024); // Must be within 16MB budget

... (truncated)
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Ensure that `unit.getErrorHandler` is false
  3. Validate that `peak < 16 * 1024 * 1024` is satisfied
  4. Validate that `growth_lift < total_before_lift * 5` is satisfied
  ```

### `test_Integration_Return_Try_I32`
- **Implementation Source**: `tests/integration/task3_try_return_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const std = @import(\
  ```
  ```zig
fn mayFail(fail: bool) !i32 {
  ```
  ```zig
if (fail) { return error.Oops; }
  ```
  ```zig
return 42;
  ```
  ```zig
fn wrapper(fail: bool) !i32 {
  ```
  ```zig
return try mayFail(fail);
  ```
  ```zig
pub fn main() void {
  ```
  ```zig
const res1 = wrapper(false) catch 0;
  ```
  ```zig
const res2 = wrapper(true) catch 99;
  ```
  ```zig
;
    return run_integration_test_task3(source,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Integration_Return_Try_I32 and validate component behavior
  ```

### `test_Integration_Return_Try_Void`
- **Implementation Source**: `tests/integration/task3_try_return_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const std = @import(\
  ```
  ```zig
fn mayFail(fail: bool) !void {
  ```
  ```zig
if (fail) { return error.Oops; }
  ```
  ```zig
fn wrapper(fail: bool) !void {
  ```
  ```zig
return try mayFail(fail);
  ```
  ```zig
pub fn main() void {
  ```
  ```zig
var ok: i32 = 0;
  ```
  ```zig
wrapper(false) catch {};
  ```
  ```zig
var err: i32 = 0;
  ```
  ```zig
wrapper(true) catch {};
  ```
  ```zig
;
    return run_integration_test_task3(source,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Integration_Return_Try_Void and validate component behavior
  ```

### `test_Integration_Return_Try_In_Expression`
- **Implementation Source**: `tests/integration/task3_try_return_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const std = @import(\
  ```
  ```zig
fn mayFail() !i32 {
  ```
  ```zig
return 10;
  ```
  ```zig
fn wrapper() !i32 {
  ```
  ```zig
// This should NOT use the special wrapping because try is not a direct child of return
  ```
  ```zig
return (try mayFail()) + 5;
  ```
  ```zig
pub fn main() void {
  ```
  ```zig
const res = wrapper() catch 0;
  ```
  ```zig
;
    return run_integration_test_task3(source,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Integration_Return_Try_In_Expression and validate component behavior
  ```
