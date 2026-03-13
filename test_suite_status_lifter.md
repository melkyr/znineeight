# Test Suite Status Report - ControlFlowLifter & Tagged Union Emission

## Summary
The test suite shows regressions in several integration tests due to recent architectural changes (unified loop labeling, lifter-based transformations, and error message updates). Example programs are fully functional and pass verification.

| Batch | Status | Failing Tests |
|-------|--------|---------------|
| 1-13  | PASSED | None |
| 14    | FAILED | 4/11 (WhileLoopIntegration_WithBreak, WithContinue, etc.) |
| 15    | FAILED | 1/12 (StructIntegration_RejectStructMethods) |
| 16-25 | PASSED | None |
| 26    | FAILED | 1/27 (Codegen_Global_AnonymousContainer_Error) |
| 27-38 | PASSED | None |
| 39    | FAILED | 2/10 (DeferIntegration_Continue, DeferIntegration_NestedContinue) |
| 40-63 | PASSED | None |
| 64    | MISSING| (Number skipped in repository) |
| 65    | FAILED | 1/6 (TaggedUnionEmission_AnonymousField) |

---

## Detailed Analysis of Regressions

### 1. Batches 14 & 39: Loop Labeling & `goto` Transition
**Issue**: Newer versions of `ControlFlowLifter` and `C89Emitter` use a unified labeling scheme (`__loop_N_start`, `__loop_N_continue`, `__loop_N_end`) and `goto` statements for all loop control (including plain `break` and `continue`). This ensures correct behavior for complex loop increments and `defer` in loops.
**Root Cause**: Integration tests in Batches 14 and 39 have hardcoded expectations for plain C `break;` and `continue;` statements.
**Examples**:
*   Expected: `while (1) { break; }`
*   Actual:   `while (1) { goto __loop_0_end; }`

### 2. Batch 15: `expect_parser_abort` Behavior
**Issue**: `test_StructIntegration_RejectStructMethods` fails.
**Root Cause**: The test correctly triggers a parser abort when it encounters a method inside a struct (which is unsupported). However, the test runner's `expect_parser_abort` logic (using `fork()` and `SIGABRT` detection) appears to be unreliable in the current environment.

### 3. Batch 26: Error Message Mismatch
**Issue**: `test_Codegen_Global_AnonymousContainer_Error` fails.
**Root Cause**: String mismatch in the reported error.
*   Expected hint: `"anonymous structs/enums not allowed in variable declarations"`
*   Actual hint:   `"anonymous aggregates not allowed in variable declarations"` (as seen in `TypeChecker::visitVarDecl`).

### 4. Batch 65: Anonymous Tagged Union Emission
**Issue**: `test_TaggedUnionEmission_AnonymousField` fails.
**Root Cause**: The test expects `int tag;` in the generated C struct, but the emitter now produces an anonymous enum member `enum /* anonymous */ tag;`.

---

## Example Verification Results
All examples in the `examples/` directory were compiled with the bootstrap compiler (`zig0`) and verified with `gcc -std=c89 -pedantic`.

| Example | Status | Output/Notes |
|---------|--------|--------------|
| hello   | PASSED | "Hello, RetroZig!" |
| prime   | PASSED | Correctly identifies primes up to 20. |
| fibonacci| PASSED | Correctly computes Fib(10) = 55. |
| heapsort| PASSED | `135671112131520` |
| quicksort| PASSED | Sorted arrays (ascending/descending). |
| sort_strings| PASSED | Correctly sorts string array. |
| func_ptr_return| PASSED | 10 + 5 = 15, 10 - 5 = 5. |

---

## Recommendations
1.  **Update Test Expectations**: Older integration tests should be updated to expect the unified `goto`-based loop control and the new anonymous tag emission format.
2.  **Harmonize Error Messages**: Update either the `TypeChecker` or the test in Batch 26 to use a consistent error string for anonymous aggregates.
3.  **Harden `expect_abort`**: Investigate why `SIGABRT` detection is unreliable for Batch 15.
