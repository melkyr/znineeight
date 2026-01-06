# Unsupported Operator Refactor: `&&`/`||` vs `and`/`or`

This document outlines the necessary refactoring to resolve the conflict between the lexer's implementation of logical operators and the parser's expectations, as identified during the start of Task 105.

## 1. Problem Summary

The Zig language specification uses the keywords `and` and `or` for logical AND and OR operations, respectively.

-   **Correct Implementation (Lexer):** The lexer correctly identifies `and` and `or` as keywords, producing `TOKEN_AND` and `TOKEN_OR`.
-   **Incorrect Design (Parser & Docs):** Several key design documents (`AST_parser.md`, `DESIGN.md`) and the parser's implementation were incorrectly based on the C-style operators `&&` and `||`. This created a fundamental conflict preventing the parsing of logical expressions.

The goal of this refactor is to make the entire codebase consistent with the Zig language specification by exclusively using `and` and `or`.

## 2. Affected Code and Required Changes

### Codebase Refactoring

1.  **`src/include/lexer.hpp`**
    -   **Line 178:** Remove the `TOKEN_PIPE2` enum member.
    -   **Line 179:** Remove the `TOKEN_AMPERSAND2` enum member.

2.  **`src/bootstrap/lexer.cpp`**
    -   Remove the logic that detects and tokenizes `||` and `&&`. This is typically found in the `lexMultiCharToken` or equivalent function where single characters like `|` and `&` are checked for a second character.

3.  **`src/bootstrap/parser.cpp`**
    -   Modify the Pratt parser's precedence table (`get_precedence` function or equivalent) to include `TOKEN_AND` and `TOKEN_OR` with the correct precedence levels (e.g., `and` having higher precedence than `or`).
    -   Update the `parseBinaryExpr` or `parsePrecedenceExpr` function to handle `TOKEN_AND` and `TOKEN_OR` as valid binary operators.

4.  **`src/bootstrap/type_checker.cpp`**
    -   **Line 29:** Remove the `case TOKEN_PIPE2: return "||";` from the `getTokenSpelling` helper function.

### Test Refactoring

1.  **`tests/test_lexer_special_ops.cpp`**
    -   The test case that validates the tokenization of a string including `||` must be removed or modified to exclude it.

2.  **`tests/test_parser_integration.cpp`**
    -   All tests that use `&&` or `||` in their source code strings must be rewritten to use `and` and `or`. This includes tests for expressions like `if (a && b)` and `if (a && (b || c))`.

3.  **`tests/test_parser_bug.cpp`**
    -   The test case with `const x: bool = a && b;` must be rewritten to `const x: bool = a and b;`.

## 3. Affected Documentation and Required Changes

1.  **`AI_tasks.md`**
    -   **Task 22:** The note "(DONE)" should be amended to clarify that `||` was removed as it is not a valid Zig operator.
    -   **Task 34:** This task, "Implement lexing for missing operators (`--`, `&&`)", should be marked as invalid or removed. A note should be added explaining that `&&` is not the correct logical operator.
    -   **Task 62:** "Extend `parseBinaryExpr` for Logical Operators" should be updated to specify the use of `and` and `or`.
    -   **Task 105:** The description should be updated to reflect that this refactor was performed as a prerequisite.
    -   Any comments referencing `a && (b || c)` should be updated.

2.  **`AST_parser.md`**
    -   The operator precedence table must be updated to remove the rows for `&&` and `||`.
    -   New rows for `and` and `or` must be added with the correct precedence levels.

3.  **`DESIGN.md`**
    -   The "Token Precedence Table" in section 4.1 must be updated to remove `OPERATOR_AND` and `OPERATOR_OR` and replace them with entries for the `and` and `or` keywords.

4.  **`Bootstrap_type_system_and_semantics.md`**
    -   All mentions of logical operators `&&` and `||` must be replaced with `and` and `or`.
    -   The table entry for `||` should be removed.

5.  **`Lexer.md`**
    -   The table entry for `TOKEN_PIPE2` (`||`) should be removed from the "Special and Wrapping Operators" section.

## 4. Conclusion

This refactor will bring the compiler's logical operator handling in line with the Zig language standard, resolving the current implementation blocker and preventing future confusion. All subsequent development should proceed with the understanding that `and` and `or` are the exclusive keywords for logical operations.
