# Testing Guide

This document outlines the testing strategy and procedures for the RetroZig compiler.

## 1. Unit Tests

Unit tests are used to verify the correctness of individual compiler components (Lexer, Parser, TypeChecker, Analyzers).

### Running Unit Tests
Execute the `test.sh` script (or `test.bat` on Windows) to compile and run all unit tests:

```bash
./test.sh
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
