# Task 107 Implementation & Refactoring Guide

This document tracks the implementation of Task 107 and outlines the necessary refactoring for existing tests.

## Phase 1: Foundational Type Helpers

The following foundational type helpers have been implemented in `type_checker.cpp` and `type_checker.hpp`:

*   **`isNumericType(Type* type)`:** Checks if a given type is any of the numeric types (`i8` through `f64`, `isize`, `usize`) or a `TYPE_INTEGER_LITERAL`.
*   **`canLiteralFitInType(Type* literal_type, Type* target_type)`:** Determines if a `TYPE_INTEGER_LITERAL` can be safely assigned to a given numeric type without overflow.
*   **`checkBinaryOperation(...)`:** The existing binary operation checker has been updated to use the new helpers to support C89-style integer literal promotion. Now, an operation like `i32 + <literal 10>` is valid, and the result is `i32`.

## Affected Tests Requiring Refactoring

The introduction of stricter C89 type-checking rules, especially the requirement for identical types in binary operations (with the exception of literal promotion), will cause several existing tests to fail. These tests were written with the expectation of more lenient, C++-style implicit conversions.

The following test files and specific test cases will likely require updates:

*   **`tests/test_type_checker.cpp`:**
    *   `test_addition_with_widening`: This test likely checks for implicit widening between numeric types (e.g., `i8 + i16`). This is no longer allowed. The test should be updated to use explicit casts or be removed.
    *   `test_subtraction_with_mixed_signedness`: This test probably mixes signed and unsigned integers, which is no longer permitted.
    *   Any other tests that rely on implicit numeric conversions in binary operations.

*   **`tests/main.cpp`:**
    *   Any integration tests that perform arithmetic with mixed types will fail. These will need to be identified and updated.

### Refactoring Strategy

For each failing test, the following steps should be taken:

1.  **Identify the invalid operation:** Pinpoint the exact binary operation that is causing the type mismatch error.
2.  **Assess the intent:** Determine if the test is validating a feature that is no longer supported (like implicit widening) or if it's a valid scenario that needs to be expressed differently.
3.  **Update the test:**
    *   For features that are no longer supported, the test should be **removed** or **rewritten** to test the new, stricter behavior (i.e., assert that the operation fails).
    *   For valid scenarios, introduce explicit casts in the test's source code to make the types match before the operation.

By following this process, we can align the existing test suite with the new C89-compliant type system.
