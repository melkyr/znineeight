# Bootstrap Type System & Semantic Analysis

This document outlines the work being done for Milestone 4: Bootstrap Type System & Semantic Analysis.

## Summary of Previous Work (Tasks 81 & 82)

### Task 81: Core Type System Definition

This task introduced the foundational data structures for the compiler's type system, focusing on types that have a direct mapping to C89. This ensures that the bootstrap compiler can correctly represent and understand the types it will eventually use to generate C code.

The following types are now supported:

*   **Primitives:** `i8`-`i64`, `u8`-`u64`, `isize`, `usize`, `bool`, `f32`, `f64`, `void`
*   **Pointers:** `*T` (Single level)

### Task 82: Symbol Table Implementation

This task introduced the initial `Symbol` and `SymbolTable` classes, a foundational component for the semantic analysis phase of the compiler.

Key changes include:

*   A new header file `src/include/symbol_table.hpp` defining the `Symbol` struct and `SymbolTable` class.
*   A new implementation file `src/bootstrap/symbol_table.cpp` with a single, global scope implementation.
*   Integration of the `SymbolTable` into the `Parser` class.
*   The addition of new unit tests for the `SymbolTable` and integration tests for the parser.
*   A comprehensive update of all existing parser tests to accommodate the new `Parser` constructor, ensuring no regressions were introduced.

## Current Task: Refactoring with the Builder Pattern

To prepare for the increased complexity of the type system and semantic analysis, the `Parser` class is being refactored to use the Builder pattern for its construction. This will make the process of creating `Parser` instances more flexible and readable, especially as more components (like a `ScopeManager` or `TypeChecker`) are added as dependencies.

The new `ParserBuilder` will allow for a fluent and descriptive way to instantiate the `Parser`, like so:

```cpp
auto parser = ParserBuilder(tokens, count, arena, symbols)
    .withScopeManager(scope_mgr)
    .withMaxRecursionDepth(200)
    .build();
```
