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
    NODE_IDENTIFIER,      ///< An identifier (e.g., a variable name `my_var`).

    // ~~~~~~~~~~~~~~~~~~~~~~ Statements ~~~~~~~~~~~~~~~~~~~~~~~
    NODE_BLOCK_STMT,      ///< A block of statements enclosed in `{}`.
    NODE_EMPTY_STMT,      ///< An empty statement (`;`).
    NODE_IF_STMT,         ///< An if-else statement.
    NODE_WHILE_STMT,      ///< A while loop statement.
    NODE_RETURN_STMT,     ///< A return statement.
    NODE_DEFER_STMT,       ///< A defer statement.

    // ~~~~~~~~~~~~~~~~~~ Declarations ~~~~~~~~~~~~~~~~~~~
    NODE_FN_DECL,         ///< A function declaration.
    NODE_VAR_DECL,        ///< A variable or constant declaration.
    NODE_PARAM_DECL,      ///< A function parameter declaration.

    // ~~~~~~~~~~~~~~ Container Declarations ~~~~~~~~~~~~~~~~~
    NODE_STRUCT_DECL,     ///< A struct declaration.
    NODE_UNION_DECL,      ///< A union declaration.
    NODE_ENUM_DECL,       ///< An enum declaration.

    // ~~~~~~~~~~~~~~~~~~ Type Expressions ~~~~~~~~~~~~~~~~~
    NODE_TYPE_NAME,       ///< A type specified by a name (e.g., `i32`).
    NODE_POINTER_TYPE,    ///< A pointer type (e.g., `*i32`).
    NODE_ARRAY_TYPE,      ///< An array or slice type (e.g., `[8]u8`).

    // ~~~~~~~~~~~~~~~~~~ Compile-Time Operations ~~~~~~~~~~~~~~~~~
    NODE_COMPTIME_BLOCK   ///< A comptime block.
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

        // Compile-Time Operations
        ASTComptimeBlockNode comptime_block;
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

## 3. AST Node Memory Layout and Strategy

To maintain a small memory footprint on constrained systems, the size of AST nodes is critical. The `ASTNode` struct itself has a base size, and the `union` member will be as large as its largest member.

### "Out-of-Line" Allocation Strategy and Impact

To keep the main `ASTNode` union small, any node-specific struct that is "large" should not be stored directly in the union. Instead, a pointer to the struct should be stored, and the struct itself should be allocated separately from the arena.

**Guideline:** A node is considered "large" if its `sizeof` on a 32-bit architecture is greater than **8 bytes**.

The initial implementation stored all node types inline. The largest member of the `ASTNode` union was `ASTVarDeclNode`, which was 16 bytes on a 32-bit system (due to pointers and bools). This forced the entire `ASTNode` to be **32 bytes** (`sizeof(NodeType)` + `sizeof(SourceLocation)` + `sizeof(union)` => 4 + 12 + 16).

By applying the out-of-line strategy, the largest `ASTVarDeclNode`, `ASTIfStmtNode`, and `ASTBinaryOpNode` structs were converted to pointers in the union. The largest remaining inline members are now `ASTIntegerLiteralNode` (`i64`) and `ASTFloatLiteralNode` (`double`), both at 8 bytes. This reduces the size of the union to 8 bytes, and the total `sizeof(ASTNode)` to **24 bytes** (4 + 12 + 8).

This change results in a **25% reduction in memory usage for every single node in the AST**, which is a significant saving for the target platform.

### Node Size Analysis (32-bit architecture)

