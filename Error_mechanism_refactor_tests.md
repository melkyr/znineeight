# Impact Analysis: Error Mechanism Refactor on Test Suite

This document identifies tests in the RetroZig test suite that will be affected by the refactor of the error reporting mechanism (transitioning from `fatalError`/`abort` to recoverable `report()`).

## 1. Summary of Impact

Total affected tests: **~153**
- **Parser Abort Dependencies**: 73 tests
- **Type Checker Abort Dependencies**: 72 tests
- **Error Message String Dependencies**: 8 tests
- **Error Code Dependencies**: ~20 tests

## 2. Affected Categories

### Category A: Parser Abort Dependencies (`expect_parser_abort`)
These tests use `expect_parser_abort` or `expect_statement_parser_abort`. They rely on the `Parser` calling `plat_abort()` when a syntax error is encountered.

**Impact**: If `Parser::error()` is changed to report an error and return (or synchronize), these tests will fail because the child process will exit with code 0 instead of aborting.

**Affected Files (Examples)**:
- `tests/test_parser_errors.cpp`
- `tests/test_parser_fn_pointer.cpp`
- `tests/test_parser_try_expr.cpp`
- `tests/test_parser_for_statement.cpp`
- `tests/test_parser_union.cpp`
- `tests/test_parser_switch.cpp`
- `tests/test_parser_if_statement.cpp`
- `tests/test_parser_while.cpp`
- `tests/test_parser_enums.cpp`

**Proposed Migration**:
Update `run_parser_test_in_child` in `tests/test_utils.cpp` to check `comp_unit.getErrorHandler().hasErrors()` and call `abort()` if true. This preserves the "abort on error" behavior for tests without refactoring each one.

---

### Category B: Type Checker Abort Dependencies (`expect_type_checker_abort`)
These tests use `expect_type_checker_abort`. Currently, `run_type_checker_test_in_child` manually calls `abort()` if any errors are reported.

**Impact**: **Low.** These tests should continue to pass as long as the refactored `TypeChecker` reports at least one error for the given input. If robustness improvements cause multiple errors to be reported, the test will still pass (as it only checks for *any* abort).

**Affected Files (Examples)**:
- `tests/task_119_test.cpp`
- `tests/test_generics_rejection.cpp`
- `tests/type_checker_enum_tests.cpp`
- `tests/integration/slice_tests.cpp`

---

### Category C: Error Message String Dependencies
These tests check the exact content of the error message using `ASSERT_STREQ` or `strstr`.

**Impact**: **High.** If error messages are centralized and reworded for better clarity/consistency, these tests will fail.

**Affected Tests**:
- `tests/test_assignment_compatibility.cpp`:
    - `ASSERT_STREQ(eh.getErrors()[0].message, "C89 assignment requires identical types: 'i32' to 'i64'")`
    - `ASSERT_STREQ(eh.getErrors()[0].message, "Cannot assign const pointer to non-const")`
    - `ASSERT_STREQ(eh.getErrors()[0].message, "Incompatible assignment: '*i32' to '*f32'")`
- `tests/test_task_150_extra.cpp`:
    - `strstr(unit.getErrorHandler().getErrors()[i].message, "Generic functions are not supported")`
- `tests/test_task_130_error_handling.cpp`:
    - Checks for `strstr` on various error messages.

**Proposed Migration**:
Update these tests to match the new centralized error messages.

---

### Category D: Error Code Dependencies
These tests check `ErrorReport::code` using `ASSERT_EQ`.

**Impact**: **Minimal.** As long as `ErrorCode` values are preserved, these tests will pass. However, if multiple errors are reported, the index `[0]` might not always point to the expected error if the order changes or new errors are detected earlier.

**Affected Files**:
- `tests/type_checker_pointer_operations.cpp`
- `tests/type_checker_pointer_arithmetic.cpp`
- `tests/type_checker_expressions.cpp`
- `tests/pointer_arithmetic_test.cpp`
- `tests/test_break_continue.cpp` (loops over errors and checks `code`)

---

## 3. Recommended Actions

1.  **Harden Test Utilities**: Modify `run_parser_test_in_child` in `tests/test_utils.cpp` to `abort()` on errors, ensuring `expect_parser_abort` remains valid for existing tests.
2.  **Centralized Message Audit**: When implementing the centralized message mapping, prioritize matching existing strings where it makes sense, but be prepared to update Category C tests.
3.  **Synchronization Strategy**: Ensure that when the `Parser` or `TypeChecker` encounters an error and continues, it doesn't enter an infinite loop or crash due to `NULL` nodes/types. The test suite will help verify this.
