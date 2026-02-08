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

### 2.2 Type Inference Handling
The `TypeChecker` supports Zig-style type inference for `var` and `const` declarations (e.g., `const x = 42;`).
- **Internal Representation**: Inferred variables have their `type` pointer set to `NULL` in the `ASTVarDeclNode`.
- **Location Tracking**: Since inferred variables lack an explicit type annotation, the `TypeChecker` uses the declaration node's location (typically the `var` or `const` keyword) as the source location for the symbol in the `SymbolTable`. This ensures robust error reporting and prevents NULL pointer dereferences during semantic analysis.

### `NodeType` Enum

This enum is the discriminator for the `union` inside the `ASTNode` struct.

```cpp
/**
 * @enum NodeType
 * @brief Defines the type of each node in the Abstract Syntax Tree.
 */
enum NodeType {
    // ~~~~~~~~~~~~~~~~~~~~~~ Expressions ~~~~~~~~~~~~~~~~~~~~~~
    NODE_ASSIGNMENT,
    NODE_COMPOUND_ASSIGNMENT,
    NODE_UNARY_OP,        ///< A unary operation (e.g., `-x`, `!y`, `p.*`).
    NODE_BINARY_OP,       ///< A binary operation (e.g., `a + b`).
    NODE_FUNCTION_CALL,   ///< A function call expression (e.g., `foo()`).
    NODE_ARRAY_ACCESS,    ///< An array access expression (e.g., `arr[i]`).
    NODE_ARRAY_SLICE,     ///< An array slice expression (e.g., `arr[start..end]`).
    NODE_MEMBER_ACCESS,   ///< A member access expression (e.g., `s.field`).
    NODE_STRUCT_INITIALIZER, ///< A struct initializer (e.g., `S { .x = 1 }`).

    // ~~~~~~~~~~~~~~~~~~~~~~~ Literals ~~~~~~~~~~~~~~~~~~~~~~~~
    NODE_BOOL_LITERAL,    ///< A boolean literal (`true` or `false`).
    NODE_NULL_LITERAL,    ///< A `null` literal.
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
    NODE_EXPRESSION_STMT, ///< A statement that consists of a single expression.

    // ~~~~~~~~~~~~~~~~~~~ Expressions ~~~~~~~~~~~~~~~~~~~~~
    NODE_SWITCH_EXPR,     ///< A switch expression.

    // ~~~~~~~~~~~~~~~~~~~~ Declarations ~~~~~~~~~~~~~~~~~~~~~~~
    NODE_VAR_DECL,        ///< A variable or constant declaration.
    NODE_PARAM_DECL,      ///< A function parameter declaration.
    NODE_FN_DECL,         ///< A function declaration.
    NODE_STRUCT_FIELD,    ///< A single field within a struct declaration.

    // ~~~~~~~~~~~~~~ Container Declarations ~~~~~~~~~~~~~~~~~
    NODE_STRUCT_DECL,     ///< A struct declaration.
    NODE_UNION_DECL,      ///< A union declaration.
    NODE_ENUM_DECL,       ///< An enum declaration.
    NODE_ERROR_SET_DEFINITION, ///< An error set definition (e.g., `error { A, B }`).
    NODE_ERROR_SET_MERGE,      ///< An error set merge (e.g., `E1 || E2`).

    // ~~~~~~~~~~~~~~~~~~~~~~ Statements ~~~~~~~~~~~~~~~~~~~~~~~
    NODE_IMPORT_STMT,     ///< An @import statement.

    // ~~~~~~~~~~~~~~~~~~~ Type Expressions ~~~~~~~~~~~~~~~~~~~~
    NODE_TYPE_NAME,       ///< A type represented by a name (e.g., `i32`).
    NODE_POINTER_TYPE,    ///< A pointer type (e.g., `*u8`).
    NODE_ARRAY_TYPE,      ///< An array or slice type (e.g., `[8]u8`, `[]bool`).
    NODE_ERROR_UNION_TYPE, ///< An error union type (e.g., `!i32`).
    NODE_OPTIONAL_TYPE,    ///< An optional type (e.g., `?i32`).

    // ~~~~~~~~~~~~~~~~ Error Handling ~~~~~~~~~~~~~~~~~
    NODE_TRY_EXPR,        ///< A try expression.
    NODE_CATCH_EXPR,      ///< A catch expression.
    NODE_ORELSE_EXPR,     ///< An orelse expression.
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
 *
 * Each `ASTNode` represents a single construct in the source code. It contains a `type`
 * to identify the construct, a `loc` for error reporting, and a `union` holding the
 * specific data for that construct type.
 */
struct ASTNode {
    NodeType type;
    SourceLocation loc;
    Type* resolved_type;
    const char* module;

    union {
        // Expressions
        ASTAssignmentNode* assignment; // Out-of-line
        ASTCompoundAssignmentNode* compound_assignment; // Out-of-line
        ASTBinaryOpNode* binary_op; // Out-of-line
        ASTUnaryOpNode unary_op;
        ASTFunctionCallNode* function_call; // Out-of-line
        ASTArrayAccessNode* array_access; // Out-of-line
        ASTArraySliceNode* array_slice; // Out-of-line
        ASTMemberAccessNode* member_access; // Out-of-line
        ASTStructInitializerNode* struct_initializer; // Out-of-line

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
        ASTStructDeclNode* struct_decl; // Out-of-line
        ASTUnionDeclNode* union_decl; // Out-of-line
        ASTEnumDeclNode* enum_decl; // Out-of-line
        ASTErrorSetDefinitionNode* error_set_decl; // Out-of-line
        ASTErrorSetMergeNode* error_set_merge; // Out-of-line

        // Statements
        ASTImportStmtNode* import_stmt; // Out-of-line

        // Type Expressions
        ASTTypeNameNode type_name;
        ASTPointerTypeNode pointer_type;
        ASTArrayTypeNode array_type;
        ASTErrorUnionTypeNode* error_union_type; // Out-of-line
        ASTOptionalTypeNode* optional_type; // Out-of-line

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

By applying the out-of-line strategy, the largest `ASTVarDeclNode`, `ASTIfStmtNode`, and `ASTBinaryOpNode` structs were converted to pointers in the union. The largest remaining inline members are now `ASTIntegerLiteralNode` (`u64` and flags) and `ASTFloatLiteralNode` (`double`), both at 8 bytes. This reduces the size of the union to 8 bytes.

The `ASTNode` struct itself contains:
- `NodeType type` (4 bytes)
- `SourceLocation loc` (12 bytes)
- `Type* resolved_type` (4 bytes)
- `union as` (8 bytes)

Total `sizeof(ASTNode)` is **28 bytes** (4 + 12 + 4 + 8).

**Note on 8-byte nodes:** Some nodes that are exactly 8 bytes (e.g., `ASTOrelseExprNode`, `ASTMemberAccessNode`, `ASTStructInitializerNode`) are currently stored as out-of-line pointers to maintain a clean separation of concerns or because they were initially designed as potentially larger. They must always be accessed via the `->` operator through the `as` union.

### Node Size Analysis (32-bit architecture)

| Node Struct                 | Size (bytes) | Stored in Union |
| --------------------------- | ------------ | --------------- |
| `ASTNode`                   | **32**       | -               |
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
| `ASTMemberAccessNode`       | 8            | Pointer (4)     |
| `ASTStructInitializerNode`  | 8            | Pointer (4)     |
| `ASTErrorSetDefinitionNode` | 8            | Pointer (4)     |
| `ASTErrorSetMergeNode`      | 8            | Pointer (4)     |
| `ASTImportStmtNode`         | 4            | Pointer (4)     |
| `ASTOrelseExprNode`         | 8            | Pointer (4)     |
| `ASTCharLiteralNode`        | 1            | Inline          |
| `ASTErrorUnionTypeNode`     | 20           | Pointer (4)     |
| `ASTOptionalTypeNode`       | 16           | Pointer (4)     |

## 4. Name Mangling for Milestone 4 Types

To ensure unique identification in C89 code, Milestone 4 types follow specific mangling rules:

### Error Unions (!T)
- **Mangled as**: `err_<payload_type>`
- **Example**: `!i32` → `err_i32`

### Optional Types (?T)
- **Mangled as**: `opt_<payload_type>`
- **Example**: `?*u8` → `opt_ptr_u8`

### Error Sets
- **Named**: Mangled as the set's name (e.g., `MyError`).
- **Anonymous**: `errset_<tag1>_<tag2>...`
- **Example**: `error{A, B}` → `errset_A_B`

## 5. Implemented AST Node Types

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
*   **Zig Code:** `-x`, `!is_ready`, `p.*`, `&x`, `++x`, `x++`, `--y`, `y--`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTUnaryOpNode
     * @brief Represents a unary operation.
     * @var ASTUnaryOpNode::operand The operand.
     * @var ASTUnaryOpNode::op The token representing the operator (e.g., TOKEN_MINUS, TOKEN_MINUS2).
     */
    struct ASTUnaryOpNode {
        ASTNode* operand;
        TokenType op;
    };
    ```

