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

This enum is the discriminator for the `union` inside the `ASTNode` struct.

```cpp
/**
 * @enum NodeType
 * @brief Defines the type of each node in the Abstract Syntax Tree.
 */
enum NodeType {
    // ~~~~~~~~~~~~~~~~~~~~~~ Expressions ~~~~~~~~~~~~~~~~~~~~~~
    NODE_UNARY_OP,        ///< A unary operation (e.g., `-x`, `!y`).
    NODE_BINARY_OP,       ///< A binary operation (e.g., `a + b`).

    // ~~~~~~~~~~~~~~~~~~~~~~~ Literals ~~~~~~~~~~~~~~~~~~~~~~~~
    NODE_INTEGER_LITERAL, ///< An integer literal (e.g., `123`, `0xFF`).
    NODE_FLOAT_LITERAL,   ///< A floating-point literal (e.g., `3.14`).
    NODE_CHAR_LITERAL,    ///< A character literal (e.g., `'a'`).
    NODE_STRING_LITERAL,  ///< A string literal (e.g., `"hello"`).
    NODE_IDENTIFIER       ///< An identifier (e.g., a variable name `my_var`).
};
```

### `ASTNode` Struct

This is the core structure for every node in the tree.

```cpp
/**
 * @struct ASTNode
 * @brief The fundamental building block of the Abstract Syntax Tree.
 *
 * Each `ASTNode` represents a single construct in the source code. It contains a `type`
 * to identify the construct, a `loc` for error reporting, and a `union` holding the
 * specific data for that construct type.
 */
struct ASTNode {
    NodeType type;
    SourceLocation loc;

    union {
        ASTBinaryOpNode binary_op;
        ASTUnaryOpNode unary_op;
        ASTIntegerLiteralNode integer_literal;
        // ... other node types
    } as;
};
```

**Example Usage:**
```cpp
// Example: Creating an integer literal node
ArenaAllocator arena(4096);
ASTNode* node = (ASTNode*)arena.alloc(sizeof(ASTNode));

node->type = NODE_INTEGER_LITERAL;
node->loc.line = 5;
node->loc.column = 12;
node->as.integer_literal.value = 1998;
```

## 3. Implemented AST Node Types

The following node types are defined and tested, forming the foundation for parsing expressions.

### Literals

#### `ASTIntegerLiteralNode`
Represents a raw integer value.
*   **Zig Code:** `42`, `0xFF`, `1_000`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTIntegerLiteralNode
     * @brief Represents an integer literal.
     * @var ASTIntegerLiteralNode::value The 64-bit integer value.
     */
    struct ASTIntegerLiteralNode {
        i64 value;
    };
    ```

#### `ASTFloatLiteralNode`
Represents a floating-point value.
*   **Zig Code:** `3.14`, `1.0e-5`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTFloatLiteralNode
     * @brief Represents a floating-point literal.
     * @var ASTFloatLiteralNode::value The double-precision float value.
     */
    struct ASTFloatLiteralNode {
        double value;
    };
    ```

#### `ASTCharLiteralNode`
Represents a single character literal.
*   **Zig Code:** `'a'`, `'\n'`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTCharLiteralNode
     * @brief Represents a character literal.
     * @var ASTCharLiteralNode::value The character value.
     */
    struct ASTCharLiteralNode {
        char value;
    };
    ```

#### `ASTStringLiteralNode`
Represents a string literal. The `value` field points to an interned string to save memory.
*   **Zig Code:** `"hello"`, `"multi\nline"`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTStringLiteralNode
     * @brief Represents a string literal.
     * @var ASTStringLiteralNode::value A pointer to the interned string.
     */
    struct ASTStringLiteralNode {
        const char* value;
    };
    ```

#### `ASTIdentifierNode`
Represents an identifier, such as a variable or function name. The `name` field points to an interned string.
*   **Zig Code:** `my_var`, `println`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTIdentifierNode
     * @brief Represents an identifier.
     * @var ASTIdentifierNode::name A pointer to the interned string for the identifier's name.
     */
    struct ASTIdentifierNode {
        const char* name;
    };
    ```

### Expressions

#### `ASTUnaryOpNode`
Represents an operation with a single operand.
*   **Zig Code:** `-x`, `!is_ready`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTUnaryOpNode
     * @brief Represents a unary operation.
     * @var ASTUnaryOpNode::operand The operand.
     * @var ASTUnaryOpNode::op The token representing the operator (e.g., TOKEN_MINUS).
     */
    struct ASTUnaryOpNode {
        ASTNode* operand;
        TokenType op;
    };
    ```

#### `ASTBinaryOpNode`
Represents an operation with two operands.
*   **Zig Code:** `a + b`, `x * y`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTBinaryOpNode
     * @brief Represents a binary operation.
     * @var ASTBinaryOpNode::left The left-hand side operand.
     * @var ASTBinaryOpNode::right The right-hand side operand.
     * @var ASTBinaryOpNode::op The token representing the operator (e.g., TOKEN_PLUS).
     */
    struct ASTBinaryOpNode {
        ASTNode* left;
        ASTNode* right;
        TokenType op;
    };
    ```
