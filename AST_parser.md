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

### `NodeType` Enum

This enum is the discriminator for the `union` inside the `ASTNode` struct and is a complete representation of all language constructs the parser can produce.

```cpp
/**
 * @enum NodeType
 * @brief Defines the type of each node in the Abstract Syntax Tree.
 */
enum NodeType {
    // ~~~~~~~~~~~~~~~~~~~~~~ Expressions ~~~~~~~~~~~~~~~~~~~~~~
    NODE_UNARY_OP,        ///< A unary operation (e.g., `-x`, `!y`).
    NODE_BINARY_OP,       ///< A binary operation (e.g., `a + b`).
    NODE_FUNCTION_CALL,   ///< A function call expression (e.g., `foo()`).
    NODE_ARRAY_ACCESS,    ///< An array access expression (e.g., `arr[i]`).

    // ~~~~~~~~~~~~~~~~~~~~~~~ Literals ~~~~~~~~~~~~~~~~~~~~~~~~
    NODE_INTEGER_LITERAL, ///< An integer literal (e.g., `123`, `0xFF`).
    NODE_FLOAT_LITERAL,   ///< A floating-point literal (e.g., `3.14`).
    NODE_CHAR_LITERAL,    ///< A character literal (e.g., `'a'`).
    NODE_STRING_LITERAL,  ///< A string literal (e.g., `"hello"`).
    NODE_IDENTIFIER,      ///< An identifier (e.g., a variable name `my_var`).

    // ~~~~~~~~~~~~~~~~~~~~~~ Statements ~~~~~~~~~~~~~~~~~~~~~~~
    NODE_BLOCK_STMT,      ///< A block of statements enclosed in `{}`.
    NODE_EMPTY_STMT,      ///< An empty statement (`;`).
    NODE_IF_STMT,         ///< An if-else statement.
    NODE_WHILE_STMT,      ///< A while loop statement.
    NODE_RETURN_STMT,     ///< A return statement.
    NODE_DEFER_STMT,      ///< A defer statement.
    NODE_FOR_STMT,        ///< A for loop statement.

    // ~~~~~~~~~~~~~~~~~~~ Expressions ~~~~~~~~~~~~~~~~~~~~~
    NODE_SWITCH_EXPR,     ///< A switch expression.

    // ~~~~~~~~~~~~~~~~~~~~ Declarations ~~~~~~~~~~~~~~~~~~~~~~~
    NODE_VAR_DECL,        ///< A variable or constant declaration.
    NODE_PARAM_DECL,      ///< A function parameter declaration.
    NODE_FN_DECL,         ///< A function declaration.

    // ~~~~~~~~~~~~~~ Container Declarations ~~~~~~~~~~~~~~~~~
    NODE_STRUCT_DECL,     ///< A struct declaration.
    NODE_UNION_DECL,      ///< A union declaration.
    NODE_ENUM_DECL,       ///< An enum declaration.

    // ~~~~~~~~~~~~~~~~~~~ Type Expressions ~~~~~~~~~~~~~~~~~~~~
    NODE_TYPE_NAME,       ///< A type represented by a name (e.g., `i32`).
    NODE_POINTER_TYPE,    ///< A pointer type (e.g., `*u8`).
    NODE_ARRAY_TYPE,      ///< An array or slice type (e.g., `[8]u8`, `[]bool`).

    // ~~~~~~~~~~~~~~~~ Error Handling ~~~~~~~~~~~~~~~~~
    NODE_TRY_EXPR,        ///< A try expression.
    NODE_CATCH_EXPR,      ///< A catch expression.
    NODE_ERRDEFER_STMT,   ///< An errdefer statement.

    // ~~~~~~~~~~~~~~~~ Async Operations ~~~~~~~~~~~~~~~~~
    NODE_ASYNC_EXPR,      ///< An async function call.
    NODE_AWAIT_EXPR,      ///< An await expression.

    // ~~~~~~~~~~~~~~~~ Compile-Time Operations ~~~~~~~~~~~~~~~~~
    NODE_COMPTIME_BLOCK   ///< A comptime block.
};
```

