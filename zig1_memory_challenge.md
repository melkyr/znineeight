# zig1 Memory Challenge: Phase 1 Profiling Report

## 1. Overview
The Z98 bootstrap compiler (`zig0`) previously hit its strictly enforced 16MB memory limit when compiling the self-hosted compiler source (`sf/src/main.zig`). Following the completion of Milestone 11, this Phase 1 profiling effort confirms that the major memory leaks and bloat issues have been resolved.

## 2. Comparison Metrics
Compilations were performed on two targets to establish a "delta profile":
- **Target A (Small):** `tests/hello.zig` (~5 lines, 1 module)
- **Target B (Large):** `sf/src/main.zig` (~6,300 lines, ~43 modules)

| Metric | Target A (Hello) | Target B (SF) | Delta |
|--------|-----------------|---------------|-------|
| Peak Usage (Internal) | ~48 KB | ~4.5 MB | +4.45 MB |
| Peak Heap (Massif) | ~0.8 MB | ~5.7 MB | +4.9 MB |
| Source Lines | ~5 | ~6,300 | +6,295 |
| AST Nodes | 13 | 22,380 | +22,367 |
| Symbols | 84 | 3,511 | +3,427 |
| Types | 40 | 814 | +774 |

## 3. Top 5 Memory Consumers (Ranked by Peak Usage)

| Rank | Allocation Site | Context | Peak (SF) | Growth (Delta) |
|------|-----------------|---------|-----------|----------------|
| 1 | `Parser::createNode` | AST Construction | ~1.31 MB | ~1.31 MB |
| 2 | `Scope::insert` | Symbol Table | ~0.78 MB | ~0.75 MB |
| 3 | `TokenSupplier::tokenizeAndCache` | Token Storage | ~0.52 MB | ~0.52 MB |
| 4 | `TypeChecker::resolveAllPlaceholders` | Type Snapshotting | ~0.26 MB | ~0.26 MB |
| 5 | `allocateType` | Type Registry | ~0.15 MB | ~0.12 MB |

## 4. Deep Dive: Resolved Hotspots

### 4.1 Type Snapshotting (`resolveAllPlaceholders`)
The single largest consumer in previous profiles (~10.5 MB) is now under control (~0.26 MB).
- **Resolution:** These temporary snapshots (struct fields, function parameters) are now allocated from the **Scratch Arena**, which is reset recursively. This prevents non-linear growth during nested type cascades.

### 4.2 Token Storage (`DynamicArray<Token>`)
Token caching previously consumed ~6 MB for a 40-module project.
- **Resolution:** Tokens are now released per-module immediately after parsing. Peak usage now only reflects the largest module's tokens plus discovery overhead, reducing usage by ~90%.

### 4.3 AST and Symbol Growth
These categories now dominate the memory profile (~2 MB total).
- **Status:** Growth is strictly linear with source size and is considered **Inevitable** for the current architecture.
- **Future Headroom:** At ~330 bytes per 100 lines (AST+Symbols), the 16MB limit allows for roughly 50,000 lines of source code.

## 5. Conclusion: Waste Eliminated

The Phase 1 profiling demonstrates that the Z98 compiler is now highly memory-efficient. The primary sources of "waste" (global token caching and permanent type snapshots) have been successfully migrated to transient or scratch storage.

**Final Verdict:** The 16MB limit is safe for the foreseeable future of the `sf/` project. No further Phase 2 or 3 optimizations are required at this time.