| Node Struct                 | Size (bytes) | Stored in Union |
| --------------------------- | ------------ | --------------- |
| `ASTNode`                   | **24**       | -               |
| `ASTBinaryOpNode`           | 12           | Pointer (4)     |
| `ASTIfStmtNode`             | 12           | Pointer (4)     |
| `ASTVarDeclNode`            | 16           | Pointer (4)     |
| `ASTFnDeclNode`             | 16           | Pointer (4)     |
| `ASTWhileStmtNode`          | 8            | Inline          |
| `ASTArrayTypeNode`          | 8            | Inline          |
| `ASTParamDeclNode`          | 8            | Inline          |
| `ASTIntegerLiteralNode`     | 8            | Inline          |
| `ASTFloatLiteralNode`       | 8            | Inline          |
| `ASTBlockStmtNode`          | 4            | Inline          |
| `ASTDeferStmtNode`          | 4            | Inline          |
| `ASTIdentifierNode`         | 4            | Inline          |
| `ASTPointerTypeNode`        | 4            | Inline          |
| `ASTReturnStmtNode`         | 4            | Inline          |
| `ASTStringLiteralNode`      | 4            | Inline          |
| `ASTTypeNameNode`           | 4            | Inline          |
| `ASTUnaryOpNode`            | 8            | Inline          |
| `ASTCharLiteralNode`        | 1            | Inline          |

## 4. Implemented AST Node Types

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

## 5. Type Expression Node Types

These nodes are used to represent types within the AST, such as in variable declarations or function return types.

### `ASTTypeNameNode`
Represents a type that is specified by a simple name or identifier.
*   **Zig Code:** `i32`, `bool`, `MyCustomStruct`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTTypeNameNode
     * @brief Represents a type specified by an identifier.
     * @var ASTTypeNameNode::name The name of the type (interned string).
     */
    struct ASTTypeNameNode {
        const char* name;
    };
    ```

### `ASTPointerTypeNode`
Represents a pointer to another type.
*   **Zig Code:** `*u8`, `*const MyStruct`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTPointerTypeNode
     * @brief Represents a pointer type.
     * @var ASTPointerTypeNode::base A pointer to the ASTNode for the type being pointed to.
     */
    struct ASTPointerTypeNode {
        ASTNode* base;
    };
    ```

### `ASTArrayTypeNode`
Represents both fixed-size arrays and dynamic slices.
*   **Zig Code:** `[8]u8` (sized array), `[]bool` (slice)
*   **Structure:**
    ```cpp
    /**
     * @struct ASTArrayTypeNode
     * @brief Represents an array or slice type.
     * @var ASTArrayTypeNode::element_type A pointer to the ASTNode for the element type.
     * @var ASTArrayTypeNode::size An expression for the array size (can be NULL for a slice).
     */
    struct ASTArrayTypeNode {
        ASTNode* element_type;
        ASTNode* size; // Can be NULL for a slice
    };
    ```

## 6. Statement Node Types

These nodes represent statements, which are instructions that perform actions.

### `ASTBlockStmtNode`
Represents a sequence of statements enclosed in braces `{ ... }`.
*   **Zig Code:**
    ```zig
    {
        var x = 1;
        print(x);
    }
    ```
*   **Structure:**
    ```cpp
    /**
     * @struct ASTBlockStmtNode
     * @brief Represents a block of statements.
     * @var ASTBlockStmtNode::statements A pointer to a dynamic array of statement nodes.
     */
    struct ASTBlockStmtNode {
        DynamicArray<ASTNode*>* statements;
    };
    ```

#### Parsing Logic (`parseBlockStatement`)
The `parseBlockStatement` function is responsible for parsing a block of statements. It handles the following cases:
- An empty block: `{}`
- A block with one or more empty statements: `{;}` or `{; ;}`
- A block with nested empty blocks: `{{}}`
- A mix of the above.

At this stage, it only recognizes other blocks and empty statements. Any other type of statement will result in a fatal error.

### `ASTEmptyStmtNode`
Represents an empty statement, which is just a semicolon.
*   **Zig Code:** `;`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTEmptyStmtNode
     * @brief Represents an empty statement.
     */
    struct ASTEmptyStmtNode {
        // No data needed.
    };
    ```

### `ASTIfStmtNode`
Represents an `if` statement with an optional `else` clause.
*   **Zig Code:** `if (condition) { ... } else { ... }`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTIfStmtNode
     * @brief Represents an if-else statement.
     * @var ASTIfStmtNode::condition The condition expression.
     * @var ASTIfStmtNode::then_block The statement block for the 'if' branch.
     * @var ASTIfStmtNode::else_block The statement block for the 'else' branch (can be NULL).
     */
    struct ASTIfStmtNode {
        ASTNode* condition;
        ASTNode* then_block;
        ASTNode* else_block; // Can be NULL
    };
    ```

