# Bootstrap Type System & Semantic Analysis

This document outlines the design and implementation of the foundational components for the type system and semantic analysis phase of the RetroZig bootstrap compiler.

## Milestone 4: Foundational Work

### Task 81: Core Type System Structures (Completed)

The initial type system was implemented to support a subset of types that are directly compatible with C89, which is the bootstrap compiler's target.

**Supported Types:**
*   **Primitives:** `i8`-`i64`, `u8`-`u64`, `isize`, `usize`, `bool`, `f32`, `f64`, `void`
*   **Pointers:** `*T` (Single level)

The core structures, `Type` and `TypeKind`, were defined in `src/include/type_system.hpp` to represent these types within the compiler's internal data structures.

### Task 82: Minimal Symbol Table (Completed)

A foundational `SymbolTable` was implemented to store information about named entities (symbols) in the code.

**Key Components:**
*   **`Symbol` Struct:** A structure in `src/include/symbol_table.hpp` that holds the name, kind (variable, function, etc.), type, and a pointer to the AST node where the symbol was defined.
*   **`SymbolTable` Class:** A class that manages a collection of symbols.
    *   It uses a `DynamicArray` for symbol storage to adhere to the project's memory constraints.
    *   It provides methods to `insert` a new symbol and `lookup` an existing symbol by name.
*   **Parser Integration:** The `Parser` was updated to hold a pointer to a global `SymbolTable`, and the `parseVarDecl` function was updated to register new variable symbols.

### Task 83: Basic Scope Management (Completed)

To support nested scopes (e.g., variables defined inside a function), a basic scope management system was implemented. This system allows for correct symbol resolution and variable shadowing.

**Design:**
The implementation uses a stack-based scope management system, where each scope is represented by a `SymbolTable`. Scopes are chained together, with each table holding a pointer to its parent.

*   **`SymbolTable` Enhancements:**
    *   A `parent` pointer was added to the `SymbolTable` class, allowing scopes to be linked in a hierarchy.
    *   The `lookup` method was updated to perform a chained lookup. If a symbol is not found in the current table, the lookup continues up the chain to the parent scope, and so on, until the global scope is reached.
    *   The `insert` method was modified to only check for duplicate symbols within the *current* scope. This allows a local variable to "shadow" a global variable with the same name.

*   **`Parser` Integration:**
    *   The `Parser` now manages a `current_scope_` pointer, which always points to the symbol table of the currently active scope.
    *   When the parser enters a construct that defines a new scope (such as a function body or a block statement), it creates a new `SymbolTable`, sets its parent to the `current_scope_`, and then updates `current_scope_` to point to the new table.
    *   When the parser exits a scope, it restores the `current_scope_` to the parent of the current table, effectively "popping" the scope from the stack.
    *   The `parseVarDecl` function was updated to insert new variable symbols into the `current_scope_`, ensuring they are registered in the correct scope.
