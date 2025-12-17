# Parser Implementation Review

This document details a comprehensive review of the RetroZig parser implementation. The goal of this review is to identify gaps, inconsistencies, and missing features before proceeding to integration testing (Task 63).

## 1. Summary of Findings

The parser has a strong foundation. A Pratt parser (`parseBinaryExpr`) is correctly implemented for handling complex expression precedence, and core statement types (`if`, `while`, `return`, `defer`, `block`) are implemented. The AST node definitions in `ast.hpp` are surprisingly comprehensive, covering many advanced Zig features like `async`, `await`, `switch`, and container declarations.

However, a significant gap exists between the defined AST nodes and the implemented parsing logic. The majority of the advanced AST nodes defined in `ast.hpp` do not have corresponding parsing functions in `parser.cpp`. The current implementation can parse expressions, basic control flow, and stubbed-out function/variable declarations, but it cannot parse container declarations, `for` loops, `switch` expressions, or error-handling expressions.

This review concludes that the parser is not yet ready for integration testing. Several new, granular tasks must be added to `AI_tasks.md` to implement the missing parsing logic.

## 2. Identified Gaps and Inconsistencies

### 2.1. Missing Statement Parsing Logic
The following statement types have AST nodes defined in `ast.hpp`, but the `parseStatement` dispatcher in `parser.cpp` does not handle them, and no parsing functions exist.

*   **Gap:** `for` Statements (`NODE_FOR_STMT`)
    *   **Details:** `ASTForStmtNode` is defined, but no `parseForStatement` function exists.
*   **Gap:** `errdefer` Statements (`NODE_ERRDEFER_STMT`)
    *   **Details:** `ASTErrDeferStmtNode` is defined, but it is not handled in the `parseStatement` dispatcher.
*   **Gap:** Expression Statements
    *   **Details:** The `parseStatement` function does not handle standalone expression statements (e.g., a function call `foo();`). This is a fundamental statement type that is currently missing.

### 2.2. Missing Expression Parsing Logic
The following expression types have AST nodes defined but lack parsing logic.

*   **Gap:** `switch` Expressions (`NODE_SWITCH_EXPR`)
    *   **Details:** `ASTSwitchExprNode` and `ASTSwitchProngNode` are defined, but no `parseSwitchExpression` function exists.
*   **Gap:** `try` Expressions (`NODE_TRY_EXPR`)
    *   **Details:** `ASTTryExprNode` is defined, but there's no logic to parse a `try` keyword.
*   **Gap:** `catch` Expressions (`NODE_CATCH_EXPR`)
    *   **Details:** `ASTCatchExprNode` is defined, but there's no logic to parse a `catch` keyword.
*   **Gap:** `async`/`await` Expressions (`NODE_ASYNC_EXPR`, `NODE_AWAIT_EXPR`)
    *   **Details:** `ASTAsyncExprNode` and `ASTAwaitExprNode` are defined, but parsing logic is absent.
*   **Gap:** `comptime` Blocks (`NODE_COMPTIME_BLOCK`)
    *   **Details:** `ASTComptimeBlockNode` is defined, but there is no logic to parse a `comptime` block.

### 2.3. Missing Declaration Parsing Logic
The following declaration types have AST nodes defined but are not supported by the parser.

*   **Gap:** Container Declarations (`struct`, `union`, `enum`)
    *   **Details:** `ASTStructDeclNode`, `ASTUnionDeclNode`, and `ASTEnumDeclNode` are defined, but no corresponding parsing functions (`parseStructDecl`, etc.) exist.

### 2.4. Incomplete Implementations

*   **Gap:** Function Declarations with Parameters and Bodies
    *   **Details:** The current `parseFnDecl` implementation explicitly aborts if the parameter list or function body is non-empty. This is a major limitation.
*   **Gap:** Top-Level Parsing
    *   **Details:** There is no top-level `parseProgram` or `parseTopLevelItem` function to parse a full source file containing multiple declarations. The parser can only parse individual constructs when directly invoked by tests.

### 2.5. Documentation Inconsistencies

*   **`AST_parser.md` vs. `parser.cpp`:**
    *   The operator precedence table in `AST_parser.md` is incomplete. It is missing the bitwise operators (`<<`, `>>`, `&`, `|`, `^`) which *are* implemented in the `get_token_precedence` function in `parser.cpp`.
    *   The "Future AST Node Requirements" section in `AST_parser.md` is outdated. Most of the nodes listed there have already been defined in `ast.hpp`.
*   **`AI_tasks.md` vs. `ast.hpp`:**
    *   Tasks #39-43 for defining AST nodes are scattered. The implementation in `ast.hpp` is nearly complete, suggesting these tasks should be consolidated into a single "review and finalize" task.

## 3. Rationale for New Tasks in `AI_tasks.md`

To prepare for integration testing, the parser's capabilities must be expanded significantly. The following new tasks are proposed to address the gaps identified above. The tasks are designed to be granular and logically grouped.

*   **New Task Group: Control Flow Statements**
    *   **Reason:** To implement parsing for fundamental control flow structures beyond `if` and `while`.
    *   **Tasks:** `Implement parseForStatement`, `Implement parseSwitchExpression`.

*   **New Task Group: Error Handling Syntax**
    *   **Reason:** To parse Zig's core error handling expressions.
    *   **Tasks:** `Implement parsing for 'try' expressions`, `Implement parsing for 'catch' expressions`, `Implement parsing for 'errdefer' statements`.

*   **New Task Group: Container Declarations**
    *   **Reason:** To enable the definition of custom data types, which is essential for any non-trivial program.
    *   **Tasks:** `Implement parseStructDecl`, `Implement parseUnionDecl`, `Implement parseEnumDecl`.

*   **New Task: Expression Statements**
    *   **Reason:** To support basic statements like function calls (`my_func();`) that do not fall into other categories.
    *   **Task:** `Add support for Expression Statements in parseStatement`.

*   **New Task: Enhance Function Declarations**
    *   **Reason:** To remove the current limitation of empty-only function bodies and parameter lists.
    *   **Task:** `Extend parseFnDecl to support parameters and non-empty bodies`.

*   **New Task: Top-Level Parsing Loop**
    *   **Reason:** To create an entry point for parsing an entire source file from start to finish.
    *   **Task:** `Implement top-level parse loop to consume a full token stream`.

*   **New Task Group: Documentation & Cleanup**
    *   **Reason:** To synchronize the documentation with the current state of the code and address inconsistencies.
    *   **Tasks:** `Update AST_parser.md to reflect implemented features and fix precedence table`, `Consolidate and update AST node definition tasks in AI_tasks.md`.
