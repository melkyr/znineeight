# Z98 Test Suite Status Report

## Summary

| Metric | 32-bit Value | 64-bit Value |
|--------|--------------|--------------|
| Total Test Batches | 77 | 77 |
| Passed Batches | 77 | - |
| Failed Batches | 0 | - |
| Total Pass Rate | 100% | - |

*Note: 32-bit values reflect the current status using -m32.*

---

## Progress Report (32-bit)

- **Lisp Interpreter (curr)**: **WORKING**. Regenerated and compiled with `gcc -m32`. Simple expressions like `(+ 1 2)`, `cons`, and `lambda` are working correctly without segfaults.
- **Example Programs**: 10/10 examples are passing. All examples (hello, prime, days_in_month, fibonacci, heapsort, quicksort, sort_strings, func_ptr_return, lzw, mandelbrot) are passing in 32-bit mode.
- **All Test Batches**: 100% Pass Rate (77/77).

---

## Detailed Breakdown of Failures (32-bit)

All batches are now passing. Recent intentional codegen improvements have been reflected in the test suite:

- **Batch 26 (Codegen)**: Updated to expect explicit `const` for constant variables.
- **Batch 29 (Arithmetic/Bitwise)**: Updated to expect `(void)` casts for compound assignment statements.
- **Batch 41 (For Loops)**: Updated to expect standardized C89-compliant temporary variable names (`for_iter`, `for_idx`, `for_len`).
- **Batch _bugs (Codegen)**: Updated to expect standardized temporary variable names.

---

## Examples Status (32-bit)

| Example | Status | Notes |
|---------|--------|-------|
| `hello` | PASS | |
| `prime` | PASS | |
| `days_in_month` | PASS | |
| `fibonacci` | PASS | |
| `heapsort` | PASS | |
| `quicksort` | PASS | |
| `sort_strings` | PASS | |
| `func_ptr_return`| PASS | |
| `lzw` | PASS | |
| `mandelbrot` | PASS | |

---

## Deep Investigation of Failures (Resolved)

### 1. `days_in_month` Local Constant Regression
Resolved. Local variables and constants now correctly use their original names in the generated C code when possible.

### 2. Compound Assignment `(void)` Casts
The compiler now wraps compound assignments in `(void)` casts to suppress C89 warnings.
```c
(void)(*a += b);
```
Tests in Batch 29 have been updated to reflect this improvement.

### 3. C89 Temporary Variable Standardization
Compiler-generated temporary variables (like those in `for` loops) now follow C89 rules (declared at the top of the block) and use standardized names (`for_idx`, `for_len`, etc.).
Tests in Batches 41 and `_bugs` have been updated to match these patterns.

### 4. Global `const` Emission
Zig `const` globals are now emitted as `static const` in C when they have constant initializers.
Batch 26 has been updated to expect `static const`.
