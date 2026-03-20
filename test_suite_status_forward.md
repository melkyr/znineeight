# Test Suite Status Report

## Summary Table (Default Run - 64-bit host, no -m32)

| Batch | Status | Details |
|-------|--------|---------|
| Batch 1 | ✓ Passed | 81/81 tests passed |
| Batch 2 | ✓ Passed | 114/114 tests passed |
| Batch 3 | ✗ Failed | 114/115 tests passed (Leak detected in compound assignment) |
| Batch 4 | ✓ Passed | 37/37 tests passed |
| Batch 5 | ✗ Failed | 16/34 tests passed (Multiple integration failures) |
| Batch 6 | ✓ Passed | 33/33 tests passed |
| Batch 7 | ✓ Passed | 51/51 tests passed |
| Batch 7_debug | ✓ Passed | 51/51 tests passed |
| Batch 8 | ✓ Passed | 5/5 tests passed |
| Batch 9 | ✓ Passed | 16/16 tests passed |
| Batch 9a | ✓ Passed | 5/5 tests passed |
| Batch 9b | ✓ Passed | 5/5 tests passed |
| Batch 9c | ✓ Passed | 13/13 tests passed |
| Batch 10 | ✓ Passed | 7/7 tests passed |
| Batch 11 | ✓ Passed | 30/30 tests passed (Compilation issue FIXED) |
| Batch 12 | ✓ Passed | 89/89 tests passed |
| Batch 13 | ✓ Passed | 13/13 tests passed |
| Batch 14 | ✓ Passed | 11/11 tests passed |
| Batch 15 | ✓ Passed | 12/12 tests passed |
| Batch 16 | ✓ Passed | 15/15 tests passed |
| Batch 17 | ✓ Passed | 6/6 tests passed |
| Batch 18 | ✓ Passed | 18/18 tests passed |
| Batch 19 | ✗ Failed | 24/31 tests passed |
| Batch 20 | ✓ Passed | 21/21 tests passed |
| Batch 21 | ✓ Passed | 15/15 tests passed |
| Batch 22 | ✓ Passed | 3/3 tests passed |
| Batch 23 | ✓ Passed | 6/6 tests passed |
| Batch 24 | ✓ Passed | 8/8 tests passed |
| Batch 25 | ✓ Passed | 5/5 tests passed |
| Batch 26 | ✓ Passed | 27/27 tests passed |
| Batch 27 | ✓ Passed | 21/21 tests passed |
| Batch 28 | ✓ Passed | 4/4 tests passed |
| Batch 29 | ✓ Passed | 15/15 tests passed |
| Batch 30 | ✓ Passed | 11/11 tests passed |
| Batch 31 | ✗ Failed | Compilation error in utils.zig |
| Batch 32 | ✓ Passed | 2/2 tests passed |
| Batch 33 | ✗ Failed | 2/3 tests passed (Import resolution issue) |
| Batch 34 | ✓ Passed | 5/5 tests passed |
| Batch 35 | ✓ Passed | 5/5 tests passed |
| Batch 36 | ✓ Passed | 6/6 tests passed |
| Batch 37 | ✓ Passed | 9/9 tests passed |
| Batch 38 | ✓ Passed | 19/19 tests passed |
| Batch 39 | ✓ Passed | 10/10 tests passed |
| Batch 40 | ✓ Passed | 11/11 tests passed |
| Batch 41 | ✓ Passed | 5/5 tests passed |
| Batch 42 | ✓ Passed | 7/7 tests passed |
| Batch 43 | ✓ Passed | 8/8 tests passed |
| Batch 44 | ✓ Passed | 3/3 tests passed |
| Batch 45 | ✓ Passed | 12/12 tests passed |
| Batch 46 | ✓ Passed | 11/11 tests passed |
| Batch 47 | ✓ Passed | 9/9 tests passed |
| Batch 48 | ✗ Failed | 6/8 tests passed |
| Batch 49 | ✓ Passed | 1/1 tests passed |
| Batch 50 | ✓ Passed | 5/5 tests passed |
| Batch 51 | ✓ Passed | 4/4 tests passed |
| Batch 52 | ✓ Passed | 3/3 tests passed |
| Batch 53 | ✗ Failed | 3/4 tests passed (Recursive composite mismatch) |
| Batch 54 | ✓ Passed | 3/3 tests passed |
| Batch 55 | ✓ Passed | 9/9 tests passed |
| Batch 56 | ✓ Passed | 3/3 tests passed |
| Batch 57 | ✓ Passed | 3/3 tests passed |
| Batch 58 | ✓ Passed | 13/13 tests passed |
| Batch 60 | ✓ Passed | 24/24 tests passed |
| Batch 61 | ✓ Passed | 13/13 tests passed |
| Batch 62 | ✓ Passed | 1/1 tests passed |
| Batch 63 | ✓ Passed | 4/4 tests passed |
| Batch 65 | ✓ Passed | 6/6 tests passed |
| Batch 66 | ✓ Passed | 4/4 tests passed |
| Batch 67 | ✓ Passed | 3/3 tests passed |
| Batch 68 | ✓ Passed | 5/5 tests passed |
| Batch 69 | ✓ Passed | 2/2 tests passed |
| Batch 70 | ✓ Passed | 5/5 tests passed |
| Batch 71 | ✓ Passed | 1/1 tests passed |
| Batch 72 | ✓ Passed | 5/5 tests passed |
| Batch 73 | ✗ Failed | 4/5 tests passed (createEnumType NULL name) |
| Batch 74 | ✓ Passed | 4/4 tests passed |
| Batch _bugs | ✓ Passed | 5/5 tests passed |

## Observations & Issues

### Legacy Test Compilation Fixes
Fixed `tests/test_milestone4_name_mangling.cpp` to use the updated `CompilationUnit`-based API for type creation. This enabled Batch 11 to compile and pass successfully.

### 32-bit Compatibility (-m32)
Tests were also run using `-m32` on the Linux host after installing `gcc-multilib`.
- **Batch 2 Regression**: One failure appeared in Batch 2 (`test_parser_expressions.cpp:268`) due to the `ASSERT_EQ` macro in `test_framework.hpp` being unsuitable for floating-point comparisons (it casts to `long`).
- **Batch 3 Regression**: An additional failure appeared in Batch 3 compared to the non-m32 run.
- All other failures remained consistent between modes.

### Outstanding Failures
- **Batch 31**: Fails due to an error in `utils.zig:1:11` during compilation.
- **Batch 53**: `PlaceholderHardening_RecursiveComposites` fails with a children_type base mismatch.
- **Batch 73**: `createEnumType` debug warning triggered due to NULL name.

## Examples Verification

All examples in the `examples/` directory were compiled and executed successfully in both 64-bit and 32-bit modes.

| Example | Status | Output Snippet |
|---------|--------|----------------|
| hello | ✓ Passed | `Hello, world!` |
| prime | ✓ Passed | `2357` |
| fibonacci | ✓ Passed | `55` |
| heapsort | ✓ Passed | `135671112131520` |
| quicksort | ✓ Passed | `Sorted (ascending): 1 1 2 3 3 4 5 5 6 9` |
| sort_strings | ✓ Passed | `Sorted strings: apple banana cherry date` |
| func_ptr_return | ✓ Passed | `10 + 5 = 15`, `10 - 5 = 5` |
| days_in_month | ✓ Passed | `Month 2: 29 days` (2024 leap year) |