#### Parsing Logic (`parsePostfixExpression` for `.*`)
The `parsePostfixExpression` function handles Zig-style postfix dereference:
- When a `TOKEN_DOT_ASTERISK` is encountered, an `ASTUnaryOpNode` is created.
- The current expression becomes the `operand`.
- The `op` is set to `TOKEN_DOT_ASTERISK`.

#### Parsing Logic (`parseUnaryExpr`)
The `parseUnaryExpr` function is responsible for handling prefix unary operators. To avoid deep recursion and potential stack overflow on constrained systems, it uses an iterative approach to handle chained operators like `!!x` or `-&y`.

- It first enters a `while` loop to consume all consecutive unary operator tokens (`-`, `!`, `~`, `&`), storing them in a temporary list.
- After consuming all prefix operators, it calls `parsePostfixExpression` to parse the operand.
- It then iterates through the stored operator tokens in reverse order. For each operator, it constructs an `ASTUnaryOpNode` with the current expression as its operand.
- The newly created `ASTUnaryOpNode` then becomes the new expression, effectively wrapping the previous one. This process correctly builds the nested AST structure from right to left, ensuring the correct operator precedence.

#### Parsing Logic (`parsePrimaryExpr`)
The `parsePrimaryExpr` function is the entry point for parsing the simplest expression types, which form the building blocks for more complex expressions. It examines the current token and proceeds as follows:
- **Literals**: If the token is `TOKEN_INTEGER_LITERAL`, `TOKEN_FLOAT_LITERAL`, `TOKEN_CHAR_LITERAL`, or `TOKEN_STRING_LITERAL`, it creates the corresponding `AST<Type>LiteralNode` and populates it with the token's value.
- **Identifiers**: If the token is `TOKEN_IDENTIFIER`, it creates an `ASTIdentifierNode`.
- **Parenthesized Expressions**: If the token is `TOKEN_LPAREN`, it recursively calls `parseExpression` to parse the inner expression and then expects a closing `TOKEN_RPAREN`.
- **Errors**: If the token is anything else, it is considered a syntax error, and the parser aborts.

#### `ASTFunctionCallNode`
Represents a function call.
*   **Zig Code:** `my_func()`, `add(1, 2)`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTFunctionCallNode
     * @brief Represents a function call expression.
     * @var ASTFunctionCallNode::callee The expression being called.
     * @var ASTFunctionCallNode::args A dynamic array of argument expressions.
     */
    struct ASTFunctionCallNode {
        ASTNode* callee;
        DynamicArray<ASTNode*>* args;
    };
    ```

#### `ASTArrayAccessNode`
Represents an array or slice access.
*   **Zig Code:** `my_array[i]`, `get_slice()[0]`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTArrayAccessNode
     * @brief Represents an array or slice access expression.
     * @var ASTArrayAccessNode::array The expression being indexed.
     * @var ASTArrayAccessNode::index The index expression.
     */
    struct ASTArrayAccessNode {
        ASTNode* array;
        ASTNode* index;
    };
    ```

