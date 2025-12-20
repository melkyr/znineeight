# Lexer-Parser Integration Test Suite

This document tracks the status and findings of the integration tests for the Lexer and Parser components, as established in Task 81.

## 1. Test Suite Overview

The primary integration test file is `tests/test_parser_integration.cpp`. It contains a suite of tests designed to validate that the parser correctly constructs an Abstract Syntax Tree (AST) from various source code snippets. These tests cover a range of language features, from simple variable declarations to more complex control flow and expression parsing.

## 2. Implemented Test Cases

The following test cases have been implemented and are passing, ensuring the robustness of the parser for these scenarios:

### `ParserIntegration_VarDeclWithBinaryExpr`
- **Purpose:** Verifies that a variable declaration with a simple binary expression as an initializer is parsed correctly.
- **Source Code:** `var x: i32 = 10 + 20;`
- **Validation:** Checks that the AST root is a `NODE_VAR_DECL` and that its initializer is a `NODE_BINARY_OP` with the correct operator (`+`) and integer literal operands.

### `ParserIntegration_ForLoopOverSlice`
- **Purpose:** Ensures the parser can handle a `for` loop that iterates over an array slice.
- **Source Code:** `for (my_slice[0..4]) |item| {}`
- **Validation:** Confirms that the parser creates a `NODE_FOR_STMT` whose iterable expression is a `NODE_ARRAY_SLICE` with the correct start and end indices.

### `ParserIntegration_ComprehensiveFunction`
- **Purpose:** A high-level test to ensure a function with a non-empty body containing various statements (variable declaration, `while` loop, `if` statement, `for` loop, `return`) can be parsed.
- **Source Code:** A multi-line function with nested control flow.
- **Validation:** Checks that a `NODE_FN_DECL` is created and that its body contains the correct number of top-level statements.

### `ParserIntegration_WhileWithFunctionCall`
- **Purpose:** Tests that the condition of a `while` loop can be a function call.
- **Source Code:** `while (should_continue()) {}`
- **Validation:** Asserts that the `condition` field of the `NODE_WHILE_STMT` is a `NODE_FUNCTION_CALL`.

### `ParserIntegration_IfWithComplexCondition`
- **Purpose:** Verifies correct precedence and associativity for nested logical operators (`&&`, `||`) in an `if` statement's condition.
- **Source Code:** `if (a && (b || c)) {}`
- **Validation:** Deeply inspects the AST to ensure that the `&&` and `||` binary operations are nested correctly according to operator precedence.

### `ParserIntegration_LogicalAndOperatorSymbol`
- **Purpose:** A regression test to ensure that the `&&` is correctly parsed as a logical AND operator (`TOKEN_AMPERSAND2`).
- **Source Code:** `const x: bool = a && b;`
- **Validation:** Checks that the initializer is a `NODE_BINARY_OP` with the `TOKEN_AMPERSAND2` operator.

### `ParserIntegration_ForLoopWithIndex`
- **Purpose:** Verifies that a `for` loop with both an item and an index capture variable is parsed correctly.
- **Source Code:** `for (my_array) |item, i| {}`
- **Validation:** Confirms that the `item_name` and `index_name` fields of the `NODE_FOR_STMT` are correctly populated.

### `ParserIntegration_TryCatchExpression`
- **Purpose:** Tests the parsing of a `try...catch` expression.
- **Source Code:** `var result = try risky_op() catch |err| fallback_op();`
- **Validation:** Ensures the parser creates a `NODE_CATCH_EXPR` that contains a `NODE_TRY_EXPR` and correctly captures the error name.

### `ParserIntegration_FunctionWithBody`
- **Purpose:** Explicitly verifies that a function with a simple body (a single variable declaration) is parsed correctly, confirming the fix for empty-body-only functions.
- **Source Code:** `fn do_stuff() -> void { var a: i32 = 1; }`
- **Validation:** Checks that the function's body is a `NODE_BLOCK_STMT` containing one statement of type `NODE_VAR_DECL`.

## 3. Known Limitations

As of this milestone, the parser is robust for the features tested above, but the following limitations should be noted for future work:

-   **Function Parameters:** Function declarations are parsed, but parameter lists are not yet supported. The parser will raise an error if any parameters are present.
-   **Advanced `comptime`:** While `comptime` blocks are parsed, the full range of compile-time operations and semantics is not yet implemented or tested.
-   **Limited Standard Library:** The parser does not yet interact with a standard library, so concepts like namespaces (`usingnamespace`) and complex built-in functions are not handled.
-   **Error Recovery:** The parser still operates on a fatal-error-only basis. It does not attempt to recover from syntax errors.
-   **Logical Operators:** The parser currently recognizes both `and` and `&&` as logical AND. This is a temporary measure to support legacy tests and will be resolved in a future task.
