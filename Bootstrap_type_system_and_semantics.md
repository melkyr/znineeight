# Bootstrap Type System & Semantic Analysis

This document outlines the design and implementation of the type system and semantic analysis phase for the RetroZig bootstrap compiler.

## 1. Scope Management

Scope management is the process of tracking declared identifiers (symbols) and determining where they are visible. Our compiler uses a hierarchical scope system, allowing for features like variable shadowing and ensuring that variables defined in an inner scope are not accessible from an outer scope.

### 1.1. Core Data Structures

#### `Symbol` Struct
The `Symbol` struct is the fundamental unit for tracking an identifier. It stores all the necessary information for a single named entity.

```cpp
struct Symbol {
    const char* name;          // The name of the symbol (interned string).
    SymbolType type;           // The kind of symbol (variable, function, etc.).
    SourceLocation location;   // Where the symbol is defined in the source code.
    ASTNode* details;          // A pointer to the defining AST node.
    unsigned int scope_level;  // The depth of the scope where it is defined.
    unsigned int flags;        // Additional info (e.g., constness).
};
```

#### `SymbolBuilder` Class
To simplify the creation of `Symbol` objects, a `SymbolBuilder` class is used. It provides a fluent interface (method chaining) to construct a `Symbol` piece by piece, which is cleaner than using a large constructor.

```cpp
// Example Usage
Symbol s = SymbolBuilder(arena)
               .withName("my_var")
               .ofType(SYMBOL_VARIABLE)
               .atLocation(location)
               .definedBy(ast_node)
               .inScope(current_scope_level)
               .withFlags(FLAG_CONST)
               .build();
```

#### `SymbolTable` Class
The `SymbolTable` is the central component for managing scopes. It implements a stack of `Scope` objects. The global scope is at the bottom of the stack, and new scopes are pushed on top as the parser enters nested blocks (like function bodies or `{...}` blocks).

-   **`enterScope()`**: Pushes a new, empty `Scope` onto the stack.
-   **`exitScope()`**: Pops the current `Scope` off the stack, effectively destroying all symbols defined within it.
-   **`insert(Symbol)`**: Adds a new symbol to the current (topmost) scope. It also checks for and rejects duplicate symbol definitions within the same scope.
-   **`lookup(name)`**: Searches for a symbol by name. The search begins in the current scope and proceeds outwards towards the global scope. This ensures that inner variables correctly "shadow" outer variables with the same name.

### 1.2. Integration with the Parser

The `Parser` is responsible for driving the scope management process.

-   When the parser encounters a `{` token (the beginning of a `parseBlockStatement` or `parseFnDecl`), it calls `sym_table->enterScope()`.
-   When it encounters the matching `}` token, it calls `sym_table->exitScope()`.
-   When it successfully parses a variable declaration (`parseVarDecl`), it uses the `SymbolBuilder` to create a `Symbol` and calls `sym_table->insert()` to add it to the current scope.

### 1.3. Symbol Visibility and Lifetime

-   **Visibility**: A symbol is visible (accessible) in the scope where it is defined and in all nested (child) scopes.
-   **Lifetime**: A symbol's lifetime is tied to its scope. When a scope is exited, all symbols defined within it are effectively destroyed and can no longer be accessed. Because all `Symbol` objects and their names (via the `StringInterner`) are allocated in an `ArenaAllocator`, no explicit memory deallocation is needed. The memory is reclaimed when the arena is reset at the end of the compilation phase.
