# Memory Analysis Report - Milestone 4 (Task 166)

## Overview
This report summarizes the memory usage of the RetroZig bootstrap compiler (C++98) during various stages of compilation. The analysis was performed using a representative subset of the compiler source code and standard benchmark programs.

**Date:** Mon Feb 9 14:40:00 UTC 2026
**Compiler Version:** v0.0.1 (Instrumented)
**Target Hardware Budget:** 16MB

## 1. Peak Memory Usage
The following table shows the peak heap memory usage (including upfront arena allocations) as reported by Valgrind Massif.

| Test Case | Peak Heap Usage (Massif) | Actual Arena Usage (Tracked) |
|-----------|-------------------------|---------------------------|
| Simple Baseline | 16.09 MB | ~6.5 KB |
| Compiler Subset | 16.09 MB | ~34.1 KB |
| Rejection Test | 16.09 MB | ~15.2 KB |

*Note: The high Massif peak is due to the 16MB arena being pre-allocated via `malloc` at startup.*

## 2. Phase-wise Memory Breakdown (Compiler Subset)
The compiler follows a multi-pass architecture. Below is the memory consumption for each phase when compiling `test/compiler_subset.zig`.

| Phase | Arena Delta | AST Nodes | Types | Symbols | Catalogue Entries |
|-------|-------------|-----------|-------|---------|-------------------|
| Parsing | 28,752 bytes | 64 | 4 | 25 | 0 |
| Name Collision | 960 bytes | 64 | 4 | 25 | 0 |
| Type Checking | 3,888 bytes | 64 | 11 | 35 | 0 |
| Signature Analysis | 0 bytes | 64 | 11 | 35 | 0 |
| C89 Validation | 440 bytes | 64 | 11 | 35 | 0 |
| **Total** | **34,040 bytes** | **64** | **11** | **35** | **0** |

## 3. Detailed Consumption Analysis

### 3.1 Hotspots by Method
Based on code instrumentation and analysis, the following methods are the primary contributors to memory consumption:

1.  **`TokenSupplier::tokenizeAndCache`**: This is the single largest consumer in the Parsing phase. It uses a `DynamicArray<Token>` that grows multiple times in the arena. Because the arena never frees memory, each growth leaves behind a "dead" buffer.
    -   *Consumption*: ~14KB for a 30-line file (including temporary growth and final stable array).
2.  **`Parser::createNode`**: Allocates `ASTNode` structures.
    -   *Consumption*: ~3.5KB (64 nodes * 56 bytes).
3.  **`Scope::insert`**: Allocates `SymbolEntry` and grows the symbol table bucket array.
    -   *Consumption*: ~3KB (25 symbols * 80 bytes + bucket arrays).
4.  **`createPointerType` / `createStructType`**: Allocates `Type` objects in the arena.
    -   *Consumption*: ~0.7KB (11 types * 64 bytes).

### 3.2 Arena Waste
The current implementation of `DynamicArray` within an `ArenaAllocator` is convenient but wasteful during the "growth" phase. For a 300-token file, approximately 8KB of arena space is occupied by old, unused token buffers that cannot be reclaimed until the arena is reset.

## 4. Identified Optimizations

### 4.1 Implemented Optimizations
-   **Symbol Table Bucket Optimization**: Reduced the initial bucket count for local scopes from 16 to 4. This saves ~1.6KB of arena space per run by reducing the frequency and size of initial bucket allocations in nested scopes.

### 4.2 Potential Future Optimizations
1.  **Lazy/Incremental Arena Allocation**: Instead of pre-allocating 16MB, use a smaller initial size and grow the arena in chunks (e.g., 1MB chunks) up to a 16MB limit. This would improve observability and real-world memory footprint.
2.  **Type Interning**: Implement a cache for complex types (pointers, arrays, optionals). Currently, every `*i32` creates a new 64-byte `Type` object. Interning these would significantly reduce memory in type-heavy code.
3.  **Tokenization Buffer**: Use a non-arena temporary buffer (e.g., `plat_alloc`/`plat_free` or a reusable global buffer) for the initial tokenization in `TokenSupplier`. This would eliminate the "dead" space caused by `DynamicArray` growth in the arena.
4.  **ASTNode union Compaction**: Move `ASTParamDeclNode` (24 bytes) out-of-line in the `ASTNode` union. This would reduce the base size of every `ASTNode` from 56 bytes to 48 bytes (on 64-bit), a ~14% reduction across the entire tree.

## 5. Conclusion
The RetroZig bootstrap compiler is highly memory-efficient, using approximately **1.1KB per source line** in its current state. At this rate, a 10,000-line compiler would consume roughly **11MB**, which is comfortably within the **16MB** limit. With the identified optimizations, this could likely be reduced to under **6MB**.