#### `ASTArraySliceNode`
Represents an array slice expression.
*   **Zig Code:** `my_array[0..10]`, `my_array[..]`, `my_array[5..]`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTArraySliceNode
     * @brief Represents an array or slice expression (e.g., `my_array[start..end]`).
     * @var ASTArraySliceNode::array The expression being sliced.
     * @var ASTArraySliceNode::start The start index expression (can be NULL).
     * @var ASTArraySliceNode::end The end index expression (can be NULL).
     */
    struct ASTArraySliceNode {
        ASTNode* array;
        ASTNode* start; // Can be NULL
        ASTNode* end;   // Can be NULL
    };
    ```

#### Parsing Logic (`parsePostfixExpression`)
The `parsePostfixExpression` function is responsible for handling postfix operations, which have a higher precedence than unary or binary operators. It follows a loop-based approach to handle chained operations like `get_array()[0]()`.

- It starts by calling `parsePrimaryExpr` to get the base of the expression (e.g., an identifier, a literal, or a parenthesized expression).
- It then enters a loop, checking for either a `TOKEN_LPAREN` (indicating a function call) or a `TOKEN_LBRACKET` (indicating an array access).
- **For a member access**:
    - When a `TOKEN_DOT` is encountered, it expects an identifier.
    - It constructs an `ASTMemberAccessNode`.
- **For a struct initializer**:
    - When a `TOKEN_LBRACE` is encountered after an identifier (type name), it parses a list of field initializers like `.field = value`.
    - It constructs an `ASTStructInitializerNode`.
- **For a function call**:
    - It constructs an `ASTFunctionCallNode`.
    - It parses a comma-separated list of arguments until it finds a `TOKEN_RPAREN`.
    - It supports empty argument lists (`()`) and allows an optional trailing comma (e.g., `(a, b,)`).
- **For an array access or slice**:
    - It checks if the expression inside the brackets is a slice by looking ahead for a `TOKEN_RANGE` (`..`).
    - **If it is a slice**:
        - It constructs an `ASTArraySliceNode`.
        - It parses the optional start expression before the `..`.
        - It parses the optional end expression after the `..`.
        - It handles all forms of slices: `[start..end]`, `[..end]`, `[start..]`, and `[..]`.
    - **If it is a simple array access**:
        - It constructs an `ASTArrayAccessNode`.
        - It calls `parseExpression` to parse the index expression.
    - It expects a closing `TOKEN_RBRACKET` for both cases.
- The result of the postfix operation (e.g., the `ASTFunctionCallNode` or `ASTArraySliceNode`) becomes the new left-hand side expression for the next iteration of the loop, allowing for chaining.
- If no postfix operator is found, the loop terminates, and the function returns the constructed expression tree.


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

#### Parsing Logic (`parseExpression` and `parseAssignmentExpression`)
The parser handles assignments as the lowest-precedence expressions.

- `parseExpression()` calls `parseAssignmentExpression()`.
- `parseAssignmentExpression()` parses a higher-precedence expression and then checks for an `=` token or any compound assignment operator (`+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=`, `>>=`).
- If an assignment operator is found, it recursively calls itself to parse the right-hand side, building either an `ASTAssignmentNode` or an `ASTCompoundAssignmentNode`.
- Assignments are **right-associative** (e.g., `a = b = c` is `a = (b = c)`).

#### `ASTCompoundAssignmentNode`
Represents a compound assignment operation.
*   **Zig Code:** `a += 5`, `x *= y`
*   **Structure:**
    ```cpp
    struct ASTCompoundAssignmentNode {
        ASTNode* lvalue;
        ASTNode* rvalue;
        TokenType op;
    };
    ```

#### Parsing Logic (`parseBinaryExpr`)
The parser uses a **Pratt parsing** algorithm to handle binary expressions, which elegantly solves the problem of operator precedence and associativity.

- The entry point for binary expression parsing is `parsePrecedenceExpr(1)` (called by `parseAssignmentExpression`).
- The `parseBinaryExpr(min_precedence)` function is the core of the algorithm. It starts by parsing a `unary_expr` as the initial left-hand side.
- It then enters a loop, peeking at the next token. If the token is a binary operator with a precedence greater than or equal to `min_precedence`, it consumes the operator and recursively calls `parseBinaryExpr` to parse the right-hand side, but with a *higher* minimum precedence.
- This recursive process naturally builds the AST in the correct order. For example, in `2 + 3 * 4`, the parser will first parse `2`, see the `+`, then recursively call itself to parse the rest of the expression with a higher precedence, which will correctly group `3 * 4` as the right-hand side of the `+` operation.
- **Left-associativity** (for operators of the same precedence, like `10 - 4 - 2`) is handled by the `+ 1` adjustment to the precedence in the recursive call, which ensures that the loop continues for the first operator and groups `(10 - 4)` first.
- **Associativity:** Left-associativity for all operators is handled naturally by the precedence climbing algorithm. For operators of the same precedence (e.g., `a - b + c`), the loop in `parsePrecedenceExpr` continues, correctly grouping `(a - b)` first. Right-associativity is not used for any binary operators in this language.

#### Parsing Logic (`parseSwitchExpression`)
The `parseSwitchExpression` function handles the `switch` expression. It adheres to the grammar:
`'switch' '(' expr ')' '{' (prong (',' prong)* ','?)? '}'`
`prong ::= (expr (',' expr)* | 'else') '=>' expr`

- It consumes a `switch` token, a parenthesized expression for the condition, and an opening brace.
- It then enters a loop to parse one or more "prongs".
- For each prong, it checks for the `else` keyword. If not present, it parses a comma-separated list of one or more case expressions.
- It then requires a `=>` token, followed by the body of the prong, which is parsed as a full expression.
- The loop continues as long as there are commas separating the prongs.
- Finally, it expects a closing brace.
- It enforces several error conditions, such as a missing `=>`, a duplicate `else` prong, or an empty switch body.

**Operator Precedence Levels:**
| Precedence | Operators                      | Associativity |
|------------|--------------------------------|---------------|
| 10         | `*`, `/`, `%`                  | Left          |
| 9          | `+`, `-`                       | Left          |
| 8          | `<<`, `>>`                     | Left          |
| 7          | `&`                            | Left          |
| 6          | `^`                            | Left          |
| 5          | `|`                            | Left          |
| 4          | `==`, `!=`, `<`, `>`, `<=`, `>=` | Left          |
| 3          | `and`                          | Left          |
| 2          | `or`                           | Left          |
| 1          | `orelse`, `catch`              | Left          |

### Parser Robustness: Recursion Depth Limit
To prevent stack overflows when parsing deeply nested or complex expressions, the parser implements a recursion depth limit.

- **Mechanism**: A counter, `recursion_depth_`, is incremented at the start of all major recursive parsing functions, including `parsePrecedenceExpr`, `parseExpression`, `parseUnaryExpr`, and `parsePostfixExpression`. It is decremented before each function returns. The check in `parsePrecedenceExpr` is the most critical, as it handles the self-recursive calls that parse chained binary operators.
- **Limit**: The maximum depth is defined by `MAX_PARSER_RECURSION_DEPTH` (currently 255).
- **Behavior**: If the depth exceeds the limit, the parser calls `error()` and aborts compilation, preventing a crash.

This feature is a critical safeguard for the compiler's stability, especially given the limited resources of the target environment.

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
*   **Zig Code:** `*u8`, `const *MyStruct`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTPointerTypeNode
     * @brief Represents a pointer type.
     * @var ASTPointerTypeNode::base A pointer to the ASTNode for the type being pointed to.
     * @var ASTPointerTypeNode::is_const True if the pointer type is const-qualified.
     */
    struct ASTPointerTypeNode {
        ASTNode* base;
        bool is_const;
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
- A block with expression statements: `{ my_func(); 42; }`

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

### `ASTExpressionStmtNode`
Represents a statement that consists of a single expression followed by a semicolon. This is common for function calls made for their side effects.
*   **Zig Code:** `do_something();`, `_ = my_func();`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTExpressionStmtNode
     * @brief Represents a statement consisting of a single expression.
     * @var ASTExpressionStmtNode::expression The expression that forms the statement.
     */
    struct ASTExpressionStmtNode {
        ASTNode* expression;
    };
    ```

