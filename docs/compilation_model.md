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

Milestone 6 introduces `@import` support and a modular compilation model.

### Parse-Time Imports (Simpler Model)

The bootstrap compiler will use a parse-time import strategy:
- When the `Parser` encounters `@import("filename")`, it triggers the `CompilationUnit` to locate and parse the referenced file.
- The results are merged into the existing compilation context.

### Module-Aware Symbol Tables

Symbols will be tracked with module context to prevent collisions between different files.
-   `SymbolTable::lookupWithModule` allows explicit module-prefixed lookups.

### Cross-Module Generic Detection

Generic functions from other modules will be detected through catalogue merging:
- Each parsed module contributes to a global `GenericCatalogue`.
- Instantiations are tracked with their originating module name to ensure unique specialization in the generated C code.

## Resource Management

Given the <16MB memory limit, the compilation model relies heavily on:
-   **Arena Allocation**: All AST nodes and analysis metadata are allocated in a single arena that is cleared between compilation sessions.
-   **String Interning**: All identifiers, module names, and error messages are interned to minimize string storage overhead.
