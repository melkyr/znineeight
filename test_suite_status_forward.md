# Z98 Test Suite Status Report

## Summary

| Metric | 32-bit Value | 64-bit Value |
|--------|--------------|--------------|
| Total Test Batches | 77 | 77 |
| Passed Batches | 73 | - |
| Failed Batches | 4 | - |
| Total Pass Rate | 94.8% | - |

*Note: 32-bit values reflect the current status using `-m32`.*

---

## Progress Report (32-bit)

Since the last report, there has been significant progress in fixing regressions. The following batches, previously reported as failing, are **now passing**:
- **Batch 7 (Switch)**: PASS
- **Batch 9 (Pointers)**: PASS
- **Batch 27 (Codegen)**: PASS
- **Batch 32 (End-to-End)**: PASS
- **Batch 41 (For Loops)**: PASS
- **Batch 47 (Optional Types)**: PASS
- **Batch 52 (Switch Range)**: PASS
- **Batch 57 (Anonymous Unions)**: PASS
- **Batch 67 (Tagged Union Tag)**: PASS

---

## Detailed Breakdown of Failures (32-bit)

The following 4 batches are currently failing in the 32-bit environment.

### Failing Batches
- **Batch 29 (Arithmetic/Bitwise)**: Codegen mismatch in compound assignments. The compiler now wraps compound assignments in `(void)` casts (e.g., `(void)(*a += b);`) to suppress C89 unused-value warnings. The tests expect the bare assignment.
- **Batch 45 (Error Handling)**: Fails C89 validation due to `const` reassignment. Zig `const` variables initialized with fallible calls (which are lifted in C) generate code like `const int a; a = val;`, which is invalid C89.
- **Batch 46 (Integration - Error Handling)**: Fails C89 validation for the same reason as Batch 45 (const reassignment in lifted constructs).
- **Batch 55 (Integration - Return/Try)**: Fails C89 validation for the same reason as Batch 45 (const reassignment in lifted constructs).

---

## Examples Status (32-bit)

| Example | Status | Notes |
|---------|--------|-------|
| `hello` | PASS | |
| `prime` | PASS | |
| `days_in_month` | FAIL | C89 error: assignment of read-only variable (`const` lift) |
| `fibonacci` | FAIL | C89 error: assignment of read-only variable (`const` lift) |
| `heapsort` | FAIL | C89 error: assignment of read-only variable (`const` lift) |
| `quicksort` | FAIL | C89 error: assignment of read-only variable (`const` lift) |
| `sort_strings` | PASS | |
| `func_ptr_return`| FAIL | C89 error: assignment of read-only variable (`const` lift) |
| `lzw` | FAIL | C89 error: assignment of read-only variable (`const` lift) |

---

## Deep Investigation of Failures

### 1. The `const` Lift Problem
In Zig, `const` means the value is immutable after initialization. Many Zig constructs like `switch` expressions, `if` expressions, and error handling (`try`, `catch`) are "lifted" by the compiler into statement blocks in C89.

If a Zig variable is declared as `const` and initialized with one of these expressions, the compiler generates a C declaration followed by an assignment within a block.
For example:
```zig
const d = switch (month) { ... };
```
Generates (roughly):
```c
const int d;
{
    int __tmp;
    switch (month) { ... __tmp = 31; ... }
    d = __tmp; // Error: assignment of read-only variable 'd'
}
```
In C89, a `const` variable **must** be initialized at the point of declaration. Since the value is only known after the lifted block executes, the current codegen is invalid C.

**Insight:** Since the Zig TypeChecker already enforces immutability for `const` variables, the compiler should safely omit the `const` keyword in C for any local variable that requires lifting (i.e., any variable where the initialization is not a simple C-compatible constant expression).

### 2. Compound Assignment `(void)` Casts
The compiler recently improved codegen to wrap compound assignments in `(void)` casts to suppress C89 warnings about unused values.
```c
(void)(*a += b);
```
Tests in Batch 29 were written before this change and expect:
```c
*a += b;
```
**Insight:** This is a legitimate improvement in the compiler. The test suite should be updated to match this new standard.

---

## Test Environment Improvements

1.  **Added `src/include/zig_special_types.h`**: Standard location for compiler-generated special types.
2.  **Validator Flag Update**: Modified `tests/c89_validation/gcc_validator.cpp` to include the `-m32` flag.
3.  **Topological Sorting (Batch 71 Fix)**: Batch 71 now passes due to the implementation of Kahn's algorithm for dependency ordering in `MetadataPreparationPass`.