### `ASTNode` Struct

This is the core structure for every node in the tree.

```cpp
/**
 * @struct ASTNode
 * @brief The fundamental building block of the Abstract Syntax Tree.
 */
struct ASTNode {
    NodeType type;
    SourceLocation loc;

    union {
        // Expressions
        ASTBinaryOpNode* binary_op; // Out-of-line
        ASTUnaryOpNode unary_op;
        ASTFunctionCallNode* function_call; // Out-of-line
        ASTArrayAccessNode* array_access; // Out-of-line

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
        ASTForStmtNode* for_stmt; // Out-of-line

        // Expressions
        ASTSwitchExprNode* switch_expr; // Out-of-line

        // Error Handling
        ASTTryExprNode try_expr;
        ASTCatchExprNode* catch_expr; // Out-of-line
        ASTErrDeferStmtNode errdefer_stmt;

        // Async
        ASTAsyncExprNode async_expr;
        ASTAwaitExprNode await_expr;

        // Comptime
        ASTComptimeBlockNode comptime_block;

        // Declarations
        ASTVarDeclNode* var_decl; // Out-of-line
        ASTParamDeclNode param_decl;
        ASTFnDeclNode* fn_decl; // Out-of-line
        ASTStructDeclNode* struct_decl; // Out-of-line
        ASTUnionDeclNode* union_decl; // Out-of-line
        ASTEnumDeclNode* enum_decl; // Out-of-line

        // Type Expressions
        ASTTypeNameNode type_name;
        ASTPointerTypeNode pointer_type;
        ASTArrayTypeNode array_type;
    } as;
};
```

## 3. AST Node Memory Layout and Strategy

To maintain a small memory footprint on constrained systems, the size of AST nodes is critical. The `ASTNode` struct itself has a base size, and the `union` member will be as large as its largest member.

### "Out-of-Line" Allocation Strategy and Impact

To keep the main `ASTNode` union small, any node-specific struct that is "large" should not be stored directly in the union. Instead, a pointer to the struct should be stored, and the struct itself should be allocated separately from the arena.

**Guideline:** A node is considered "large" if its `sizeof` on a 32-bit architecture is greater than **8 bytes**.

The largest members of the `ASTNode` union are `ASTIntegerLiteralNode` (`i64`) and `ASTFloatLiteralNode` (`double`), both at 8 bytes. This reduces the size of the union to 8 bytes, and the total `sizeof(ASTNode)` to **24 bytes** (4 for `NodeType` + 12 for `SourceLocation` + 8 for `union`). This represents a significant memory saving for every single node in the AST.

### Node Size Analysis (32-bit architecture)

| Node Struct                 | Size (bytes) | Stored in Union |
| --------------------------- | :----------: | :-------------: |
| `ASTNode`                   |    **24**    |       N/A       |
| `ASTBinaryOpNode`           |      12      |   Pointer (4)   |
| `ASTFunctionCallNode`       |      8       |   Pointer (4)   |
| `ASTArrayAccessNode`        |      8       |   Pointer (4)   |
| `ASTIfStmtNode`             |      12      |   Pointer (4)   |
| `ASTVarDeclNode`            |      16      |   Pointer (4)   |
| `ASTFnDeclNode`             |      16      |   Pointer (4)   |
| `ASTForStmtNode`            |      16      |   Pointer (4)   |
| `ASTSwitchExprNode`         |      8       |   Pointer (4)   |
| `ASTCatchExprNode`          |      12      |   Pointer (4)   |
| `ASTStructDeclNode`         |      4       |   Pointer (4)   |
| `ASTUnionDeclNode`          |      4       |   Pointer (4)   |
| `ASTEnumDeclNode`           |      4       |   Pointer (4)   |
| `ASTWhileStmtNode`          |      8       |   Inline (8)    |
| `ASTArrayTypeNode`          |      8       |   Inline (8)    |
| `ASTParamDeclNode`          |      8       |   Inline (8)    |
| `ASTIntegerLiteralNode`     |      8       |   Inline (8)    |
| `ASTFloatLiteralNode`       |      8       |   Inline (8)    |
| `ASTUnaryOpNode`            |      8       |   Inline (8)    |
| `ASTBlockStmtNode`          |      4       |   Inline (8)    |
| `ASTDeferStmtNode`          |      4       |   Inline (8)    |
| `ASTIdentifierNode`         |      4       |   Inline (8)    |
| `ASTPointerTypeNode`        |      4       |   Inline (8)    |
| `ASTReturnStmtNode`         |      4       |   Inline (8)    |
| `ASTStringLiteralNode`      |      4       |   Inline (8)    |
| `ASTTypeNameNode`           |      4       |   Inline (8)    |
| `ASTCharLiteralNode`        |      1       |   Inline (8)    |

