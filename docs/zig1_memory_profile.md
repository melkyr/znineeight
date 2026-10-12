# Z98 Memory Profile: Phase 1 Report

## 1. Overview
This report details the memory usage of the `zig0` bootstrap compiler when compiling the self-hosted compiler source (`sf/src/main.zig`). Following recent optimizations (Milestone 11), the compiler now comfortably fits within the 16MB hard limit.

## 2. Delta Profile
We compared a minimal compilation (`tests/hello.zig`) against the full Stage 1 compilation (`sf/src/main.zig`).

| Metric | Target A (Hello) | Target B (SF) | Delta |
|--------|-----------------|---------------|-------|
| Internal Peak | 48.3 KB | 4.51 MB | +4.46 MB |
| Massif Peak Heap | 840 KB | 5.73 MB | +4.89 MB |
| Source Lines | ~5 | ~6,300 | +6,295 |
| AST Nodes | 13 | 22,380 | +22,367 |
| Symbols | 84 | 3,511 | +3,427 |
| Types | 40 | 814 | +774 |

## 3. Top 5 Allocation Sites (Ranked by Peak Heap Usage)

| Rank | Allocation Site | Context | Peak (SF) | Delta |
|------|-----------------|---------|-----------|--------|
| 1 | `Parser::createNode` | AST Construction | ~1.31 MB | ~1.31 MB |
| 2 | `Scope::insert` | Symbol Management | ~0.78 MB | ~0.75 MB |
| 3 | `TokenSupplier::tokenizeAndCache` | Token Storage (Peak) | ~0.52 MB | ~0.52 MB |
| 4 | `TypeChecker::resolveAllPlaceholders` | Recursive Type Snapshots | ~0.26 MB | ~0.26 MB |
| 5 | `allocateType` | Type Registry | ~0.15 MB | ~0.12 MB |

## 4. Analysis of Memory Consumers

### 4.1 AST Nodes (`Parser::createNode`)
AST nodes represent the largest single category of memory usage. This growth is strictly linear with the number of statements and expressions in the source code.
- **Status**: Inevitable.
- **Optimization**: Already using a bump allocator for zero fragmentation.

### 4.2 Symbols (`Scope::insert`)
Symbol table entries grow with each unique declaration and local variable.
- **Status**: Inevitable.
- **Optimization**: Symbols are reused where possible; scopes are managed in the global arena.

### 4.3 Tokens (`TokenSupplier::tokenizeAndCache`)
Memory usage for tokens is now managed per-module. The peak usage occurs during the initial discovery and parsing phase of the dependency graph.
- **Status**: Optimized. Previously ~6MB, now ~0.5MB at peak because tokens are released after the AST is built for each module.
- **Optimization**: Per-module token release implemented in Milestone 11.

### 4.4 Type Snapshots (`resolveAllPlaceholders`)
Temporary snapshots are created during recursive type resolution to ensure iterator stability.
- **Status**: Heavily Optimized. Previously ~10.5MB, now ~0.26MB.
- **Optimization**: These snapshots were moved from the permanent arena to the **Scratch Arena**, which is reset frequently.

### 4.5 String Interner
Unique identifiers across all modules are stored once.
- **Status**: Linear with source complexity.
- **Optimization**: Deduplication ensures minimal waste.

## 5. Conclusion: State of the 16MB Challenge

The Z98 compiler is now in a very healthy state regarding memory. The "Transitive Alias Blockade" and "Snapshot Blowup" issues that previously pushed usage to ~30MB have been resolved by:
1. **Scratch Arena Migration**: Moving transient type-resolution data out of the permanent arena.
2. **Per-Module Token Release**: Freeing lexer tokens immediately after parsing each module.
3. **Type Deduplication**: Robust nominal type identity preventing redundant type objects across module boundaries.

**Final Verdict**: The current 16MB limit is more than sufficient for the ~6,300 line `sf/` source. The compiler can likely scale to 15,000-20,000 lines before hitting the limit again. Future optimizations should focus on AST node size reduction if further headroom is required.
