# RetroZig Compiler Architecture

This document provides a detailed overview of the RetroZig compiler's architecture. It is intended for developers who want to contribute to the project.

## Memory Management

The compiler uses a layered architecture that relies heavily on **Arena Allocation** to avoid the overhead of `malloc`/`free` on slow 90s-era allocators.

### Arena Allocator

The arena allocator is a region-based allocator that frees all memory at once (e.g., after a compilation pass). It works by pre-allocating a large block of memory and then "bumping" a pointer every time a new allocation is made. This is much faster than traditional heap allocation, as it avoids the need to search for free blocks of memory.

### String Interning

To reduce memory usage and speed up identifier comparisons, the compiler uses a string interning system. This system ensures that each unique identifier is stored only once in memory.

## Compilation Pipeline

The compilation process is divided into six layers:

1.  **Lexer:** The lexer takes the source code as input and produces a stream of tokens.
2.  **Parser:** The parser takes the stream of tokens and builds an Abstract Syntax Tree (AST).
3.  **Type System:** The type system checks the AST for type errors and enforces the language's type rules.
4.  **Symbol Table:** The symbol table stores information about all of the identifiers in the program, such as their type and scope.
5.  **Code Generation:** The code generator takes the AST and produces x86 assembly code.
6.  **PE Backend:** The PE backend takes the assembly code and produces a 32-bit Win32 PE executable.

## The "Zig Subset" Language

The compiler supports a restricted version of the Zig language. The following features are **excluded** in Phase 1:

*   Async/Await
*   Closures/Captures
*   Complex Comptime (only basic integer math allowed)
*   SIMD Vectors

## Defer Statement

The compiler supports the `defer` statement, which allows you to execute a statement at the end of a scope. The `defer` statements are executed in reverse order of their declaration.

## Compile-Time Evaluation

The compiler supports a limited form of compile-time evaluation. The following operations are supported:

*   Integer arithmetic
*   Boolean logic
*   Comparisons
*   Array length calculation
*   Basic string concatenation
*   Conditional compilation flags

## Performance

The compiler is designed to be as fast as possible. The following performance targets have been set:

*   **Parse Speed:** < 1ms per 100 lines
*   **Type Check:** < 2ms per 100 lines
*   **Code Gen:** < 3ms per 100 lines
*   **Memory Usage:** Peak < 16MB per 1000-line file

To achieve these goals, the compiler uses a number of optimization techniques, including string interning, arena allocation, and lookup tables.