### `ASTWhileStmtNode`
Represents a `while` loop.
*   **Zig Code:** `while (condition) { ... }`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTWhileStmtNode
     * @brief Represents a while loop.
     * @var ASTWhileStmtNode::condition The loop condition expression.
     * @var ASTWhileStmtNode::body The loop body.
     */
    struct ASTWhileStmtNode {
        ASTNode* condition;
        ASTNode* body;
    };
    ```

### `ASTReturnStmtNode`
Represents a `return` statement.
*   **Zig Code:** `return;`, `return 42;`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTReturnStmtNode
     * @brief Represents a return statement.
     * @var ASTReturnStmtNode::expression The expression to return (can be NULL).
     */
    struct ASTReturnStmtNode {
        ASTNode* expression; // Can be NULL
    };
    ```

### `ASTDeferStmtNode`
Represents a `defer` statement.
*   **Zig Code:** `defer file.close();`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTDeferStmtNode
     * @brief Represents a defer statement.
     * @var ASTDeferStmtNode::statement The statement to be executed at scope exit.
     */
    struct ASTDeferStmtNode {
        ASTNode* statement;
    };
    ```

## 7. Declaration Node Types

These nodes represent declarations, which introduce new named entities like variables and functions into the program.

### `ASTVarDeclNode`
Represents a `var` or `const` declaration.
*   **Zig Code:** `var x: i32 = 10;`, `const pi = 3.14;`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTVarDeclNode
     * @brief Represents a variable or constant declaration (`var` or `const`).
     * @var ASTVarDeclNode::name The name of the variable (interned string).
     * @var ASTVarDeclNode::type A pointer to the declared type (can be NULL).
     * @var ASTVarDeclNode::initializer A pointer to the initializer expression.
     * @var ASTVarDeclNode::is_const True if the declaration is `const`.
     * @var ASTVarDeclNode::is_mut True if the declaration is `var`.
     */
    struct ASTVarDeclNode {
        const char* name;
        ASTNode* type;
        ASTNode* initializer;
        bool is_const;
        bool is_mut;
    };
    ```

#### Parsing Logic (`parseVarDecl`)
The `parseVarDecl` function is responsible for parsing variable and constant declarations. It strictly follows the grammar:
`('var'|'const') IDENT ':' type_expr '=' expr ';'`

- It consumes a `var` or `const` token.
- It expects an identifier, a colon, a type expression (parsed via `parseType`), an equals sign, and an initializer expression.
- The initializer expression is currently handled by a minimal `parseExpression` function that **only supports integer literals**.
- The function constructs and returns a `NODE_VAR_DECL` AST node.
- Any deviation from this grammar results in a fatal error.

**Example Usage in Parser:**
```cpp
// Source code: "const answer: i32 = 42;"
Parser parser = create_parser_for_test("const answer: i32 = 42;", ...);
ASTNode* decl = parser.parseVarDecl();
// `decl` now points to a fully populated ASTNode with type NODE_VAR_DECL.
```

