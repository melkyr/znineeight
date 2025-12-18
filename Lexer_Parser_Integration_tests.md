# Lexer-Parser Integration Test Failures

This document tracks and analyzes failures discovered during the integration testing of the Lexer and Parser components (Task 74).

### 1. Test Case: `ParserIntegration_ForLoopOverSlice`
- **Source Code:**
```zig
for (my_slice[0..4]) |item| {}
```
- **Observed Behavior:**
  - The test runner process aborted, indicating a fatal error in the parser. The test `ParserIntegration_ForLoopOverSlice` was the last one added and is the likely cause.
- **Hypothesis / Root Cause Analysis:**
  1.  **Lexer Mismatch:** The lexer does not have a token for the range operator `..`. In `src/bootstrap/lexer.cpp`, the logic for `.` handles `...` (`TOKEN_ELLIPSIS`) and `.` (`TOKEN_DOT`), but not `..`. When it sees `..`, it emits a `TOKEN_DOT` and backtracks, leaving the second `.` to be processed as the next token.
  2.  **Parser Failure:** The `parsePostfixExpression` function in `src/bootstrap/parser.cpp` is responsible for array access `[...]`. It calls `parseExpression` to handle the contents within the brackets.
  3.  `parseExpression` parses the integer `0` successfully. It then sees the `.` token. `TOKEN_DOT` is not a binary operator, so `parsePrecedenceExpr` returns the node for `0`.
  4.  `parsePostfixExpression` then expects a closing `]`. However, the current token is the second `.`.
  5.  The `expect(TOKEN_RBRACKET, ...)` call fails, which invokes `parser->error()`, leading to an `abort()`.

  The core issue is that the parser and lexer do not support range expressions (`..`) as valid syntax within an array access. The test passed erroneously before because it was not being correctly registered and run by the test harness.
---
### 2. Test Case: `ParserIntegration_ComprehensiveFunction`
- **Source Code:**
```zig
fn comprehensive_test() -> i32 {
    var i: i32 = 0;
    while (i < 10) {
        if (i % 2 == 0) {
            i = i + 1;
        } else {
            i = i + 2;
        }
    }
    for (some_iterable) |item| {
        // do nothing
    }
    return i;
}
```
- **Observed Behavior:**
  - The test runner process aborted. This indicates a fatal error in the parser, as the test attempts to parse a full function definition.
- **Hypothesis / Root Cause Analysis:**
  1.  **Parser Limitation:** The documentation in `AST_parser.md` and the implementation in `src/bootstrap/parser.cpp` for `parseFnDecl` explicitly state that it only supports empty function bodies.
  2.  **Error Trigger:** The parser, after parsing the function signature `fn comprehensive_test() -> i32 {`, encounters the `var` token, which is not the expected `}`.
  3.  The `parseFnDecl` function has a check: `if (peek().type != TOKEN_RBRACE) { error("Non-empty function bodies are not yet supported"); }`.
  4.  This `error()` call correctly triggers an `abort()`, which terminates the test runner.

  The failure is not a bug in the parser, but rather a limitation that the comprehensive test was designed to expose. The parser is behaving as documented. A more advanced `parseStatement` dispatcher that can be called from `parseBlockStatement` is needed to handle statements inside a function body.
---
### 3. Test Case: `ParserIntegration_IfWithComplexCondition`
- **Source Code:**
```zig
if (a && (b || c)) {}
```
- **Observed Behavior:**
  - The test runner process aborted, indicating a fatal error in the parser when this specific test is enabled.
- **Hypothesis / Root Cause Analysis:**
  1.  **Expression Parsing:** The condition `a && (b || c)` is parsed by `parseExpression`, which uses a Pratt parser (`parsePrecedenceExpr`).
  2.  **Potential Flaw:** The logic for handling parenthesized expressions occurs in `parsePrimaryExpr`. When `parsePrecedenceExpr` is parsing the `&&` operator, it recursively calls `parsePrecedenceExpr` for the right-hand side. This recursive call should correctly handle the `(b || c)` part.
  3.  The crash suggests that the parser state is becoming corrupted during this process. A possible cause is that after parsing the parenthesized `(b || c)` expression, the parser's position is not correctly advanced past the closing `)`. This could lead to an infinite loop where the parser keeps re-parsing the same tokens, eventually causing a stack overflow or other fatal error. Another possibility is a memory corruption issue in the arena allocator when building the nested binary operator AST nodes.
