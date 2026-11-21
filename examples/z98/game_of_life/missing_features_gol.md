# Conway's Game of Life: Missing Features & Blockers

This document tracks the current compiler limitations encountered while implementing the Conway's Game of Life example in Z98.

## 1. Exhaustive Switch Requirement
The compiler currently requires an `else` prong for all `switch` expressions and statements, even when all cases of an enum or tagged union are covered.
- **Workaround used:** Added `else => unreachable` to all switches.
- **Goal:** Allow omitting `else` when the compiler can prove exhaustiveness.

## 2. Tagged Union Coercion in Expressions
Implicit coercion from an enum tag (e.g., `.Alive`) to its corresponding tagged union type (`Cell`) is partially implemented but unstable in complex expressions or assignments.
- **Status:** Experimental. Using naked tags like `.Alive` currently often results in the compiler emitting only the enum tag instead of the full union structure, leading to C type mismatches.
- **Workaround used:** Continued use of explicit struct initializers: `Cell{ .Alive = {} }`.
- **Goal:** Robustly support `next_state = if (cond) .Alive else .Dead` and direct assignments.

## 3. C89 Compatibility: Aggregate Initializers as Arguments
When an aggregate (struct/union) initializer is passed directly as a function argument, the `C89Emitter` used to generate C99-style compound literals.
- **Status:** RESOLVED. The compiler now lifts these initializers into temporary variables and passes the variables to the function, ensuring C89 compatibility.

## 4. Multi-dimensional Slice/Array Handling
Passing 2D arrays or slices of slices is currently unstable or unsupported in the bootstrap compiler's 32-bit/m32 target mode.
- **Workaround used:** A flat 1D array (`[800]Cell`) with manual indexing (`y * WIDTH + x`) was used for the grid to ensure stability.
- **Goal:** Improve support for multi-dimensional aggregates and slices.

## 5. C89 Codegen: Pointer to Array Type Mismatch
When passing a pointer to a fixed-size array (e.g., `*[800]Cell`) to a function, the `C89Emitter` incorrectly generates code that passes the address of the first element as a `Cell*` instead of `Cell(*)[800]`, leading to a type mismatch in the generated C.
- **Workaround:** Use slices (`[]Cell`) instead of pointers to fixed-size arrays.
- **Goal:** Fix pointer-to-array decomposition in `C89Emitter`.