### `ASTFnDeclNode`
Represents a function declaration. This is a large node, so the `ASTNode` union stores a pointer to it rather than the struct itself.
*   **Zig Code:** `fn add(a: i32, b: i32) -> i32 { ... }`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTFnDeclNode
     * @brief Represents a function declaration.
     * @var ASTFnDeclNode::name The name of the function.
     * @var ASTFnDeclNode::params A dynamic array of pointers to ASTParamDeclNode.
     * @var ASTFnDeclNode::return_type A pointer to the return type expression (can be NULL).
     * @var ASTFnDeclNode::body A pointer to the function's body (a block statement).
     */
    struct ASTFnDeclNode {
        const char* name;
        DynamicArray<ASTParamDeclNode*>* params;
        ASTNode* return_type;
        ASTNode* body;
    };
    ```

#### Parsing Logic (`parseFnDecl`)
The `parseFnDecl` function is responsible for parsing function declarations. It strictly follows the grammar:
`'fn' IDENT '(' ')' '->' type_expr '{' '}'`

- It consumes the `fn` keyword, the function's identifier, an opening parenthesis, a closing parenthesis, an arrow `->`, a type expression, an opening brace, and a closing brace.
- **Parameter lists must be empty.** Any tokens between the parentheses will result in a fatal error. This will be expanded in a future task.
- **Function bodies must be empty.** Any tokens between the braces will result in a fatal error. This will be expanded in a future task.
- The return type is mandatory.
- Any deviation from this grammar results in a fatal error, adhering to the parser's no-recovery policy.

### `ASTParamDeclNode`
Represents a single parameter within a function's parameter list. This node is not directly used in the main `ASTNode` union but is a component of `ASTFnDeclNode`.
*   **Zig Code:** `a: i32`, `comptime message: []const u8`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTParamDeclNode
     * @brief Represents a single function parameter.
     * @var ASTParamDeclNode::name The name of the parameter.
     * @var ASTParamDeclNode::type A pointer to the parameter's type expression.
     */
    struct ASTParamDeclNode {
        const char* name;
        ASTNode* type;
    };
    ```

### `ASTFnDeclNode`
Represents a function declaration. This is a large node, so the `ASTNode` union stores a pointer to it rather than the struct itself.
*   **Zig Code:** `fn add(a: i32, b: i32) -> i32 { ... }`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTFnDeclNode
     * @brief Represents a function declaration.
     * @var ASTFnDeclNode::name The name of the function.
     * @var ASTFnDeclNode::params A dynamic array of pointers to ASTParamDeclNode.
     * @var ASTFnDeclNode::return_type A pointer to the return type expression (can be NULL).
     * @var ASTFnDeclNode::body A pointer to the function's body (a block statement).
     */
    struct ASTFnDeclNode {
        const char* name;
        DynamicArray<ASTParamDeclNode*>* params;
        ASTNode* return_type;
        ASTNode* body;
    };
    ```

## 8. Control Flow Node Types

These nodes represent control flow constructs like loops and switches.

### `ASTForStmtNode`
Represents a `for` loop statement. This is a large node, so it is allocated out-of-line.
*   **Zig Code:** `for (my_array) |item, i| { ... }`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTForStmtNode
     * @brief Represents a for loop statement.
     * @var ASTForStmtNode::iterable_expr The expression being iterated over.
     * @var ASTForStmtNode::item_name The name of the item capture variable.
     * @var ASTForStmtNode::index_name The optional name of the index capture variable (can be NULL).
     * @var ASTForStmtNode::body The block statement that is the loop's body.
     */
    struct ASTForStmtNode {
        ASTNode* iterable_expr;
        const char* item_name;
        const char* index_name; // Can be NULL
        ASTNode* body;
    };
    ```

### `ASTSwitchExprNode`
Represents a `switch` expression. This is a large node, so it is allocated out-of-line. It contains a list of `ASTSwitchProngNode`s.
*   **Zig Code:**
    ```zig
    switch (value) {
        1 => "one",
        2, 3 => "two or three",
        else => "other",
    }
    ```
*   **Structure:**
    ```cpp
    /**
     * @struct ASTSwitchProngNode
     * @brief Represents a single prong in a switch expression (e.g., `case => ...`).
     * @var ASTSwitchProngNode::cases A dynamic array of case expressions for this prong.
     * @var ASTSwitchProngNode::is_else True if this is the `else` prong.
     * @var ASTSwitchProngNode::body The expression to execute for this prong.
     */
    struct ASTSwitchProngNode {
        DynamicArray<ASTNode*>* cases;
        bool is_else;
        ASTNode* body;
    };

    /**
     * @struct ASTSwitchExprNode
     * @brief Represents a switch expression.
     * @var ASTSwitchExprNode::expression The expression whose value is being switched on.
     * @var ASTSwitchExprNode::prongs A dynamic array of pointers to the switch prongs.
     */
    struct ASTSwitchExprNode {
        ASTNode* expression;
        DynamicArray<ASTSwitchProngNode*>* prongs;
    };
    ```

