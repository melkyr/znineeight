# Compilation Model

This document describes the overall compilation model of the RetroZig bootstrap compiler.

## Single-File Compilation (Current)

In Milestones 1-5, the compiler operates primarily on a single-file basis.

1.  **Source Loading**: The `CompilationUnit` loads a single source file.
2.  **Lexing**: The source is converted into a token stream.
3.  **Parsing**: The `Parser` builds an AST from the tokens. All nodes are assigned the module name derived from the input filename.
4.  **Semantic Analysis**:
    -   **Name Collision Detection**: Checks for duplicate names in the same scope.
    -   **Type Checker (Pass 0)**: Resolves types and validates basic operations. Populates catalogues (Generic, ErrorSet, etc.).
    -   **Signature Analyzer (Pass 0.5)**: Enforces C89-compatible function signatures.
    -   **C89 Feature Validator (Pass 1)**: Rejects any modern Zig features (like generics or error handling constructs) before code generation.
5.  **Static Analysis** (Optional): Lifetime, Null Pointer, and Double Free analyzers run on the validated AST.
6.  **Code Generation**: (Milestone 5) C89 code is emitted from the AST.

## Multi-File Compilation (Milestone 6)

Milestone 6 introduces `@import` support and a modular compilation pipeline.

### Recursive Import Resolution

The compiler uses a recursive, multi-pass loading strategy:
- **Discovery**: When the `Parser` encounters an `@import("path.zig")`, it records the requirement in the current module's `ASTImportStmtNode`.
- **Recursive Loading**: The `CompilationUnit` resolves these paths relative to the current module's directory. It uses normalized, interned filenames to avoid redundant parsing and detects circular dependencies via a filename stack.
- **Unit Aggregation**: All parsed modules are stored in a single `CompilationUnit`, which manages the overall lifecycle.

### Module-Isolated Analysis

To prevent global state leakage, each module is analyzed in its own context:
- **Per-Module Symbol Tables**: Each module has its own `SymbolTable`. `SymbolTable::lookupWithModule` is used for cross-module member access (e.g., `utils.add`).
- **Feature Catalogues**: Analysis catalogues (Generics, ErrorSets, etc.) are moved from the unit to the individual `Module`.
- **Pipeline Context Switching**: The `CompilationUnit` executes each analysis pass (Type Checking, C89 Validation, etc.) by iterating through all modules and setting the active module context for each one.

### Cross-Module Generic Specialization

Generic functions and types from imported modules are handled by tracking their source module:
- Instantiation requests from importing modules are recorded with the target module's name.
- The `C89Emitter` uses this information to generate unique, mangled C symbols (e.g., `z_TargetModule_GenericFn_T`) in the appropriate translation unit.

## Resource Management

Given the <16MB memory limit, the compilation model relies heavily on:
-   **Arena Allocation**: All AST nodes and analysis metadata are allocated in a single arena that is cleared between compilation sessions.
-   **String Interning**: All identifiers, module names, and error messages are interned to minimize string storage overhead.
