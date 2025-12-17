# Parser Review for Milestone 3

This document outlines a review of the RetroZig parser implementation. Its purpose is to identify gaps, inconsistencies, and missing features by comparing the current state of the parser and its documentation against the master design (`DESIGN.md`) and the official Zig language specification.

The goal is to generate a clear list of actionable tasks to ensure the parser is feature-complete and robust before proceeding to the integration testing phase (Task 63).

## 1. Gaps and Inconsistencies

### 1.1. Missing Parsing Logic

While the AST nodes for several language features have been defined in `ast.hpp`, the parser currently lacks the logic to parse them. New tasks must be created to implement the parsing functions for these features.

#### New Task Group: Control Flow Statements
*   **Reason:** To implement parsing for fundamental control flow structures beyond `if` and `while`. The AST nodes (`ASTForStmtNode`, `ASTSwitchExprNode`) already exist, but the parser cannot yet recognize or process `for` and `switch` statements from the source code.
*   **Tasks to Create:**
    *   `Implement parseForStatement`
    *   `Implement parseSwitchExpression`

#### New Task Group: Container Declaration Nodes
*   **Reason:** To parse container type definitions, a core feature for any complex program. The AST nodes (`ASTStructDeclNode`, `ASTUnionDeclNode`, `ASTEnumDeclNode`) are defined, but the parser cannot process `struct`, `union`, or `enum` declarations.
*   **Tasks to Create:**
    *   `Implement parseStructDeclaration`
    *   `Implement parseUnionDeclaration`
    *   `Implement parseEnumDeclaration`

#### New Task Group: Error Handling Expressions
*   **Reason:** To support Zig's idiomatic error handling. The AST nodes (`ASTTryExprNode`, `ASTCatchExprNode`, `ASTErrDeferStmtNode`) are defined, but the parser cannot recognize `try`, `catch`, or `errdefer`.
*   **Tasks to Create:**
    *   `Implement parseTryExpression`
    *   `Implement parseCatchExpression`
    *   `Implement parseErrDeferStatement`

#### New Task Group: Asynchronous Operations
*   **Reason:** To support async operations, which are part of the Zig language specification. The corresponding AST nodes (`ASTAsyncExprNode`, `ASTAwaitExprNode`) have been defined.
*   **Tasks to Create:**
    *   `Implement parseAsyncExpression`
    *   `Implement parseAwaitExpression`

#### New Task Group: Compile-Time Operations
*   **Reason:** To support compile-time execution blocks. The AST node (`ASTComptimeBlockNode`) has been defined.
*   **Tasks to Create:**
    *   `Implement parseComptimeBlock`
