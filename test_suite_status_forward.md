# Z98 Test Suite Status Report - Forward (Post-Milestone 11 Stability)

## Summary

| Metric | 32-bit Value | 64-bit Value |
|--------|--------------|--------------|
| Total Test Batches | 81 | 81 |
| Passed Batches | 71 | - |
| Failed Batches | 10 | - |
| Total Pass Rate | 87.6% | - |

*Note: 32-bit values reflect the status using -m32 after recent compiler updates. Analysis of failures included below.*

---

## Progress Report (32-bit)

- **Compiler Stability**: **VERIFIED**. `zig0` compiles properly with `g++ -std=c++98`.
- **Test Suite Integrity**: **PARTIAL**. 71 out of 81 test batches pass. Failures include regressions in tuple handling and integration test environment issues.
- **Name Mangling**: **VERIFIED**. Recent changes to implement deterministic cross-module symbol hashing are stable.
- **Example Programs**: **VERIFIED**. `rogue_mud`, `func_ptr_return`, `days_in_month`, `lisp_interpreter_curr`, and `mandelbrot` compile and execute correctly under `-m32` and C89 constraints.
- **CVariableAllocator**: **UPDATED**. The truncation limit was increased from 31 to 63 characters to support longer mangled names, causing an expectation mismatch in Batch 23.
- **Stage 1 (sf/) Compilation**: **STABLE**. `sf/src/main.zig` no longer segfaults during compilation, although it currently reports semantic errors due to incomplete stage1 implementation.

---

## Failure Analysis (32-bit)

### 1. Batch 23 (CVariableAllocator)
- **Status**: **FAIL**
- **Test**: `test_CVariableAllocator_Truncation`
- **Cause**: The test expects identifiers to be truncated at 31 characters. However, the compiler now supports up to 63 characters.
- **Result**: **TEST OUTDATED**. The compiler behavior is intentional.

### 2. Batch 31 & 32 (Integration Segfault)
- **Status**: **FAIL (Segfault)**
- **Cause**: Segmentation fault during integration test execution. Likely related to C linkage or symbol resolution in the generated code for multi-file examples.
- **Result**: **REGRESSION/BUG**. Needs investigation into the C backend's handling of cross-module symbols in these specific cases.

### 3. Batch 46 & 55 (Tuple Handling)
- **Status**: **FAIL**
- **Cause**: `std.debug.print` reports type mismatches for tuples.
- **Result**: **REGRESSION**. Recent changes in tuple lowering or type checking for anonymous struct initializers have introduced regressions in how `std.debug.print` arguments are validated.

### 4. Batch 60 & 65 (Test Runner Conflict)
- **Status**: **COMPILE FAIL**
- **Cause**: Redefinition of `main` because multiple files with `main()` are included in the same batch runner.
- **Result**: **ENVIRONMENT ISSUE**. Non-regression; the test runner configuration is flawed for these batches.

### 5. Batch 75 (Missing Entry Point)
- **Status**: **NOT FOUND**
- **Cause**: The file `tests/main_batch75.cpp` is missing. However, sub-batches `75a`, `75b`, `75c`, and `75d` are present and PASS.
- **Result**: **TEST ABSENT**.

### 6. Batch _bugs
- **Status**: **FAIL (7/8 Passed)**
- **Result**: One regression in bug-fix verification suite.

---

## Detailed Breakdown of Resolved Failures (32-bit)

### 1. Batch 44 (Print Lowering)
- **Status**: **PASS**
- **Analysis**: The compiler correctly uses tuples for argument passing.

### 2. Batch 75d (Memory Limit)
- **Status**: **PASS**
- **Analysis**: Lexer fix for float literals prevents infinite loops on tokens like `.0`.

### 3. Batch 1 (Lexer)
- **Status**: **PASS**
- **Analysis**: Z98 correctly lexes `.123` as `TOKEN_DOT` followed by an integer.

---

## Examples Status (32-bit)

| Example | Status | Compilation | Correctness | C89 Warnings | Zig0 Warnings |
|---------|--------|-------------|-------------|--------------|---------------|
| `hello` | PASS | OK | OK | 0 | 2 |
| `prime` | PASS | OK | OK | 0 | 1 |
| `days_in_month` | PASS | OK | OK | 0 | 1 |
| `fibonacci` | PASS | OK | OK | 0 | 1 |
| `heapsort` | PASS | OK | OK | 6 | 21 |
| `quicksort` | PASS | OK | OK | 0 | 11 |
| `sort_strings` | PASS | OK | OK | 0 | 14 |
| `func_ptr_return`| PASS | OK | OK | 0 | 0 |
| `lzw` | PASS | OK | OK | 0 | 13 |
| `mandelbrot` | PASS | OK | OK | 0 | 5 |
| `lisp_interpreter_curr` | PASS | OK | OK | 12 | 14 |
| `game_of_life` | PASS | OK | OK | 0 | 4 |
| `mud_server` | PASS | OK | LINKED | 0 | 18 |
| `rogue_mud` | PASS | OK | OK | 0 | 78 |

---

## Example Warnings and Analysis

### Zig0 Compiler Warnings (on Examples)
The `zig0` compiler issues various warnings when processing the example programs.

- **Portability (Windows 98)**: Many examples trigger warnings about non-8.3 filenames (e.g., `std_debug.zig`).
- **Static Analysis**:
    - **Potential null pointer dereference**: `rogue_mud` shows 78 warnings of this type. These occur primarily in manual memory management patterns (arenas).
- **Unresolved Calls (Informational Messages)**: `rogue_mud` reports 52 "Unresolved call" messages.
    - **Analysis**: These are harmless and occur during the deferred validation pass before all module symbols are completely resolved. They resolve correctly during the final link phase.

### Generated C89 Warnings
- **`heapsort`**: 6 warnings regarding incompatible pointer types when passing array pointers.
- **`lisp_interpreter_curr`**: 12 warnings regarding ISO C forbids conversion between function pointers and object pointers (`void *`). This is expected due to the way builtins are stored in the Lisp environment using `void *`.
- **Note**: Most examples that previously had C89 warnings now compile cleanly with `-std=c89 -pedantic` thanks to recent improvements in aggregate initializer lifting and type mapping.

---

## zig0 Status

### C++98 Compilation
Compiling `zig0` with `g++ -std=c++98 -Wall -Wextra -Isrc/include src/bootstrap/bootstrap_all.cpp -o zig0` produces zero fatal errors and is verified to work on the current environment.

### Stage 1 Bootstrap (sf/)
Compiling the Stage 1 compiler (`sf/src/main.zig`) with `zig0` is memory-stable. `valgrind` reports no errors during the compilation process. While the compilation currently stops at semantic analysis due to undeclared identifiers in the stage1 source, the compiler itself remains stable and does not crash or segfault when handling large multi-module inputs.
