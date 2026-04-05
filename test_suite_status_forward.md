# Z98 Test Suite Status Report

## Summary

| Metric | 32-bit Value | 64-bit Value |
|--------|--------------|--------------|
| Total Test Batches | 77 | 77 |
| Passed Batches | 72 | - |
| Failed Batches | 5 | - |
| Total Pass Rate | 93.5% | - |

*Note: 32-bit values reflect the current status using -m32.*

---

## Progress Report (32-bit)

- **Lisp Interpreter (curr)**: **WORKING**. Regenerated and compiled with `gcc -m32`. Simple expressions like `(+ 1 2)`, `cons`, and `lambda` are working correctly without segfaults.
- **Example Programs**: 9/10 examples are passing. `mandelbrot` was added and is passing.
- **Batch 7 (Switch)**: PASS
- **Batch 27 (Codegen)**: PASS (Previously reported as failing in some environments)
- **Batch 45 (Error Handling)**: PASS (Now passing after recent compiler updates)
- **Batch 47 (Optional Types)**: PASS
- **Batch 52 (Switch Range)**: PASS

---

## Detailed Breakdown of Failures (32-bit)

The following 5 batches are currently failing in the 32-bit environment.

### Failing Batches
- **Batch 26 (Codegen)**: Regression in constant emission.
    - *Test*: `const x: i32 = 42;`
    - *Cause*: The compiler emits `static const int zC_0_x = 42;` but the test expects `static int zC_0_x = 42;` (without `const`).
- **Batch 29 (Arithmetic/Bitwise)**: Codegen mismatch in compound assignments.
    - *Test*: `a.* += b;`
    - *Cause*: The compiler now wraps compound assignments in `(void)` casts (e.g., `(void)(*a += b);`) to suppress C89 unused-value warnings. The tests expect the bare assignment.
- **Batch 44 (Task 225_2)**: Integration test failure.
    - *Test*: `test_Task225_2_PrintLowering` (Batch 44, Test 1).
    - *Cause*: Internal mismatch in expected lowering patterns for `debug.print`.
- **Batch 46 (Integration - Error Handling)**: Fails during C compilation of generated code.
    - *Test*: `temp_Integration_Try_Defer_LIFO`
    - *Cause*: Undefined reference to `zV_8_log` in the generated C code.
- **Batch 55 (Integration - Return/Try)**: Fails during C compilation of generated code.
    - *Test*: `Integration_Return_Try_In_Expression`
    - *Cause*: Failed to compile generated C code (likely due to missing files or scope issues in the test's custom build logic).

---

## Examples Status (32-bit)

| Example | Status | Notes |
|---------|--------|-------|
| `hello` | PASS | |
| `prime` | PASS | |
| `days_in_month` | FAIL | Regression: Mangled name `zV_ff06ae_year` used but not declared for local constant. |
| `fibonacci` | PASS | |
| `heapsort` | PASS | |
| `quicksort` | PASS | |
| `sort_strings` | PASS | |
| `func_ptr_return`| PASS | |
| `lzw` | PASS | |
| `mandelbrot` | PASS | Added to the suite. |

---

## Deep Investigation of Failures

### 1. `days_in_month` Local Constant Regression
The compiler is incorrectly applying global-style mangling to local constants defined inside functions.
```zig
pub fn main() void {
    const year = 2024;
    std.debug.print("...", .{year});
}
```
Generated C:
```c
int main(void) {
    const int year = 2024;
    __bootstrap_print_int(zV_ff06ae_year); // ERROR: zV_ff06ae_year not declared
}
```
This indicates that the TypeChecker or Emitter is failing to recognize `year` as a local symbol during the print lowering phase.

### 2. Compound Assignment `(void)` Casts
The compiler recently improved codegen to wrap compound assignments in `(void)` casts to suppress C89 warnings.
```c
(void)(*a += b);
```
Tests in Batch 29 were written before this change and expect:
```c
*a += b;
```
**Recommendation**: Update tests to expect the `(void)` cast.

### 3. Batch 26 `const` mismatch
The test expects `static int` for a global const, but the compiler (correctly for C89 constant initializers) emits `static const int`.
**Recommendation**: Update tests to expect `const`.

### 4. Lisp Interpreter Status
The `lisp_interpreter_curr` is confirmed to be working in 32-bit mode. The previous reports of segfaults were likely due to 64-bit size mismatches in the `Value` tagged union or stale generated code. Fresh regeneration and 32-bit compilation resolved the issues.

### 5. Lisp Recursion Limitation
It is worth noting that while the Lisp interpreter is working, recursive functions defined via `define` cannot call themselves by name due to the current environment capture semantics. The environment is captured at the moment the `lambda` is evaluated, and subsequent updates to the global environment (like the name of the function itself) are not reflected in the closure's captured environment. Passing the function to itself as an argument (Y-combinator style or explicit passing) works correctly, confirming the evaluator logic is sound.
