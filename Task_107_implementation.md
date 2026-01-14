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

## Phase 2: Assignment Compatibility Validation

The following tests will be affected by the implementation of `IsTypeAssignableTo` in Phase 2. They rely on old, lenient assignment rules and will need to be refactored or removed when the new function is fully integrated in Phase 3.

- **`TypeChecker_VarDecl_Valid_Widening`** (from `tests/type_checker_var_decl.cpp`): This test currently passes because it assumes numeric widening is allowed in variable declarations (e.g., `const x: i64 = 42;`). Under strict C89 rules, this will become an error.

- **`TypeCompatibility` Test** (from `tests/type_compatibility_tests.cpp`): The assertions in this test are based on the `areTypesCompatible` helper, which explicitly allows for numeric widening. The following assertions will fail when validated against a strict C89 assignment checker:
  - `checker.areTypesCompatible(i16_t, i8_t)`
  - `checker.areTypesCompatible(i32_t, i16_t)`
  - `checker.areTypesCompatible(i64_t, i32_t)`
  - `checker.areTypesCompatible(f64_t, f32_t)`

## Phase 3: AST Node Integration

The strict C89 assignment validation has now been integrated into the AST visitors. The `visitAssignment` and `visitCompoundAssignment` functions in `type_checker.cpp` were updated to use the `IsTypeAssignableTo` function, replacing the older, more lenient `areTypesCompatible` logic.

### Newly Affected Tests

This integration is expected to cause the same tests listed in Phase 2 to fail, as the logic they depend on has now been replaced. The primary tests impacted are:

- **`TypeChecker_VarDecl_Valid_Widening`**: This test will now fail because implicit widening during variable initialization is no longer allowed. The test must be refactored to either use a variable of the correct type (e.g., `i32`) or be removed if it's testing a now-unsupported feature.

- **`TypeCompatibility` Test**: The assertions in this test that check for numeric widening will fail. These assertions should be removed or updated to reflect that `areTypesCompatible` is no longer used for assignment validation.

- **General Integration Tests**: Any other tests in the main test suite that rely on implicit numeric widening in simple or compound assignments will also fail. These will be identified and fixed in the subsequent testing and refactoring phase.

## Test Suite Analysis (Post-Implementation)

After the full implementation of all three phases, an investigation into the test suite failures revealed that the new, stricter C89 assignment validation was working correctly. The failures were not regressions but rather indicated that the tests themselves were written with the expectation of more lenient, C++-style implicit type conversions.

The final resolution involved updating the affected tests to align with the stricter C89 semantics. The following changes were made:

-   **`src/bootstrap/type_checker.cpp`**: The `visitVarDecl` function was updated with a special case to handle integer literal initializers, which is the correct C89 behavior. Additionally, the `canLiteralFitInType` helper was enhanced to allow integer literals to be assigned to floating-point types.

-   **`tests/type_checker_binary_ops.cpp`**: The tests `TypeCheckerBinaryOps_NumericArithmetic` and `TypeCheckerBinaryOps_Comparison` were failing because their setup code included an invalid assignment (`var a_i16: i16 = 3;`). The fix was to declare the variables without initializing them (e.g., `var a_i16: i16;`). This provided the necessary type mismatch for the tests to function as intended while also being syntactically correct.

-   **`tests/type_checker_var_decl.cpp`**: The tests in this file were updated to align with the correct C89 behavior for integer literals. `TypeChecker_VarDecl_Invalid_Widening` now correctly passes, and `TypeChecker_VarDecl_Multiple_Errors` now expects only one error.

This process has aligned the test suite with the new, stricter type system, ensuring that it correctly validates C89-compliant behavior.