#### Parsing Logic (`parseStatement`)
The `parseStatement` function acts as a dispatcher. When it does not find a keyword that starts a specific statement (like `if`, `while`, `return`, etc.), it falls back to a default case where it attempts to parse an expression. If an expression is successfully parsed, it then requires a terminating semicolon. The resulting expression is then wrapped in an `ASTExpressionStmtNode` to represent it as a statement in the AST.

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

#### Parsing Logic (`parseIfStatement`)
The `parseIfStatement` function handles the `if-else` control flow structure. It adheres to the grammar:
`'if' '(' expr ')' block_statement ('else' block_statement)?`

- It consumes an `if` token, followed by a parenthesized expression parsed by `parseExpression`.
- It then requires a block statement (`{...}`) for the `then` branch, parsed by `parseBlockStatement`.
- It checks for an optional `else` token. If found, it requires a subsequent block statement for the `else` branch.
- Any deviation from this structure results in a fatal error.

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

#### Parsing Logic (`parseWhileStatement`)
The `parseWhileStatement` function is responsible for parsing a `while` loop. It adheres to the grammar:
`'while' '(' expr ')' statement`

- It consumes a `while` token, followed by a parenthesized expression parsed by `parseExpression`.
- It then requires a statement for the loop body. At this foundational stage, this must be a block statement (`{...}`), which is parsed by `parseBlockStatement`.
- Any deviation from this structure results in a fatal error.

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

#### Parsing Logic (`parseDeferStatement`)
The `parseDeferStatement` function handles the `defer` statement. It adheres to the grammar:
`'defer' statement`

- It consumes a `defer` token.
- It then requires a subsequent statement. Based on the current implementation phase, this must be a block statement (`{...}`), which is parsed by `parseBlockStatement`.
- Any deviation from this structure results in a fatal error.

### `ASTForStmtNode`
Represents a `for` loop, which iterates over an expression.
*   **Zig Code:** `for (my_array) |item| { ... }`, `for (0..10) |val, i| { ... }`
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

#### Parsing Logic (`parseForStatement`)
The `parseForStatement` function is responsible for parsing a `for` loop. It adheres to the grammar:
`'for' '(' expr ')' '|' IDENT (',' IDENT)? '|' statement`

- It consumes a `for` token, a parenthesized expression for the iterable, and an opening `|`.
- It then expects an identifier for the item capture variable.
- It checks for an optional comma followed by another identifier for the index capture variable.
- It requires a closing `|` to end the capture list.
- Finally, it requires a statement for the loop body, which, like `while` and `if`, must be a block statement at this stage.
- Any deviation from this structure results in a fatal error with a specific message.

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

#### Parsing Logic (`parseReturnStatement`)
The `parseReturnStatement` function handles the `return` statement. It adheres to the grammar:
`'return' (expr)? ';'`

- It consumes a `return` token.
- It then checks for a semicolon. If the next token is not a semicolon, it assumes an expression is present and calls `parseExpression` to parse it.
- Finally, it requires a terminating semicolon.
- Any deviation from this structure results in a fatal error.

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

#### Parsing Logic (`parseDeferStatement`)
The `parseDeferStatement` function handles the `defer` statement. It adheres to the grammar:
`'defer' statement`

- It consumes a `defer` token.
- It then requires a subsequent statement. Based on the current implementation phase, this must be a block statement (`{...}`), which is parsed by `parseBlockStatement`.
- Any deviation from this structure results in a fatal error.

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

#### Parsing Logic (`parseErrDeferStatement`)
The `parseErrDeferStatement` function handles the `errdefer` statement. It adheres to the grammar:
`'errdefer' statement`

- It consumes an `errdefer` token.
- It then requires a subsequent statement. Consistent with `defer`, this must be a block statement (`{...}`), which is parsed by `parseBlockStatement`.
- Any deviation from this structure results in a fatal error.

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
The `parseVarDecl` function is responsible for parsing variable and constant declarations. It follows the grammar:
`('var'|'const') IDENT ':' type_expr ('=' expr)? ';'`

- It consumes a `var` or `const` token.
- It expects an identifier, a colon, and a type expression (parsed via `parseType`).
- It then checks for an optional initializer, which starts with an equals sign.
- If an initializer is present, it is parsed by `parseExpression`.
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
The `parseFnDecl` function is responsible for parsing function declarations. It follows the grammar:
`'fn' IDENT '(' param_list ')' (type_expr | '->' type_expr)? block_statement`

- It consumes the `fn` keyword and the function's identifier.
- It parses the parameter list inside `()`.
- It then checks for a return type. The return type can be specified with an optional `->` token followed by a type expression, or just the type expression itself. If no return type is present before the opening `{` of the body, it defaults to `void`.
- After parsing the function signature, it calls `parseBlockStatement` to parse the function's body.

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

### `ASTStructDeclNode` and `ASTStructFieldNode`
Represents a `struct` definition. The declaration node contains a list of field nodes.
*   **Zig Code:** `struct { field1: i32, field2: bool }`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTStructFieldNode
 * @brief Represents a single field within a struct or union declaration.
     * @var ASTStructFieldNode::name The name of the field (interned string).
     * @var ASTStructFieldNode::type A pointer to an ASTNode representing the field's type.
     */
    struct ASTStructFieldNode {
        const char* name;
        ASTNode* type;
    };

    /**
     * @struct ASTStructDeclNode
     * @brief Represents a `struct` declaration. Allocated out-of-line.
     * @var ASTStructDeclNode::fields A dynamic array of pointers to ASTNode (of type NODE_STRUCT_FIELD).
     */
    struct ASTStructDeclNode {
        DynamicArray<ASTNode*>* fields;
    };
    ```

#### Parsing Logic (`parseStructDeclaration`)
The `parseStructDeclaration` function is responsible for parsing struct declarations. It can be invoked from `parsePrimaryExpr` to handle anonymous struct literals (e.g., in a variable assignment) or from `parseTopLevelItem` to handle top-level struct declarations. The function adheres to the grammar:
`'struct' '{' (field (',' field)* ','?)? '}'`
`field ::= IDENTIFIER ':' type`

- It consumes the `struct` and `{` tokens.
- It then enters a loop that continues as long as the next token is not `}`.
- Inside the loop, it parses a single field by expecting an identifier, a colon, and a type expression (parsed via `parseType`).
- It constructs an `ASTStructFieldNode` for each field, which is then wrapped in an `ASTNode` of type `NODE_STRUCT_FIELD`. This `ASTNode` is then appended to the `DynamicArray` in the `ASTStructDeclNode`.
- The loop correctly handles an optional trailing comma by checking for a comma after each field, but only if the next token is not the closing brace.
- It correctly handles empty structs (`{}`).
- Finally, it consumes the closing `}` token. Any deviation from this structure results in a fatal error.

### `ASTUnionDeclNode`
Represents a `union` definition.
*   **Zig Code:** `union { a: i32, b: f32 }`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTUnionDeclNode
     * @brief Represents a `union` declaration. Allocated out-of-line.
     * @var ASTUnionDeclNode::fields A dynamic array of pointers to ASTNode (of type NODE_STRUCT_FIELD) representing the union fields.
     */
    struct ASTUnionDeclNode {
        DynamicArray<ASTNode*>* fields;
    };
    ```

