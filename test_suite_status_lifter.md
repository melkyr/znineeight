# Test Suite Status Report - ControlFlowLifter Integration

## Summary
The integration of the unified `ControlFlowLifter` has introduced regressions in **6 out of 56** test batches. While the core lifting logic is functional, there are critical issues regarding symbol registration for temporary variables and outdated expectations in the integration test suite.

| Batch | Status | Failing Tests |
|-------|--------|---------------|
| 1-42  | PASSED | None |
| 43    | PASSED | None |
| 44    | PARTIAL| `Task225_2_PrintLowering` (Print lowering regression) |
| 45    | FAILED | `ErrorHandling_C89Execution` |
| 46    | FAILED | 5 Integration Tests (Try/Catch/Defer) |
| 47    | FAILED | `OptionalOrelse`, `OptionalOrelseBlock` |
| 48-54 | PASSED | None |
| 55    | PASSED | None |
| 56    | PASSED | None |

---

## Detailed Failure Analysis

### 1. Missing Variable Declarations (Batches 45, 46, 47) [PARTIALLY RESOLVED]
**Symptoms**: Generated C code fails to compile due to undeclared identifiers (e.g., `__tmp_catch_res_4`).
**Note**: Mangling issue (prefixing `__` with `z_`) has been RESOLVED (Task 9.16).
**Remaining Issues**:
*   The `ControlFlowLifter` generates temporary names (e.g., `__tmp_if_1`) using the `interner` but does not create or register `Symbol` objects for them.
*   The `C89Emitter::emitLocalVarDecl` returns early if `decl->symbol` is `NULL`, meaning the `typedef` and variable declaration are never emitted.
*   Even though mangling is now bypassed for `__` identifiers, the variables are still not being declared in the C code because they lack `Symbol` entries in the local table.

### 2. Statement Count Mismatch (Batch 55) [RESOLVED]
**Resolution**:
*   Updated `tests/integration/ast_lifter_tests.cpp` to reflect the "full lowering" strategy of the `ControlFlowLifter`.
*   The lifter now splits expression-valued control flow into a `NODE_VAR_DECL`, a lowering statement (e.g., `NODE_IF_STMT`), and the original statement updated to use the temporary.
*   Expectations adjusted to correctly count and verify these additional nodes.

### 3. Codegen Pattern Mismatch (Batch 43, 44) [RESOLVED]
**Symptoms**: Tests fail to find expected strings like `__return_val = 1;` or `__bootstrap_panic`.
**Root Cause**:
1. `TestCompilationUnit::performTestPipeline` did not call the `ControlFlowLifter`. Since `C89Emitter` no longer performs ad-hoc lifting, control-flow expressions (if/switch/try/catch/orelse) were not emitted at all, causing expected strings like `__bootstrap_panic` (from `unreachable`) to be missing.
2. Even when lifted, the generated code pattern changes. `return if (b) 1 else 2` becomes a statement `if (b) { __tmp_if_1 = 1; } else { __tmp_if_1 = 2; }` followed by `return __tmp_if_1;`. The tests previously expected direct assignments to `__return_val` or literals, which are no longer present in the same form.

**Resolution**:
*   Updated `TestCompilationUnit::performTestPipeline` in `tests/integration/test_compilation_unit.hpp` to include the `ControlFlowLifter` pass.
*   Updated integration test expectations in `tests/integration/task225_2_tests.cpp` and `tests/integration/switch_noreturn_tests.cpp` to match lifted patterns.
*   Updated `MockC89Emitter` in `tests/integration/mock_emitter.hpp` to support `NODE_SWITCH_STMT`.

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