## 9. Container Declaration Node Types

These nodes represent container types like structs, unions, and enums.

### `ASTStructDeclNode`
Represents a `struct` definition.
*   **Zig Code:** `struct { field1: i32, field2: bool }`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTStructDeclNode
     * @brief Represents a `struct` declaration. Allocated out-of-line.
     * @var ASTStructDeclNode::fields A dynamic array of pointers to ASTVarDeclNode representing the struct fields.
     */
    struct ASTStructDeclNode {
        DynamicArray<ASTNode*>* fields;
    };
    ```

### `ASTUnionDeclNode`
Represents a `union` definition.
*   **Zig Code:** `union { a: i32, b: f32 }`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTUnionDeclNode
     * @brief Represents a `union` declaration. Allocated out-of-line.
     * @var ASTUnionDeclNode::fields A dynamic array of pointers to ASTVarDeclNode representing the union fields.
     */
    struct ASTUnionDeclNode {
        DynamicArray<ASTNode*>* fields;
    };
    ```

### `ASTEnumDeclNode`
Represents an `enum` definition.
*   **Zig Code:** `enum { Red, Green, Blue }`, `enum { A = 1, B = 2 }`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTEnumDeclNode
     * @brief Represents an `enum` declaration. Allocated out-of-line.
     * @var ASTEnumDeclNode::fields A dynamic array of pointers to ASTVarDeclNode representing the enum fields, allowing for explicit values.
     */
    struct ASTEnumDeclNode {
        DynamicArray<ASTNode*>* fields;
    };
    ```

## 10. Error Handling Node Types

These nodes represent Zig's error handling mechanisms.

### `ASTTryExprNode`
Represents a `try` expression, which either unwraps a successful value or propagates an error.
*   **Zig Code:** `try fallible_operation()`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTTryExprNode
     * @brief Represents a `try` expression.
     * @var ASTTryExprNode::expression The expression that may return an error.
     */
    struct ASTTryExprNode {
        ASTNode* expression;
    };


## Parser Skeleton Design (Task 44a)

### Core Principles
- **Zero-allocation navigation**: Methods `advance()`, `peek()`, and `is_at_end()` perform no memory allocations. Critical for memory-constrained environments.
- **Bounds safety**: All operations validated via `assert()` in debug builds. Release builds rely on caller guarantees (lexer must provide valid EOF).
- **State minimalism**: Only tracks token stream position. No AST construction at this stage.

### Memory Strategy
- **Arena usage**: Reserved for future node allocation (44b+). Not utilized in 44a methods.
- **Token references**: `peek()` returns const reference to avoid copying tokens. Lexer guarantees token lifetime exceeds parser lifetime.

### Error Handling (44a Scope)
- **Fatal errors only**: Out-of-bounds access aborts immediately via `assert()`. Recovery mechanisms deferred to 44b.
- **No error messages**: Memory constraints prohibit string allocation for errors in this phase.

### TDD Verification Points
1. `advance()` correctly increments position and returns consumed token
2. `peek()` never modifies parser state
3. `is_at_end()` returns true exactly at `token_count_` position
4. All methods handle empty token streams safely (via constructor assertions)
    ```

### `ASTCatchExprNode`
Represents a `catch` expression, providing a fallback value in case of an error.
*   **Zig Code:** `my_value catch |err| fallback_value`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTCatchExprNode
     * @brief Represents a `catch` expression. Allocated out-of-line.
     * @var ASTCatchExprNode::payload The expression that may produce an error.
     * @var ASTCatchExprNode::error_name The optional name for the captured error (can be NULL).
     * @var ASTCatchExprNode::else_expr The expression to evaluate if an error occurs.
     */
    struct ASTCatchExprNode {
        ASTNode* payload;
        const char* error_name; // Can be NULL
        ASTNode* else_expr;
    };
    ```

### `ASTErrDeferStmtNode`
Represents an `errdefer` statement, which is executed only if the function returns an error.
*   **Zig Code:** `errdefer cleanup();`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTErrDeferStmtNode
     * @brief Represents an `errdefer` statement.
     * @var ASTErrDeferStmtNode::statement The statement to execute upon error-based scope exit.
     */
    struct ASTErrDeferStmtNode {
        ASTNode* statement;
    };
    ```

