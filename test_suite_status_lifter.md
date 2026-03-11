# Test Suite Status Report - ControlFlowLifter Integration

## Summary
The test suite currently has **2 regressions** in the bootstrap compiler's static analysis and type checking. Additionally, most examples are functional, but one fails C89 validation due to incorrect variadic function emission.

| Batch | Status | Failing Tests |
|-------|--------|---------------|
| 1-4   | PASSED | None |
| 5     | FAILED | `DoubleFree_SwitchBothFree` |
| 6-50  | PASSED | None |
| 51    | FAILED | `test_UnionCapture_InvalidIntegerCase` |
| 52-60 | PASSED | None |

---

## Detailed Analysis of Current Regressions

### 1. Batch 5: Double Free Analysis Regression
*   **Test**: `DoubleFree_SwitchBothFree` in `tests/test_task_130_switch.cpp`
*   **Diagnosis**: The `DoubleFreeAnalyzer` does not yet support `NODE_SWITCH_STMT`. When the compiler was updated to distinguish between switch expressions and switch statements (Milestone 9), the analyzer was not updated to visit `NODE_SWITCH_STMT`. As a result, it treats switch statements as no-ops, failing to track allocations freed within their branches.
*   **Impact**: Potential double-frees or leaks within switch statements are not detected by the bootstrap compiler.

### 2. Batch 51: Union Capture Error Message Mismatch
*   **Test**: `test_UnionCapture_InvalidIntegerCase` in `tests/integration/task9_9_union_capture_tests.cpp`
*   **Diagnosis**: The test expects a specific error message ("Capture requires a tag name case item") when a capture is used with a non-tag case (like `1 => |val|`). However, the `TypeChecker` currently reports "Switch case type mismatch" first because it validates the item type against the union's tag type before checking the capture requirements.
*   **Impact**: Purely diagnostic; the error is still caught, but the hint is less specific than intended.

### 3. Batch 60: C89 Validation [KNOWN ISSUE]
*   **Status**: PASSED (Compiler phase only)
*   **Note**: Integration tests in this batch verify range-based switch AST and C emission. However, they currently fail the C89 validation phase of the test harness because the generated code contains calls to `extern` functions for which the test harness does not provide mock definitions. This is a known limitation of the current test infrastructure.

---

## Examples Status Report

| Example | zig0 Status | C89 Status (GCC -std=c89 -pedantic) | Runtime Status | Notes |
|---------|-------------|-----------------------------------|----------------|-------|
| hello | PASSED | PASSED | PASSED | - |
| prime | PASSED | PASSED | PASSED | - |
| fibonacci | PASSED | PASSED | PASSED | - |
| heapsort | PASSED | PASSED | PASSED | zig0 warnings for potential null deref |
| quicksort | PASSED | PASSED | PASSED | zig0 warnings for potential null deref |
| sort_strings | PASSED | PASSED | PASSED | zig0 warnings for potential null deref |
| func_ptr_return | PASSED | PASSED | PASSED | - |
| days_in_month | PASSED | **FAILED** | N/A | Generated C has invalid syntax for variadic `print` |

### Diagnosis: `days_in_month` failure
The example `days_in_month` fails C89 compilation because `zig0` emits an invalid C prototype for the `print` function.
Zig source: `pub extern fn print(fmt: *const u8, args: anytype) void;`
Generated C: `extern void print(unsigned char const* fmt, ... args);`
C89 does not allow naming the variadic arguments (`... args`). It should simply be `...`.

---

## Recommendations
1.  **Update DoubleFreeAnalyzer**: Implement `visitSwitchStmt` to restore path-aware analysis for switch statements.
2.  **Refine TypeChecker Switch Validation**: Reorder checks in `validateSwitch` to prioritize capture-specific errors over general type mismatches to restore the expected error message.
3.  **Fix Variadic Codegen**: Update `C89Emitter::emitDeclarator` to avoid emitting a name for `anytype` parameters (the `...` in C).
