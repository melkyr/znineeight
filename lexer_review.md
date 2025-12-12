# Lexer Review for RetroZig (Phase 2)

## 1. Overall Status

The lexer is in a robust state, covering a wide range of Zig tokens as specified in `Lexer.md`. The implementation correctly handles various literals (integers, floats, strings, chars), nested block comments, and a comprehensive set of operators. The code is generally clean, and the use of a sorted keyword table with binary search is efficient.

The current implementation provides a solid foundation for the subsequent parsing stage. The issues identified below are primarily minor inconsistencies or missing keywords that can be addressed straightforwardly.

## 2. Identified Issues & Action Plan

This section details the identified issues, their potential impact, and a recommended action plan to resolve them.

### Issue 1: Critical Missing Keywords in Implementation

**Observation:**
The `keywords` array in `src/bootstrap/lexer.cpp` is missing several crucial keywords that are defined in the `TokenType` enum (`src/include/lexer.hpp`). These include `fn`, `var`, `return`, and `defer`.

**Impact:**
This is a critical bug. Without these entries, the lexer will incorrectly classify these keywords as `TOKEN_IDENTIFIER`, which will cause the parser to fail when encountering fundamental language constructs like function and variable declarations.

**Action Plan:**
1.  **Update `keywords` array:** Add the missing keywords to the `keywords` array in `src/bootstrap/lexer.cpp`.
2.  **Maintain Sort Order:** Ensure the array remains alphabetically sorted to guarantee the correctness of the binary search lookup. The new entries should be inserted in the following positions:
    *   `{"defer", TOKEN_DEFER}`
    *   `{"fn", TOKEN_FN}`
    *   `{"return", TOKEN_RETURN}`
    *   `{"var", TOKEN_VAR}`

### Issue 2: Missing Operator Token Implementations

**Observation:**
The `TokenType` enum defines `TOKEN_MINUS2` (for `--`) and `TOKEN_AMPERSAND2` (for `&&`), but the `switch` statement in the `nextToken` function in `lexer.cpp` does not have logic to recognize them.

**Impact:**
The lexer will fail to tokenize `--` and `&&`. It will incorrectly parse them as two separate `-` or `&` tokens, leading to syntax errors in the parser.

**Action Plan:**
1.  **Update `nextToken`:**
    *   In the `case '-':` block, add a check for a second `-` to create `TOKEN_MINUS2`.
    *   In the `case '&':` block, add a check for a second `&` to create `TOKEN_AMPERSAND2` and update the existing logic to handle the single `&` case correctly.

### Issue 3: Potential Ambiguity with `..` Operator

**Observation:**
The lexer correctly tokenizes `...` as `TOKEN_ELLIPSIS` and correctly backtracks to handle `..` as two separate `TOKEN_DOT` tokens. While this behavior is logically sound based on the current implementation, the official Zig language includes a `..` range operator.

**Impact:**
This is not an immediate bug, but a point of potential deviation. If the intention is for this Zig subset to eventually support range expressions (`for (0..10)`), the current lexing logic would need to be modified.

**Action Plan:**
1.  **Clarify Intent:** No immediate code change is required. However, it is recommended to decide whether the `..` operator will be part of the RetroZig subset.
2.  **Document Deviation:** If `..` is intentionally omitted, this should be explicitly mentioned in `Lexer.md` to avoid future confusion.

## 3. Recommendations for `lexer.md`

To improve documentation and make future development easier, the following additions to `Lexer.md` are recommended:

1.  **Add a "Deviations from Official Zig" Section:** Create a new section that explicitly lists features of the official Zig lexer that are intentionally omitted or handled differently in RetroZig. This would be the perfect place to clarify the status of the `..` operator.

2.  **Synchronize Token Tables:** Add a note emphasizing that the token implementation tables in `Lexer.md` must be kept in sync with the `TokenType` enum in `lexer.hpp` and the `keywords` array in `lexer.cpp` to serve as a reliable source of truth.

3.  **Briefly Document Location Tracking:** Add a small paragraph explaining how `line` and `column` counters are updated, especially noting the handling of `\n` characters and the manual column adjustments after consuming multi-character tokens.