#### Parsing Logic (`parseUnionDeclaration`)
The `parseUnionDeclaration` function is responsible for parsing union declarations. It can be invoked from `parsePrimaryExpr` to handle anonymous union literals or from `parseTopLevelItem` to handle top-level declarations. The function's logic is nearly identical to that of `parseStructDeclaration`. It adheres to the grammar:
`'union' '{' (field (',' field)* ','?)? '}'`
`field ::= IDENTIFIER ':' type`

- It consumes the `union` and `{` tokens.
- It then enters a loop that continues as long as the next token is not `}`.
- Inside the loop, it parses a single field by expecting an identifier, a colon, and a type expression (parsed via `parseType`).
- It constructs an `ASTStructFieldNode` for each field, which is then wrapped in an `ASTNode` of type `NODE_STRUCT_FIELD`. This `ASTNode` is then appended to the `DynamicArray` in the `ASTUnionDeclNode`. This is the same node type used for struct fields, as the syntax is identical.
- The loop correctly handles an optional trailing comma.
- It correctly handles empty unions (`{}`).
- Finally, it consumes the closing `}` token. Any deviation from this structure results in a fatal error.

### `ASTEnumDeclNode`
Represents an `enum` definition.
*   **Zig Code:** `enum { Red, Green, Blue }`, `enum(u8) { A = 1, B = 2 }`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTEnumDeclNode
     * @brief Represents an `enum` declaration. Allocated out-of-line.
     * @var ASTEnumDeclNode::backing_type The optional explicit backing type for the enum (can be NULL).
     * @var ASTEnumDeclNode::fields A dynamic array of pointers to ASTVarDeclNode representing the enum fields, allowing for explicit values.
     */
    struct ASTEnumDeclNode {
        ASTNode* backing_type; // Can be NULL
        DynamicArray<ASTNode*>* fields;
    };
    ```

### Enum Type Checking
The `TypeChecker` validates enums by:
1.  **Backing Type Verification**: Ensures the backing type is a C89-compatible integer (defaults to `i32`).
2.  **Value Calculation**: Handles explicit values and Zig-style auto-incrementing.
3.  **Range Checking**: Verifies each member value fits within the backing type's range.
4.  **Nominal Typing**: Enums are distinct types based on their declaration identity.
5.  **Dot Notation Access**: Supports `EnumName.MemberName` via `visitMemberAccess`.
6.  **C89 Compatibility**: Allows implicit conversion from enums to integer types.

#### Parsing Logic (`parseEnumDeclaration`)
The `parseEnumDeclaration` function handles anonymous enum literals. It is invoked from `parsePrimaryExpr` when an `enum` keyword is encountered. The function adheres to the grammar:
`'enum' ('(' type ')')? '{' (field (',' field)* ','?)? '}'`
`field ::= IDENTIFIER ('=' expr)?`

- It consumes the `enum` token.
- It then checks for an optional parenthesized backing type, which is parsed by `parseType`.
- It requires an opening `{` to start the member list.
- It enters a loop to parse the members, which continues as long as the next token is not `}`.
- Inside the loop, it expects an identifier for the member's name.
- It checks for an optional `=` followed by an initializer expression, which is parsed by `parseExpression`.
- For simplicity and to match the AST design, each enum member is stored as an `ASTVarDeclNode`.
- The loop correctly handles an optional trailing comma.
- It correctly handles empty enums (`{}`).
- Finally, it consumes the closing `}` token. Any deviation from this structure results in a fatal error.

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

#### Parsing Logic (`parseUnaryExpr` for `try`)
The `try` keyword is parsed as a prefix unary operator within the `parseUnaryExpr` function.
- When a `TOKEN_TRY` is encountered, it is consumed.
- The function then recursively calls `parseUnaryExpr` to handle the subsequent expression. This allows `try` to correctly compose with other unary operators (e.g., `try !fallible_operation()`).
- An `ASTTryExprNode` is created, wrapping the parsed expression.


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

### `peekNext()`
The `peekNext()` function provides a one-token lookahead without consuming the current token. This is useful in situations where the parser needs to make a decision based on the token that follows the current one. For example, it can be used to distinguish between an array access `[i]` and an array slice `[i..]`.
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

#### Parsing Logic (`parsePrecedenceExpr` for `catch`)
The `catch` expression is parsed as a binary operator within `parsePrecedenceExpr` with a precedence of 1.
- When `TOKEN_CATCH` is encountered, it is consumed.
- The parser optionally handles the `|err|` capture syntax.
- The fallback expression is parsed recursively.

### `ASTOrelseExprNode`
Represents an `orelse` expression, providing a fallback value in case of an error or optional type.
*   **Zig Code:** `my_value orelse default_value`
*   **Structure:**
    ```cpp
    /**
     * @struct ASTOrelseExprNode
     * @brief Represents an `orelse` expression. Allocated out-of-line.
     * @var ASTOrelseExprNode::payload The expression that may produce an error or be optional.
     * @var ASTOrelseExprNode::else_expr The expression to evaluate if the payload is an error or null.
     */
    struct ASTOrelseExprNode {
        ASTNode* payload;
        ASTNode* else_expr;
    };
    ```

#### Parsing Logic (`parsePrecedenceExpr` for `orelse`)
The `orelse` expression is handled similarly to `catch` within `parsePrecedenceExpr` (precedence 1). It takes the current left-hand side as the payload and parses the subsequent expression as the fallback.

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

## 11. Error Set Definitions

### Syntax
```zig
// Named error set
const MyErrors = error { FileNotFound, PermissionDenied };

// Anonymous error set
fn open() error{FileNotFound}!void { ... }

