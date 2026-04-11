# Z98 Test Suite Status Report - Forward (Phase 3 Compatibility)

## Summary

| Metric | 32-bit Value | 64-bit Value |
|--------|--------------|--------------|
| Total Test Batches | 78 | 78 |
| Passed Batches | 74 | - |
| Failed Batches | 4 | - |
| Total Pass Rate | 94.9% | - |

*Note: 32-bit values reflect the status using -m32. Lisp and repro tests were excluded from this run.*

---

## Progress Report (32-bit)

- **Phase 3/4 Compatibility**: **VERIFIED**. The compiler successfully generates C89-compliant code that compiles with `gcc -m32 -std=c89 -pedantic`.
- **Example Programs**: **PASSED**. All major examples (hello, prime, heapsort, mandelbrot, etc.) are fully functional.
- **Tuple Support**: **IMPLEMENTED**. Integration tests and examples confirm tuple literal and type support are working as intended.

---

## Detailed Breakdown of Failures (32-bit)

### 1. Batch 1 (Lexer)
- **Status**: FAIL
- **Test**: `Lexer_FloatNoIntegerPart`
- **Reason**: Regression in Lexer.
- **Details**: The test expects `.123` to return `TOKEN_ERROR` (float must have leading digit). However, it now returns `TOKEN_DOT` (116). This is likely due to the introduction of tuple/member access syntax where a dot can start an expression.

### 2. Batch 5 (Static Analysis)
- **Status**: FAIL
- **Test**: `DoubleFree_TransferTracking`
- **Reason**: Regression in `DoubleFreeAnalyzer`.
- **Details**: The analyzer fails to recognize ownership transfer to an unknown function (`unknown_func(p)`), incorrectly reporting a memory leak at the end of the scope.

### 3. Batch 44 (Codegen/Tuples)
- **Status**: FAIL
- **Test**: `Task225_2_PrintLowering`
- **Reason**: Test expectation mismatch (Tuple Lowering).
- **Details**: The test expects direct calls like `__bootstrap_print_int(x)`. However, since `print` takes `anytype`, the argument is now correctly lowered as a tuple member: `__bootstrap_print_int(__tmp_tup_X_Y.field0)`.

### 4. Batch 63 (Parser/Tuples)
- **Status**: FAIL
- **Test**: `Struct_NakedTagsRejection`
- **Reason**: Test expectation mismatch (Tuple Support).
- **Details**: The test expects the parser to abort when encountering a naked identifier `A,` in a struct. With the introduction of tuples, this is now valid syntax for a tuple element (anonymous field) of type `void`.

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
| `lzw` | PASS | Built successfully (execution skipped as it's interactive) |
| `mandelbrot` | PASS | |

---

## Deep Investigation of Failures

### 1. Lexer Leading Dot
The lexer's handling of `.` has been broadened to support `t.0` and `.A`. The failure in `Lexer_FloatNoIntegerPart` confirms that `.123` is no longer caught as a malformed float at the lexer level but is instead treated as a `TOKEN_DOT` followed by an integer.

### 2. Ownership Transfer
In `DoubleFreeAnalyzer::isOwnershipTransferCall`, the compiler uses a whitelist (arena_create, deep_copy, transfer_ownership). The test `DoubleFree_TransferTracking` uses `unknown_func`, which is not on the whitelist, hence the leak report. This reflects a "strict" policy that might need adjustment or test update.

### 3. Print Lowering and Tuples
The `PrintLowering` implementation now leverages the tuple infrastructure for `anytype` arguments. This ensures consistency but requires updating older tests that expect "flat" argument lowering.

### 4. Struct vs. Tuple Ambiguity
The parser now treats `A,` in a struct as a tuple element. Batch 63's rejection test is now obsolete as the grammar has been expanded to support mixed named/anonymous fields in aggregates.
