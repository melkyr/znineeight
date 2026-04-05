# Z98 Test Suite Status Report

## Summary

| Metric | 32-bit Value | 64-bit Value |
|--------|--------------|--------------|
| Total Test Batches | 77 | 77 |
| Passed Batches | 73 | - |
| Failed Batches | 4 | - |
| Total Pass Rate | 94.8% | - |

*Note: 32-bit values reflect the current status using -m32.*

---

## Progress Report (32-bit)

- **Lisp Interpreter (curr)**: **WORKING**. Regenerated and compiled with `gcc -m32`. Simple expressions like `(+ 1 2)`, `cons`, and `lambda` are working correctly without segfaults.
- **Example Programs**: 10/10 examples are passing. All examples (hello, prime, days_in_month, fibonacci, heapsort, quicksort, sort_strings, func_ptr_return, lzw, mandelbrot) are now passing in 32-bit mode.
- **Batch 7 (Switch)**: PASS
- **Batch 27 (Codegen)**: PASS
- **Batch 44 (Task 225_2)**: PASS
- **Batch 45 (Error Handling)**: PASS
- **Batch 46 (Integration - Error Handling)**: PASS
- **Batch 47 (Optional Types)**: PASS
- **Batch 52 (Switch Range)**: PASS
- **Batch 55 (Integration - Return/Try)**: PASS

---

## Detailed Breakdown of Failures (32-bit)

The following 4 batches are currently failing in the 32-bit environment due to intentional codegen improvements that have not yet been reflected in test expectations.

### Failing Batches
- **Batch 26 (Codegen)**: Improvement in constant emission.
    - *Test*: `const x: i32 = 42;`
    - *Cause*: The compiler now correctly emits `static const int zC_0_x = 42;` for Zig `const` globals. The test expects `static int zC_0_x = 42;`.
    - *Status*: Improvement.
- **Batch 29 (Arithmetic/Bitwise)**: Codegen improvement for C89 compliance.
    - *Test*: `a.* += b;`
    - *Cause*: The compiler now wraps compound assignments in `(void)` casts (e.g., `(void)(*a += b);`) to suppress C89 unused-value warnings. The tests expect the bare assignment.
    - *Status*: Improvement.
- **Batch 41 (For Loops)**: Codegen improvement for C89 compliance.
    - *Test*: Various for-loop tests.
    - *Cause*: The compiler now uses `makeTempVarForType` for internal loop variables (e.g., `for_idx`, `for_len`) and ensures declarations are at the top of the block. The tests expect older, harder-to-match patterns (using `#` wildcard or specific names like `__for_len_1`).
    - *Status*: Improvement.
- **Batch _bugs (Codegen)**: Codegen improvement for C89 compliance.
    - *Test*: `Codegen_ForPtrToArray` (Test 3).
    - *Cause*: Similar to Batch 41, the test expects `__for_len_1 = 5;` but the compiler now emits `for_len = 5;` using standardized temporary variable names.
    - *Status*: Improvement.

---

## Examples Status (32-bit)

| Example | Status | Notes |
|---------|--------|-------|
| `hello` | PASS | |
| `prime` | PASS | |
| `days_in_month` | PASS | Resolved: Local constant mangling issue fixed. |
| `fibonacci` | PASS | |
| `heapsort` | PASS | |
| `quicksort` | PASS | |
| `sort_strings` | PASS | |
| `func_ptr_return`| PASS | |
| `lzw` | PASS | |
| `mandelbrot` | PASS | |

---

## Deep Investigation of Failures

### 1. `days_in_month` Local Constant Regression (RESOLVED)
The previously reported issue where `days_in_month` failed due to local constant mangling is resolved. Local variables and constants now correctly use their original names in the generated C code when possible, avoiding undefined symbol errors.

### 2. Compound Assignment `(void)` Casts
The compiler improved codegen to wrap compound assignments in `(void)` casts to suppress C89 warnings.
```c
(void)(*a += b);
```
Tests in Batch 29 still expect the bare assignment. This is an improvement in the compiler that requires a test suite update.

### 3. C89 Temporary Variable Standardization
Recent refactorings to `C89Emitter` introduced `makeTempVarForType` to ensure all compiler-generated temporary variables (like those in `for` loops and `switch` captures) follow C89 rules (declared at the top of the block). This changed names like `__for_len_1` to `for_len`.
Batches 41 and `_bugs` contain tests that rely on string matching for these specific temporary names.
**Recommendation**: Update these tests to use more robust matching patterns or expect the new standardized names.

### 4. Global `const` Emission
Zig `const` globals are now emitted as `static const` in C when they have constant initializers.
Batch 26 expects `static int`, which is less strictly correct for a Zig `const`.
**Recommendation**: Update Batch 26 to expect `static const`.
