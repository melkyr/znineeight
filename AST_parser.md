# AST & Parser Design

This document provides a detailed overview of the Abstract Syntax Tree (AST) and the Parser for the RetroZig compiler.

## 1. Core Design Philosophy

The AST is the central data structure used by the compiler after the lexing phase. It represents the source code in a hierarchical, tree-like format that is easy for the subsequent phases (type checking, code generation) to work with.

### Memory Strategy: Arena Allocation
Given the strict memory constraints of the target platform (<16MB), the entire AST is allocated using a single `ArenaAllocator`. This has two key advantages:
1.  **Speed:** Allocating a new node is a simple and fast pointer bump within a pre-allocated memory region.
2.  **Simplicity:** All memory used by the AST for a given compilation unit can be freed at once by simply resetting the arena, eliminating the need for complex, per-node memory management and destructors.

## 2. Foundational AST Structures

All nodes in the tree are represented by the `ASTNode` struct. It is designed to be memory-efficient by using a `union` to store data specific to the node's type.

### 2.1 Pass Pipeline

The compiler's semantic analysis is divided into three passes:
1.  **Type Checker**: Resolves types, validates operations, and tags symbols with semantic flags (`SYMBOL_FLAG_LOCAL`, `SYMBOL_FLAG_PARAM`).
2.  **Lifetime Analyzer**: A read-only pass that uses the flags and AST structure to detect dangling pointers.
3.  **Null Pointer Analyzer**: A read-only pass that identifies potential null pointer dereferences and uninitialized pointer usage.

### `NodeType` Enum

This enum is the discriminator for the `union` inside the `ASTNode` struct.

```cpp
enum NodeType {
    // Expressions
    NODE_UNARY_OP,        ///< A unary operation (e.g., `-x`, `!y`, `p.*`).
    NODE_BINARY_OP,       ///< A binary operation (e.g., `a + b`).
    NODE_FUNCTION_CALL,   ///< A function call expression (e.g., `foo()`).
    NODE_ARRAY_ACCESS,    ///< An array access expression (e.g., `arr[i]`).
    NODE_ARRAY_SLICE,     ///< An array slice expression (e.g., `arr[start..end]`).

    // Literals
    NODE_INTEGER_LITERAL, ///< An integer literal (e.g., `123`, `0xFF`).
    NODE_FLOAT_LITERAL,   ///< A floating-point literal (e.g., `3.14`).
    NODE_CHAR_LITERAL,    ///< A character literal (e.g., `'a'`).
    NODE_STRING_LITERAL,  ///< A string literal (e.g., `"hello"`).
    NODE_IDENTIFIER,      ///< An identifier (e.g., a variable name `my_var`).
    NODE_NULL_LITERAL,    ///< A `null` literal.

    // Statements
    NODE_BLOCK_STMT,      ///< A block of statements enclosed in `{}`.
    NODE_EMPTY_STMT,      ///< An empty statement (`;`).
    NODE_IF_STMT,         ///< An if-else statement.
    NODE_WHILE_STMT,      ///< A while loop statement.
    NODE_RETURN_STMT,     ///< A return statement.
    NODE_DEFER_STMT,      ///< A defer statement.
    NODE_FOR_STMT,        ///< A for loop statement.
    NODE_EXPRESSION_STMT, ///< A statement that consists of a single expression.

    // Declarations
    NODE_VAR_DECL,        ///< A variable or constant declaration.
    NODE_PARAM_DECL,      ///< A function parameter declaration.
    NODE_FN_DECL,         ///< A function declaration.

    // Type Expressions
    NODE_TYPE_NAME,       ///< A type represented by a name (e.g., `i32`).
    NODE_POINTER_TYPE,    ///< A pointer type (e.g., `*u8`).
    NODE_ARRAY_TYPE,      ///< An array or slice type (e.g., `[8]u8`, `[]bool`).
};
```

### `ASTNode` Struct

This is the core structure for every node in the tree.

```cpp
struct ASTNode {
    NodeType type;
    SourceLocation loc;
    Type* resolved_type;

    union {
        ASTBinaryOpNode* binary_op; // Out-of-line
        ASTUnaryOpNode unary_op;

        // Literals
        ASTIntegerLiteralNode integer_literal;
        ASTFloatLiteralNode float_literal;
        ASTCharLiteralNode char_literal;
        ASTStringLiteralNode string_literal;
        ASTIdentifierNode identifier;

        // Statements
        ASTBlockStmtNode block_stmt;
        ASTEmptyStmtNode empty_stmt;
        ASTIfStmtNode* if_stmt; // Out-of-line
        ASTWhileStmtNode while_stmt;
        ASTReturnStmtNode return_stmt;
        ASTDeferStmtNode defer_stmt;
        ASTExpressionStmtNode expression_stmt;

        // Declarations
        ASTVarDeclNode* var_decl; // Out-of-line
        ASTParamDeclNode param_decl;
        ASTFnDeclNode* fn_decl; // Out-of-line

        // Type Expressions
        ASTTypeNameNode type_name;
        ASTPointerTypeNode pointer_type;
        ASTArrayTypeNode array_type;
    } as;
};
```

## 3. AST Node Memory Layout and Strategy

To maintain a small memory footprint on constrained systems, the size of AST nodes is critical. The `ASTNode` struct itself has a base size, and the `union` member will be as large as its largest member.

### "Out-of-Line" Allocation Strategy
To keep the main `ASTNode` union small, any node-specific struct that is "large" (e.g. > 8 bytes on 32-bit) is stored as a pointer, and the struct itself is allocated separately from the arena.

## 4. Implemented AST Node Types

### Expressions

#### `ASTUnaryOpNode`
Represents an operation with a single operand.
*   **Zig Code:** `-x`, `!is_ready`, `p.*`, `&x`
*   **Structure:**
    ```cpp
    struct ASTUnaryOpNode {
        ASTNode* operand;
        TokenType op;
    };
    ```

#### Parsing Logic (`parsePostfixExpression`)
The `parsePostfixExpression` function handles postfix operations, which have higher precedence.

- **For a Zig-style dereference (`.*`)**:
    - It constructs an `ASTUnaryOpNode` with `op` set to `TOKEN_DOT_ASTERISK`.
    - The current expression becomes the operand.

#### Parsing Logic (`parseUnaryExpr`)
Handles prefix unary operators like `-`, `!`, `~`, `&`, and C-style `*`.

## 5. Pass Pipeline & Semantic Analysis

### 5.1 Type Checker
Resolves types and populates the symbol table. It supports both C-style prefix `*p` and Zig-style postfix `p.*` dereferencing.

### 5.2 Null Pointer Analyzer
Identifies potential null pointer dereferences using a scoped state-tracking system.
- **Definite Null Dereference (Error 2004)**
- **Uninitialized Pointer Warning (Warning 6001)**
- **Potential Null Dereference Warning (Warning 6002)**
