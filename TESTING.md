# Testing Guide

This document outlines the testing strategy and procedures for the RetroZig compiler.

## 1. Unit Tests

Unit tests are used to verify the correctness of individual compiler components (Lexer, Parser, TypeChecker, Analyzers).

### Batch Testing Strategy
To prevent memory fragmentation and handle the large number of tests (~380+) within strict memory constraints (<16MB), the test suite is divided into multiple batches. Each batch runs in a fresh process with its own arena.

Execute the `test.sh` script (or `test.bat` on Windows) to compile all batch runners and execute them sequentially via `run_all_tests.sh`.

By default, the test runner binaries (`test_runner_batch*`) are automatically deleted after successful execution to save space. To keep the binaries for debugging, use the `--no-postclean` flag:

```bash
./test.sh           # Compiles, runs, and cleans up binaries
./test.sh --no-postclean  # Compiles, runs, and keeps binaries
```

To run a specific batch:
```bash
./test_runner_batch1
```

### Test Framework
The project uses a custom, minimal unit testing framework defined in `src/include/test_framework.hpp`.
- `TEST_FUNC(name)`: Defines a test function.
- `ASSERT_TRUE(condition)`: Asserts that a condition is true.
- `ASSERT_FALSE(condition)`: Asserts that a condition is false.
- `ASSERT_EQ(expected, actual)`: Asserts that two values are equal.

### Adding a New Unit Test
1. Create or open a test file in the `tests/` directory (e.g., `tests/my_component_tests.cpp`).
2. Use the `TEST_FUNC` macro to define your test.
3. Include the test file in `tests/main.cpp` using `#include`.
4. Add the test function to the `tests` array in `main()` in `tests/main.cpp`.

## 2. Integration Tests

Integration tests verify that multiple compiler stages work together correctly. The full pipeline typically consists of:
`Lexing -> Parsing -> Type Checking -> [Analyzers] -> Code Generation`

### Integration Test Examples
Existing integration tests can be found in `tests/integration_tests.cpp`. They demonstrate how to set up a `CompilationUnit`, add source code, and run the full pipeline with all analyzers enabled.

## 3. Self-Tests

The bootstrap compiler includes a `--self-test` mode that runs an internal suite of integration tests directly from the compiler executable.

```bash
./retrozig --self-test
```

This is useful for quick verification of the compiler's core functionality in its final binary form.

## 4. Memory Safety Testing

Since the compiler targets 1990s-era hardware, memory efficiency and safety are paramount.

### Valgrind
To check for memory leaks and memory corruption, run the test runner under Valgrind:

```bash
valgrind --leak-check=full ./test_runner
```

### Arena Allocation
Tests should use the `ArenaAllocator` and `ArenaLifetimeGuard` to ensure that memory used during a test is properly cleaned up at the end of the test.

```cpp
TEST_FUNC(MyTest) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    // ... test logic ...
    return true;
}
```

## 5. Manual Compilation Testing

### Enhanced Error Messages
The `DoubleFreeAnalyzer` provides enhanced diagnostics by tracking allocation sites. When testing, you should verify that error messages contain correct location information:

- **Memory Leak Warning**: `Memory leak: 'p' not freed (allocated at test.zig:2:15)`
- **Double Free Error**: `Double free of pointer 'p' (allocated at test.zig:2:15) - first freed at test.zig:3:5`
- **Double Free via Defer**: `Double free of pointer 'p' (allocated at test.zig:2:15) - first freed via defer at test.zig:4:5 (deferred free at test.zig:6:10)`
- **Ownership Transfer Warning**: `Pointer 'p' transferred (at test.zig:8:5) - receiver responsible for freeing`

You can manually test the compiler on Zig source files using the `--compile` flag:

```bash
./retrozig --compile my_source.zig
```

This will run the full compilation pipeline, including all static analysis passes, and report any errors or warnings to the console.

## 6. Path-Aware Analysis Testing (Task 130)
The `DoubleFreeAnalyzer` is path-aware. Tests should verify that it correctly handles conditional deallocations and merges states.

### If/Else Branching
Verify that freeing a pointer in only one branch of an `if` results in an `AS_UNKNOWN` state after the `if`, preventing false definite double-free reports.

### Switch Expressions
Verify that `switch` prongs fork state correctly and merge back. If states diverge across prongs, the variable should become `AS_UNKNOWN`.

### Try/Catch and Orelse
Verify that `try` transitions all potentially affected pointers to `AS_UNKNOWN`. `catch` and `orelse` should fork for success/failure paths and merge back accurately.

### Loop Safety
Verify that variables modified within `while` or `for` loops are transitioned to `AS_UNKNOWN` to account for potential multiple iterations.

### Memory Stability
Run Valgrind to ensure the new delta-based state map does not leak memory or access uninitialized values during branch analysis.

## 7. Edge Case Coverage (Tasks 131 & 132)
The test suite explicitly covers the following edge cases to ensure analyzer reliability:

### Task 131 (Identify Multiple Deallocations)
-   **Nested Defer Scopes**: Verified that `defer` statements in inner blocks are executed correctly and their state persists or triggers double-free reports at appropriate points.
-   **Multiple Defers**: Verified that multiple `defer` statements for the same pointer in the same scope trigger a double free (in LIFO order).
-   **Defers in Loops**: Verified that the analyzer correctly handles the uncertainty of multiple loop iterations, transitioning modified pointers to `AS_UNKNOWN`.

### Task 132 (Flag Double-Free Risks)
-   **Pointer Aliasing**: Verified that the compiler conservatively handles assignments between pointer variables by transitioning the target to `AS_UNKNOWN`.
-   **Transfer to Unknown Functions**: Verified that passing a pointer to any non-freeing function marks it as `AS_TRANSFERRED` and issues a warning at scope exit.
-   **Conditional Allocation**: Verified that unconditional frees after a conditional allocation (if-else) are flagged as potential risks (`WARN_FREE_UNALLOCATED`).

## 8. Error-Returning Function Detection Testing (Task 142)
Tests verify that functions returning error unions (`!T`) or error sets are correctly identified and rejected.

### Cataloguing Verification
Verify that `ErrorFunctionCatalogue` correctly records function names, return types, and parameter counts for all error-returning functions, even when they are rejected.

### Rejection Verification
Confirm that `C89FeatureValidator` reports `ERR_NON_C89_FEATURE` for each detected error-returning function.

### Pipeline Order
Tests should verify that `TypeChecker` successfully resolves error types before `C89FeatureValidator` runs, ensuring that even complex return types (like those using type aliases) are accurately detected.
