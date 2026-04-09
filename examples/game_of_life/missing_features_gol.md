# Conway's Game of Life: Missing Features & Blockers

This document tracks the current compiler limitations encountered while implementing the Conway's Game of Life example in Z98.

## 1. Exhaustive Switch Requirement
The compiler currently requires an `else` prong for all `switch` expressions and statements, even when all cases of an enum or tagged union are covered.
- **Workaround used:** Added `else => unreachable` to all switches.
- **Goal:** Allow omitting `else` when the compiler can prove exhaustiveness.

## 2. Tagged Union Coercion in Expressions
The compiler does not currently support implicit coercion from an enum tag (e.g., `Cell.Alive`) to its corresponding tagged union type (`Cell`) when used inside control-flow expressions like `if`.
- **Workaround used:** Used explicit struct initializers: `Cell{ .Alive = {} }`.
- **Goal:** Support `next_state = if (cond) .Alive else .Dead`.

## 3. C89 Compatibility: Aggregate Initializers as Arguments (CRITICAL BLOCKER)
When an aggregate (struct/union) initializer is passed directly as a function argument, the `C89Emitter` currently generates C99-style compound literals:
```c
zF_set(..., {.tag = zE_Alive}); // Error: C99 syntax in C89 mode
```
C89 does not support anonymous aggregate literals in expressions.
- **Status:** This is the primary blocker preventing the example from compiling with MSVC 6.0 or `gcc -std=c89`.
- **Required Fix:** The compiler must lift these initializers into temporary variables and pass the variables to the function.

## 4. Multi-dimensional Slice/Array Handling
Passing 2D arrays or slices of slices is currently unstable or unsupported in the bootstrap compiler's 32-bit/m32 target mode.
- **Workaround used:** A flat 1D array (`[800]Cell`) with manual indexing (`y * WIDTH + x`) was used for the grid to ensure stability.
- **Goal:** Improve support for multi-dimensional aggregates and slices.
