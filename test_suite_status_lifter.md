# Test Suite Status Report - ControlFlowLifter Integration

## Summary
The integration of the unified `ControlFlowLifter` has introduced regressions in **6 out of 56** test batches. While the core lifting logic is functional, there are critical issues regarding symbol registration for temporary variables and outdated expectations in the integration test suite.

| Batch | Status | Failing Tests |
|-------|--------|---------------|
| 1-42  | PASSED | None |
| 43    | FAILED | `SwitchNoreturn_RealCodegen` |
| 44    | FAILED | `Task225_2_BracelessIfExpr`, `Task225_2_PrintLowering` |
| 45    | FAILED | `ErrorHandling_C89Execution` |
| 46    | FAILED | 5 Integration Tests (Try/Catch/Defer) |
| 47    | FAILED | `OptionalOrelse`, `OptionalOrelseBlock`, `OptionalOrelseUnreachable` |
| 48-54 | PASSED | None |
| 55    | FAILED | `ASTLifter_BasicIf`, `ASTLifter_Nested`, `ASTLifter_ComplexAssignment`, `ASTLifter_CompoundAssignment` |
| 56    | PASSED | None |

---

## Detailed Failure Analysis

### 1. Missing Variable Declarations (Batches 45, 46, 47)
**Symptoms**: Generated C code fails to compile due to undeclared identifiers (e.g., `z__tmp_catch_res_4`).
**Possible Cause**:
*   The `ControlFlowLifter` generates temporary names (e.g., `__tmp_if_1`) using the `interner` but does not create or register `Symbol` objects for them.
*   The `C89Emitter::emitLocalVarDecl` returns early if `decl->symbol` is `NULL`, meaning the `typedef` and variable declaration are never emitted.
*   Simultaneously, `C89Emitter::emitExpression` mangles these identifiers via `getC89GlobalName` (adding `z_` prefixes), while the declaration (if it were emitted) would use `var_alloc_`, leading to a name mismatch even if declared.

### 2. Statement Count Mismatch (Batch 55)
**Symptoms**:
*   `ASTLifter_BasicIf`: Expected 3 but got 2 (tests/integration/ast_lifter_tests.cpp:58)
*   `ASTLifter_Nested`: Expected 7 but got 3 (tests/integration/ast_lifter_tests.cpp:123)
*   `ASTLifter_ComplexAssignment`: Expected 3 but got 2 (tests/integration/ast_lifter_tests.cpp:173)
*   `ASTLifter_CompoundAssignment`: Expected 3 but got 2 (tests/integration/ast_lifter_tests.cpp:222)
**Possible Cause**:
*   The lifter tests in `tests/integration/ast_lifter_tests.cpp` were written when the lifter only produced a `NODE_VAR_DECL` with an initializer.
*   The current `ControlFlowLifter` performs a "full lowering" strategy, splitting constructs into multiple statements (e.g., a declaration followed by an `if` statement for an `if` expression).
*   Example: `foo(if (b) 1 else 2)` now becomes 3 statements (Decl, If-Stmt, Call) instead of the expected 2.

### 3. Codegen Pattern Mismatch (Batch 43, 44)
**Symptoms**: Tests fail to find expected strings like `__return_val = 1;` or `__bootstrap_panic`.
**Possible Cause**:
*   **Batch 44**: `Task225_2_BracelessIfExpr` expects a direct assignment to `__return_val`. Because the `if` expression is lifted, the assignment is now indirect (`__tmp_if_1 = 1; __return_val = __tmp_if_1;`).
*   **Batch 43**: Lifting a switch containing an `unreachable` prong might be causing the `NODE_UNREACHABLE` to be wrapped or transformed in a way that the `C89Emitter` no longer emits the expected `__bootstrap_panic` call in the specific context the test searches for.

### 4. Print Lowering Regression (Batch 44)
**Symptoms**: `Task225_2_PrintLowering` fails.
**Possible Cause**:
*   The lifter transforms the AST before the `C89Emitter` performs its ad-hoc lowering for `std.debug.print`.
*   If the format string or arguments are wrapped in new nodes (like `NODE_PAREN_EXPR` or lifted into temps), the emitter's pattern matching for `print` may fail.

---

## Recommendations
1.  **Symbol Registration**: Update `ControlFlowLifter` to register generated temporary variables in the local symbol table to ensure they are properly declared and mangled by the `C89Emitter`.
2.  **Update Test Expectations**: Update Batch 55 and Batch 44 integration tests to reflect the new lowered AST structure and C code patterns produced by the unified lifting pass.
3.  **Sanitize Mangling**: Ensure internal compiler-generated identifiers (prefixed with `__`) bypass the standard `z_` mangling in `C89Emitter`.