## 4. Implemented AST Node Types

### Literals

(Sections for `ASTIntegerLiteralNode`, `ASTFloatLiteralNode`, `ASTCharLiteralNode`, `ASTStringLiteralNode`, `ASTIdentifierNode` remain the same.)

### Expressions

(Sections for `ASTUnaryOpNode`, `ASTFunctionCallNode`, `ASTArrayAccessNode`, `ASTBinaryOpNode` and their `Parsing Logic` subsections remain the same.)

**Operator Precedence Levels:**
| Precedence | Operators                      | Associativity |
|:----------:|:-------------------------------|:--------------|
| 10         | `*`, `/`, `%`                  | Left          |
| 9          | `+`, `-`                       | Left          |
| 8          | `<<`, `>>`                     | Left          |
| 7          | `&`                            | Left          |
| 6          | `^`                            | Left          |
| 5          | `|`                            | Left          |
| 4          | `==`, `!=`, `<`, `>`, `<=`, `>=` | Left          |
| 3          | `and`                          | Left          |
| 2          | `or`                           | Left          |
| 1          | `orelse`                       | Right         |

## 5. Type Expression Node Types

(Sections for `ASTTypeNameNode`, `ASTPointerTypeNode`, `ASTArrayTypeNode` remain the same.)

## 6. Statement Node Types

(Sections for `ASTBlockStmtNode`, `ASTEmptyStmtNode`, `ASTIfStmtNode`, `ASTWhileStmtNode`, `ASTReturnStmtNode`, `ASTDeferStmtNode` and their `Parsing Logic` subsections remain the same.)

## 7. Declaration Node Types

(Sections for `ASTVarDeclNode`, `ASTFnDeclNode`, `ASTParamDeclNode` and their `Parsing Logic` subsections remain the same.)

## 8. Control Flow Node Types

(Sections for `ASTForStmtNode`, `ASTSwitchExprNode` remain the same.)

## 9. Container Declaration Node Types

(Sections for `ASTStructDeclNode`, `ASTUnionDeclNode`, `ASTEnumDeclNode` remain the same.)

## 10. Error Handling Node Types

(Sections for `ASTTryExprNode`, `ASTCatchExprNode`, `ASTErrDeferStmtNode` remain the same.)

## 11. Async and Comptime Node Types

These nodes are related to async operations and compile-time execution.

### `ASTAsyncExprNode`
*   **Zig Code:** `async my_func()`
*   **Structure:**
    ```cpp
    struct ASTAsyncExprNode {
        ASTNode* expression;
    };
    ```

### `ASTAwaitExprNode`
*   **Zig Code:** `await my_promise`
*   **Structure:**
    ```cpp
    struct ASTAwaitExprNode {
        ASTNode* expression;
    };
    ```

### `ASTComptimeBlockNode`
*   **Zig Code:** `comptime { ... }`
*   **Structure:**
    ```cpp
    struct ASTComptimeBlockNode {
        ASTNode* expression;
    };
    ```

## 12. Type Expression Parsing

(Section remains the same.)

## 13. Parser Error Handling

(Section remains the same.)