// Error set merging
const AllErrors = Errors1 || Errors2;
```

### AST Nodes

#### `ASTErrorSetDefinitionNode`
Represents a definition of error tags.
```cpp
struct ASTErrorSetDefinitionNode {
    const char* name; // NULL for anonymous
    DynamicArray<const char*>* tags;
};
```

#### Parsing Logic (`parseErrorSetDefinition`)
The `parseErrorSetDefinition` function handles error set declarations like `error { A, B }`. It consumes the `error` keyword and the braced list of identifiers. It also registers the error set in the `ErrorSetCatalogue`.

#### `ASTErrorSetMergeNode`
Represents the merging of two error sets.
```cpp
struct ASTErrorSetMergeNode {
    ASTNode* left;
    ASTNode* right;
};
```

#### Parsing Logic (`parsePrecedenceExpr` for `||`)
The error set merge operator `||` is parsed within `parsePrecedenceExpr` (or recursively in `parseType`) when two error sets are combined.

### Detection and Cataloguing
Error sets are parsed and added to the `ErrorSetCatalogue` in the `CompilationUnit` during the parsing phase. This allows for documentation and analysis of all errors used in the codebase, even though they are eventually rejected by the `C89FeatureValidator`.

## 12. Try Expression Detection (Task 143)

### AST Node
```cpp
struct ASTTryExprNode {
    ASTNode* expression;  // The expression being tried
};
```

### Detection Context
Try expressions are detected in various contexts to provide detailed analysis:
1. **Return statements**: `return try func();` -> `context: "return"`
2. **Assignments**: `x = try func();` -> `context: "assignment"`
3. **Function arguments**: `foo(try bar());` -> `context: "call_argument"`
4. **Variable declarations**: `var x = try init();` -> `context: "variable_decl"`
5. **Conditional**: `if (try func()) { ... }` -> `context: "conditional"`
6. **Binary Operations**: `try a() + try b()` -> `context: "binary_op"`
7. **Nested expressions**: `try (try inner())` -> `context: "nested_try"`

### Catalogue Information
Each try expression is recorded in the `TryExpressionCatalogue` with:
- **Source location**: Exact position in the file.
- **Context type**: String representation of the usage context.
- **Inner expression type**: The resolved type of the expression being tried (e.g., `!i32`).
- **Result type**: The type after unwrapping (e.g., `i32`).
- **Nesting depth**: Tracking how deep the `try` is nested within other `try` expressions.

## 13. Catch Expression Detection (Task 144)

### AST Node
```cpp
struct ASTCatchExprNode {
    ASTNode* payload;        // Expression that might error
    const char* error_name;  // NULL or identifier name (from |err|)
    ASTNode* else_expr;      // Handler expression
};
```

### Detection Context
Catch expressions are catalogued in `CatchExpressionCatalogue` with:
- **Source location**: Position of the `catch` keyword.
- **Context type**: e.g., "assignment", "variable_decl", "return".
- **Error type**: Resolved type of the payload (the error union).
- **Handler type**: Resolved type of the `else_expr`.
- **Result type**: Type after the catch operation.
- **Chaining info**: Whether it is part of a chain (`a catch b catch c`) and its index in that chain.
- **Error parameter**: Name of the captured error variable, if any.

## 14. Orelse Expression Detection

### AST Node
```cpp
struct ASTOrelseExprNode {
    ASTNode* payload;        // Expression that might be null
    ASTNode* else_expr;      // Fallback expression
};
```

### Catalogue Information
Orelse expressions are catalogued in `OrelseExpressionCatalogue` with:
- **Source location**: Position of the `orelse` keyword.
- **Context type**: usage context.
- **Left type**: Type of the payload (typically an optional type).
- **Right type**: Type of the fallback expression.
- **Result type**: Resolved type after the orelse operation.

## 15. Import Statements

### Syntax
```zig
const std = @import("std");
```

### AST Node

#### `ASTImportStmtNode`
Represents an `@import` expression.
```cpp
struct ASTImportStmtNode {
    const char* module_name;
};
```

## 16. Error-Returning Function Detection (Task 142)

### Detection Criteria
A function is catalogued as error-returning when its resolved return type is:
1. Error union (`!T`) → `TYPE_ERROR_UNION`
2. Error set (`error{A,B}`) → `TYPE_ERROR_SET`
3. Named error set alias (`MyErrorSet`) → `TYPE_ERROR_SET`

### Cataloguing Process
During the `C89FeatureValidator` pass (which now runs AFTER `TypeChecker`):
1. Resolve the function's return type using the symbol table (populated by `TypeChecker`).
2. Check if the return type kind is `TYPE_ERROR_UNION` or `TYPE_ERROR_SET`.
3. Record in `ErrorFunctionCatalogue` with:
   - Function name (interned string)
   - Resolved return type pointer
   - Source location
   - Generic flag (comptime params)
   - Parameter count

### Rejection
`C89FeatureValidator` rejects all catalogued functions with specific diagnostics:
- "Function 'X' returns error type 'Y' (non-C89)"

## 17. Compile-Time Operation Node Types

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

#### Parsing Logic (`parseComptimeBlock`)
The `parseComptimeBlock` function is responsible for parsing a `comptime` block. It is invoked from `parseStatement` when a `comptime` keyword is found. The function adheres to the grammar:
`'comptime' '{' expression '}'`

- It consumes the `comptime` and `{` tokens.
- It then calls `parseExpression` to parse the expression within the block.
- It requires that the block contains exactly one expression.
- Finally, it consumes the closing `}` token. Any deviation from this structure results in a fatal error.

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

After printing the message (on Windows), the function **always** calls `abort()`. This terminates the program immediately, preventing any further processing of the invalid source code. This applies to both syntax errors and critical runtime issues like out-of-memory conditions. An out-of-memory condition during AST node allocation is considered a non-recoverable error, and immediate termination via `abort()` is the desired behavior for this bootstrap compiler.

This approach avoids forbidden standard library dependencies like `<cstdio>` (for `fprintf`) while still providing useful diagnostic messages on the primary development and target platform.

## 15. Parser Lifetime and Memory Safety

The `Parser` is designed with clear ownership semantics to ensure memory safety and prevent unintended side effects.

-   **Token Ownership:** The `Parser` does **not** own the token stream it processes. It receives a `const Token*` in its constructor, making it a read-only consumer of tokens. This `const` contract guarantees that the parser cannot modify the token stream. The ownership and stability of the token stream are managed by the `TokenSupplier` (which is in turn owned by the `CompilationUnit`). The `TokenSupplier` guarantees that the pointer to the token data is stable and will not be invalidated by subsequent memory allocations, which is critical for preventing dangling pointer bugs. The `CompilationUnit` ensures that the tokens' lifetime exceeds that of any `Parser` instance created to view them.

-   **AST Node Ownership:** The `Parser` does **not** own the AST nodes it creates. All `ASTNode` objects are allocated from an `ArenaAllocator` that is passed into the parser's constructor. The arena's owner is responsible for managing its lifetime and freeing the memory when the AST is no longer needed, typically by using an `ArenaLifetimeGuard` in test scenarios.

-   **Non-Copyable by Design:** The `Parser`'s copy constructor and assignment operator are private. This is a deliberate design choice to prevent shallow copies. A shallow copy would result in multiple `Parser` instances sharing pointers to the same token stream, arena, and symbol table, leading to memory corruption and double-free errors. By making the class non-copyable, the compiler enforces a clear ownership model where the `CompilationUnit` exclusively manages the `Parser`'s lifetime. The `createParser()` method returns a `Parser*` to the arena-allocated object, ensuring that its lifetime is tied to the compilation session.

This design decouples the parser from memory management concerns, making it a focused and predictable component responsible solely for syntactic analysis.

## 16. Lifetime Analysis Phase

The Lifetime Analysis phase is a critical semantic analysis pass that follows the Type Checker. Its purpose is to identify memory safety issues at compile-time, specifically dangling pointers created by returning pointers to local (stack-allocated) variables.

### Timing and Dependencies
- **Placement:** It runs after the `TypeChecker` has completed and before the `CodeGenerator`.
- **Dependencies:** It relies on the `SymbolTable` being fully populated with semantic flags (`SYMBOL_FLAG_LOCAL`, `SYMBOL_FLAG_PARAM`) by the `TypeChecker`.
- **Input:** It traverses the AST produced by the `Parser`.

### Analysis Rules
1. **Direct Dangling Pointers:** Identifies immediate returns of local addresses, such as `return &local_var;` or `return &parameter;`.
2. **Indirect Dangling Pointers:** Tracks assignments to pointer variables. If a local pointer is assigned the address of a local variable (e.g., `p = &x;`), returning that pointer (`return p;`) is flagged as a violation.
3. **Safety of Parameters:** Returning a pointer *value* passed as a parameter (e.g., `fn f(p: *i32) -> *i32 { return p; }`) is considered safe, as the caller manages its lifetime. However, returning the *address* of the parameter itself (`return &p;`) is a violation.
4. **Global Persistence:** Addresses of global variables are always safe to return.

### Implementation Strategy
The `LifetimeAnalyzer` uses a visitor pattern to traverse the AST. It maintains a list of `PointerAssignment` records for the current function to track the provenance of local pointer variables. It reports `ERR_LIFETIME_VIOLATION` through the `ErrorHandler`, allowing compilation to continue and identify multiple issues in a single pass.

## 17. Double Free Analysis Phase

The Double Free Analysis phase (Task 127 & 128) detects memory safety issues related to the `ArenaAllocator` interface (`arena_alloc`, `arena_free`).

### Allocation Site Tracking
To improve diagnostics, the analyzer tracks the `SourceLocation` of every allocation site. This information is preserved in the `TrackedPointer` structure and used to enhance error messages.

### Enhanced Diagnostics
1. **Memory Leaks**: When a pointer is not freed at scope exit or is leaked through reassignment, the warning message includes the location of the original `arena_alloc` call.
   - *Example*: `Memory leak: 'p' not freed (allocated at main.zig:10:15)`
2. **Double Frees**: When a pointer is freed more than once, the error message includes the original allocation site and the location where it was first freed.
   - *Example*: `Double free of pointer 'p' (allocated at main.zig:10:15) - first freed at main.zig:12:5`
3. **Deallocation Site Tracking (Task 129)**: Double free errors now provide context if the first free occurred via a `defer` or `errdefer` statement.
   - *Example*: `Double free of pointer 'p' ... - first freed via defer at main.zig:5:5 (deferred free at main.zig:6:10)`
4. **Ownership Transfer Tracking (Task 129)**: Detects when a pointer is passed to a function call (other than `arena_free`), conservatively assuming ownership might have been transferred.
   - *Example*: `Pointer 'p' transferred (at main.zig:8:5) - receiver responsible for freeing`
5. **Uninitialized Frees**: Detects and warns when a pointer that was never allocated is passed to `arena_free`.

### Implementation Details
The analyzer records locations in:
- `visitVarDecl`: Captures location from the initializer if it's an `arena_alloc` call.
- `visitAssignment`: Updates the tracked allocation site when a pointer is reassigned to a new `arena_alloc` result.
- `visitFunctionCall`: Records the `first_free_loc` when `arena_free` is first called on an allocated pointer.

### Control Flow Analysis (Task 130)
The analyzer is path-aware, tracking allocation states across branches and loops to detect memory safety issues in complex control flow.

#### Memory-Efficient State Tracking
To support deep branch nesting on 1990s hardware, the analyzer uses an `AllocationStateMap` that stores state changes as a linked list of **deltas** pointing to a parent scope. This architecture provides several benefits:
- **O(1) Forking**: Creating a new branch state only requires creating a new map pointing to the current one.
- **O(K) Merging**: Merging only requires iterating over the variables modified in the branches (K).
- **Recursive Lookup**: `getState()` traverses the delta list to find the most recent state of a variable.

#### Analysis Rules for Milestone 4 Constructs
1. **Branching**: For `if`, `switch`, `catch`, and `orelse` constructs, the analyzer forks the current state for each branch. This allows independent tracking of allocations and deallocations within each path.
2. **Merging**: At control flow join points, the branched states are merged back using conservative rules:
   - If a pointer's state differs between branches (e.g., `AS_ALLOCATED` on one path and `AS_FREED` on another), its state becomes `AS_UNKNOWN` to avoid false positives.
3. **Try Expression**: The `try` keyword introduces uncertainty because it may return early from the function. After a `try` expression, all currently `AS_ALLOCATED` pointers transition to `AS_UNKNOWN`.
4. **Loops**: For `while` and `for` loops, any variable modified within the loop body is transitioned to `AS_UNKNOWN`, reflecting the uncertainty of potential multiple iterations.

### Double-Free Analysis Details (Tasks 131-132)

The `DoubleFreeAnalyzer` employs a conservative, path-aware strategy to identify deallocation risks in complex control flow.

#### Multiple Deallocations Detection
The analyzer identifies potential double frees by tracking the transition to the `AS_FREED` state.
-   **Linear Paths**: A definite double free (`ERR_DOUBLE_FREE`) is reported if `arena_free` is called on a pointer already in the `AS_FREED` state.
-   **Deferred Actions**: `defer` and `errdefer` statements are queued and executed in LIFO order at scope exit. The analyzer tracks the source location of the first deallocation (including its defer context) to provide detailed diagnostics.
-   **Nested Scopes**: Correct depth handling ensures that `defer` statements in nested blocks are executed only when their defining block is exited, correctly modeling runtime behavior.

#### Flagging Double-Free Risks
To minimize false negatives while maintaining simplicity, the analyzer flags risks where it cannot prove safety:
-   **Conservative Merging**: When control flow paths merge (e.g., after an `if-else`), any pointer whose state differs between branches is transitioned to `AS_UNKNOWN`.
-   **Aliasing Design Choice**: In the bootstrap phase, the compiler **does not track aliases** (multiple variables pointing to the same allocation). Assigning an allocated pointer to another variable transitions the target variable to `AS_UNKNOWN`. This avoids the complexity of full pointer alias analysis while still catching basic mistakes on the original tracked pointer.
-   **Function Call Conservatism**: Passing a pointer to any function (except `arena_free`) marks it as `AS_TRANSFERRED`. This stops tracking for that pointer to avoid false positives, instead issuing a `WARN_TRANSFERRED_MEMORY` warning to the developer.

## 18. Non-C89 Type Detection

### Error Union Types (!T)
The parser recognizes `!` as an error union type operator:
- Syntax: `!` payload_type
- Example: `!u32`, `![]const u8`
- Rejected by C89FeatureValidator

### Optional Types (?T)
The parser recognizes `?` as an optional type operator:
- Syntax: `?` payload_type
- Example: `?i32`, `?*u8`
- Rejected by C89FeatureValidator

### Detection Strategy
Both validators traverse type expressions recursively:
1. C89FeatureValidator: Reports fatal errors
2. TypeChecker: Logs locations for documentation

## 19. Generic Function Detection (Tasks 156-160)

Zig's compile-time generic functions (often called "templates" in older documentation) are detected and catalogued during semantic analysis, then subsequently rejected by the `C89FeatureValidator` as non-C89 compatible features. This process fulfills Tasks 156 through 160 by identifying, tracking, and validating the safety (via rejection) of generic instantiations.

### Detection Mechanism

The compiler identifies generic function calls using two primary strategies:

1.  **Explicit Generic Calls**: A function call is considered explicitly generic if one or more of its arguments is a type expression (e.g., `max(i32, a, b)`).
2.  **Implicit Generic Calls**: A function call is considered implicitly generic if the callee is a function symbol marked as `is_generic`. Symbols are marked as generic during parsing if their declaration contains `comptime` parameters.

### `isTypeExpression` Helper

The `isTypeExpression` helper function is used by both the `C89FeatureValidator` and the `TypeChecker` to identify AST nodes that represent types. It recognizes:
-   Built-in primitive type names (e.g., `i32`, `u8`, `bool`, `type`).
-   Type expression nodes like `NODE_POINTER_TYPE`, `NODE_ARRAY_TYPE`, etc.
-   Identifiers that resolve to symbols of kind `SYMBOL_TYPE`.

### Cataloguing (GenericCatalogue)

Detected generic instantiations are recorded in the `GenericCatalogue` owned by the `CompilationUnit`. Each entry includes:
-   The function name.
-   Up to 4 resolved type arguments (capturing the actual types passed at the call site).
-   The source location of the call.

This catalogue provides a comprehensive record of all generic features used in the source code, even though they are eventually rejected to maintain C89 compatibility.

### Rejection Strategy

All generic function calls are rejected by the `C89FeatureValidator` because:
1.  Standard C89 does not support compile-time type parameters or generics.
2.  Zig's `comptime` execution model has no direct equivalent in the target legacy environments.

## 21. Multi-File Considerations for Milestone 6

The current implementation assumes single-file compilation but includes data structures designed for modular compilation in Milestone 6.

### 21.1 Module Field in ASTNode
Every `ASTNode` stores a `module` field, which is a pointer to the interned logical name of the module (e.g., "main", "std"). This field is populated by the `Parser` using the module name provided by the `CompilationUnit`.

### 21.2 Design for Milestone 6
- **Import System**: `@import` will be processed during parsing to pull in external declarations.
- **Catalogue Merging**: Specialized catalogues (e.g., `GenericCatalogue`) support merging to track cross-module feature usage.
- See `docs/multi_file_considerations.md` and `docs/compilation_model.md` for more details.

## 20. Parser Path for Non-C89 Features (Task 150)

To support accurate diagnostics and future translation planning, the RetroZig parser is intentionally designed to recognize a subset of modern Zig features, even though they are rejected by the `C89FeatureValidator` before code generation.

### 20.1 Purpose of Detection
- **Comprehensive Cataloguing**: By parsing and resolving these features, the compiler can maintain detailed catalogues (e.g., `ErrorSetCatalogue`, `GenericCatalogue`) that inform Milestone 5 translation strategies.
- **Type-Aware Rejection**: The `TypeChecker` (Pass 0) resolves the semantics of these features (like error union implicit wrapping), allowing the `C89FeatureValidator` (Pass 1) to issue more precise diagnostics (e.g., "Function 'X' returns error type 'Y'") rather than simple syntax errors.

### 20.2 Implementation Highlights
- **Error Handling**: The parser handles `try`, `catch`, `orelse`, and `errdefer` using standard Zig precedence rules. Error sets and error unions (`!T`) are parsed as types. The `.?` operator is recognized by the lexer and strictly rejected as non-C89.
- **Generics**: Function declarations support `comptime` parameters, and function calls support explicit type arguments. The `TypeChecker` identifies both explicit and implicit generic calls and populates the `GenericCatalogue` with resolved argument types for each instantiation site, enabling detailed diagnostic reporting.
- **Imports**: `@import` is recognized as a primary expression for the purpose of identifying external dependencies, though it is currently strictly rejected.

### 20.3 Rejection via Validation
The `C89FeatureValidator` ensures that none of these modern constructs proceed to the code generation phase. It recursively traverses the AST and issues fatal errors for any node that represents a non-C89 feature or has an associated error-related type.

## 21. Name Mangling for C89 Compatibility

When a function is declared, the `TypeChecker` computes a mangled name:
- **Non-generic functions**: same name (if valid) or prefixed/sanitized.
- **Generic instantiations**: encode type parameters in the name.
- **Module prefixes**: added when imports are implemented (Milestone 6).

Example: `fn max(comptime T: type, a: T, b: T) T` called as `max(i32, x, y)`
Mangled: `max__i32` (if i32 is the only type parameter).

This mangled name is stored in the `Symbol` table and used by the code generator and catalogues.

---

## Deprecated

This section contains documentation that is outdated but preserved for historical context.

### 11. Future AST Node Requirements

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
    *   `AsyncExprNode`: For `async` function calls. (Note: The `async` keyword is not currently recognized by the lexer, so parsing for this node is not implemented.)
    *   `AwaitExprNode`: For the `await` expression.
    *   `SuspendStmtNode`: For the `suspend` statement.
    *   `ResumeStmtNode`: For the `resume` statement.

*   **Compile-Time Operations:**
    *   `ComptimeBlockNode`: For `comptime` blocks. (DONE)