## 11. Future AST Node Requirements

A review of the Zig language specification has identified several language features for which AST nodes have not yet been defined. Adding these nodes will be necessary to parse a more complete subset of the Zig language. Future tasks should be created to address the following:

*   **Container Declarations:**
    *   `OpaqueDeclNode`: For `opaque` type declarations.

*   **Control Flow:**
    *   `ForStmtNode`: For `for` loops. (DONE)
    *   `SwitchExprNode`: For `switch` expressions, including prongs and cases. (DONE)

*   **Error Handling:**
    *   `TryExprNode`: For the `try` expression. (DONE)
    *   `CatchExprNode`: For the `catch` expression. (DONE)
    *   `ErrDeferStmtNode`: For `errdefer` statements. (DONE)

*   **Asynchronous Operations:**
    *   `AsyncExprNode`: For `async` function calls.
    *   `AwaitExprNode`: For the `await` expression.
    *   `SuspendStmtNode`: For the `suspend` statement.
    *   `ResumeStmtNode`: For the `resume` statement.

*   **Compile-Time Operations:**
    *   `ComptimeBlockNode`: For `comptime` blocks. (DONE)

## 12. Compile-Time Operation Node Types

These nodes are related to compile-time execution and evaluation.

### `ASTComptimeBlockNode`
Represents a `comptime` block, which contains an expression that must be evaluated at compile-time.
*   **Zig Code:** `comptime { ... }`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTComptimeBlockNode
     * @brief Represents a `comptime` block.
     * @var ASTComptimeBlockNode::expression The expression inside the block to be evaluated at compile-time.
     */
    struct ASTComptimeBlockNode {
        ASTNode* expression;
    };
    ```

## 13. Type Expression Parsing

The parser is responsible for parsing type expressions from the token stream. The grammar for type expressions is as follows:

`type = primitive | pointer_type | array_type | slice_type`
`primitive = IDENTIFIER`
`pointer_type = '*' type`
`array_type = '[' <expr> ']' type`
`slice_type = '[]' type`

### AST Node Structures

- **`ASTTypeNameNode`**: Represents a primitive or named type (e.g., `i32`, `MyStruct`).
- **`ASTPointerTypeNode`**: Represents a pointer to a base type.
- **`ASTArrayTypeNode`**: Represents both fixed-size arrays and slices. For slices, the `size` field is `NULL`.

### Error Cases

The parser will abort with an error in the following cases:
- A type expression is expected but not found.
- An array's size is not an integer literal.
- The closing `]` is missing in an array type declaration.

## 14. Parser Error Handling

The parser's error handling strategy is designed for simplicity and adherence to the strict technical constraints of the project.

### No-Recovery Policy
At this foundational stage, any syntax error is considered fatal. When the parser encounters a token sequence that violates the language grammar (e.g., a missing semicolon or an unexpected token), it does not attempt to recover by synchronizing to a future state. Instead, it immediately halts the compilation process. This simplifies the initial parser implementation significantly.

### The `error()` Function
All fatal parsing errors are routed through the `Parser::error(const char* msg)` function. Its behavior is platform-dependent to comply with the project's dependency limitations:

-   **On Windows (`_WIN32`):** It uses the Win32 API call `OutputDebugStringA` to print a "Parser Error: " prefix followed by the specific error message to the debugger's output console.
-   **On other platforms:** It produces no output.

After printing the message (on Windows), the function **always** calls `abort()`. This terminates the program immediately, preventing any further processing of the invalid source code.

This approach avoids forbidden standard library dependencies like `<cstdio>` (for `fprintf`) while still providing useful diagnostic messages on the primary development and target platform.
