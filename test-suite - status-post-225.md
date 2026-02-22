# Test Suite Status Post-Task 225

**Date**: 2026-02-22 01:12:18 UTC
**Status**: 42/44 Batches Passing, 7/8 Examples Passing

## Summary
The test suite and examples were fully audited following the implementation of Task 225 (Switch/If expressions and Print lowering). While most components remain stable, two specific regressions and one instability were identified.

## Test Batches Status

| Batch | Status | Cause |
|-------|--------|-------|
| 1-20  | ✓ PASS | |
| 21    | ✗ FAIL | Segmentation fault in `test_SizeOf_Array`. |
| 22-31 | ✓ PASS | |
| 32    | ✗ FAIL | `std.debug.print` argument count mismatch in `test_EndToEnd_HelloWorld`. |
| 33-44 | ✓ PASS | |

### Batch 21: Segmentation Fault
- **Failing Test**: `test_SizeOf_Array` (Index 2).
- **Investigation**:
  - The test passes when run in isolation.
  - It segfaults when run as the 3rd test in a sequence (e.g., after `test_SizeOf_Primitive` and `test_SizeOf_Struct`).
  - Valgrind indicates "Conditional jump or move depends on uninitialised value(s)" in `TypeChecker::catalogGenericInstantiation`.
  - **Suspected Cause**: Memory corruption or uninitialized variable in the generic instantiation cataloging logic, which is triggered by `@sizeOf` being treated as a generic builtin.

### Batch 32: Print Regression
- **Failing Test**: `test_EndToEnd_HelloWorld`.
- **Error**: `greetings.zig:3:15: error: std.debug.print expects 2 arguments`
- **Root Cause**: Task 225.2 changed `std.debug.print` to require a tuple literal as the second argument. The test source in `end_to_end_hello.cpp` still uses the old 1-argument signature.
- **Action Needed**: Update `tests/integration/end_to_end_hello.cpp` to use `std.debug.print("...", .{})`.

## Examples Status

| Example | Status | Notes |
|---------|--------|-------|
| hello   | ✗ FAIL | Regression: `std.debug.print` needs 2 arguments. |
| prime   | ✓ PASS | Correctly calculates and prints 2357. |
| fibonacci | ✓ PASS | Correctly calculates Fib(10) = 55. |
| heapsort | ✓ PASS | Correctly sorts array (Advanced). |
| quicksort | ✓ PASS | Correctly sorts array using function pointers (Advanced). |
| sort_strings | ✓ PASS | Correctly sorts strings (Advanced). |
| func_ptr_return | ✓ PASS | Correctly handles functions returning function pointers. |
| days_in_month | ✓ PASS | Correctly calculates leap year days (Advanced). |

### Regression: `examples/hello`
- **Error**: Same as Batch 32.
- **Action Needed**: Update `examples/hello/greetings.zig` to use `std.debug.print("Hello, world!\n", .{})`.

## Recommendations
1. **Fix Print Regression**: Update both the integration test and the `hello` example to match the new `std.debug.print` signature.
2. **Investigate Batch 21**: Deep dive into `TypeChecker::catalogGenericInstantiation` to ensure all fields of `GenericParamInfo` and `GenericInstantiation` are properly initialized.
3. **Continuous Integration**: Ensure `days_in_month` is added to `examples/run_all_examples.sh`.
