# Memory Analysis Report - Milestone 4 (Task 166)

## Overview
This report summarizes the memory usage of the RetroZig bootstrap compiler (C++98) during various stages of compilation. The analysis was performed using a representative subset of the compiler source code and standard benchmark programs.

**Date:** Mon Feb 9 14:40:00 UTC 2026
**Compiler Version:** v0.0.1 (Instrumented)
**Target Hardware Budget:** 16MB

## 1. Peak Memory Usage (Optimized - Task 180)
The following table shows the peak heap memory usage after implementing chunked arena allocation and early token freeing.

| Test Case | Peak Heap Usage (Tracked) | Previous Usage | Reduction |
|-----------|---------------------------|----------------|-----------|
| Simple Baseline | ~6.6 KB | ~6.5 KB | -2% (overhead) |
| Compiler Subset | ~14.4 KB | ~34.1 KB | **58%** |
| Large (2000 lines) | ~958 KB | ~2.2 MB (est) | **~56%** |

*Note: Upfront 16MB pre-allocation has been eliminated in favor of lazy 1MB chunks.*

## 2. Phase-wise Memory Breakdown (Compiler Subset)
The compiler follows a multi-pass architecture. Below is the memory consumption for each phase when compiling `test/compiler_subset.zig` with optimizations.

| Phase | Arena Delta | AST Nodes | Types | Symbols | Catalogue Entries |
|-------|-------------|-----------|-------|---------|-------------------|
| Parsing (Tokens) | 0 bytes (freed) | - | - | - | - |
| AST & Symbols | ~12.5 KB | 64 | 4 | 25 | 0 |
| Type Checking | ~1.5 KB | 64 | 8 (deduped) | 35 | 0 |
| Other Passes | ~0.4 KB | 64 | 8 | 35 | 0 |
| **Total Peak** | **~14.4 KB** | **64** | **8** | **35** | **0** |

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

### 4.1 Implemented Optimizations (Task 180)
-   **Lazy Chunked Arena Allocation**: Eliminated 16MB upfront waste. Physical memory is now allocated in 1MB chunks on demand.
-   **Transient Token Arena**: Added a dedicated `token_arena` that is reset immediately after parsing, freeing up to 50% of peak memory before semantic analysis begins.
-   **Type Interning**: Implemented `TypeInterner` to deduplicate pointer, array, and optional types. This reduced type object overhead significantly in type-heavy code.
-   **Symbol Table Bucket Optimization**: Reduced the initial bucket count for local scopes from 16 to 4.

### 4.2 Potential Future Optimizations
1.  **ASTNode union Compaction**: Move moderate-sized nodes (Unary, IntegerLiteral, etc.) out-of-line. Currently deferred as goals were exceeded without it.
2.  **SourceLocation packing**: Reduce `SourceLocation` from 12 bytes to 8 bytes by using `u16` for line/column.

## 5. Conclusion
The RetroZig bootstrap compiler is highly memory-efficient, using approximately **1.1KB per source line** in its current state. At this rate, a 10,000-line compiler would consume roughly **11MB**, which is comfortably within the **16MB** limit. With the identified optimizations, this could likely be reduced to under **6MB**.
