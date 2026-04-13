# Technical Debt: TypeChecker and Memory

This document tracks technical debt for the semantic and memory management components.

## TypeChecker Issues
- **RAII Duplication**: Significant duplication in RAII guards for scope and expected types.
- **Literal Promotion**: Redundant logic in `visitBinaryOp` helpers for promoting `TYPE_INTEGER_LITERAL` to concrete types.
- **Disambiguation Logic**: `visitMemberAccess` contains complex logic for unwrapping aliases and placeholders that could be unified.

## Memory Management
- **Arena Bloat**: `DynamicArray` reallocation strategies may cause arena bloat in extremely large modules.
- **TCO Reset**: The `temp_sand` arena is not reset during TCO loops, causing `OutOfMemory` in deep recursion (e.g. Lisp interpreter).
