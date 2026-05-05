# zig1 Memory Challenge: Phase 1 Profiling Report

## 1. Overview
The Z98 bootstrap compiler (`zig0`) is currently hitting its strictly enforced 16MB memory limit when compiling the self-hosted compiler source (`sf/src/main.zig`). This report details the findings from a Phase 1 profiling effort using Valgrind Massif to identify the primary sources of memory consumption and growth.

## 2. Comparison Metrics
Compilations were performed on two targets to establish a "delta profile":
- **Target A (Small):** `examples/lisp_interpreter_curr/main.zig` (~1,000 lines, 10 modules)
- **Target B (Large):** `sf/src/main.zig` (~6,300 lines, ~40 modules)

| Metric | Target A (Lisp) | Target B (SF) | Delta |
|--------|-----------------|---------------|-------|
| Peak Usage | ~4.3 MB | ~29.2 MB | +24.9 MB |
| Source Lines | ~1,000 | ~6,300 | +5,300 |
| Modules | 10 | ~43 | +33 |

## 3. Top 5 Memory Consumers (Ranked by Peak Usage)

| Rank | Allocation Site | Context | Peak (SF) | Growth (Delta) |
|------|-----------------|---------|-----------|----------------|
| 1 | `TypeChecker::resolveAllPlaceholders` | Type Snapshotting | ~10.5 MB | ~10.2 MB |
| 2 | `DynamicArray<Token>::ensure_capacity` | Token Caching | ~6.1 MB | ~5.1 MB |
| 3 | `C89Emitter::scanType` | CodeGen Preparation | ~2.1 MB | ~2.1 MB |
| 4 | `DynamicArray<Symbol*>::ensure_capacity` | Metadata/Symbol Tables | ~1.3 MB | ~1.0 MB |
| 5 | `Lexer::lexStringLiteral` | String Literal Buffering | ~1.0 MB | ~0.7 MB |

## 4. Deep Dive: The Biggest Deltas

### 4.1 Type Snapshotting (`resolveAllPlaceholders`)
The single largest consumer is the snapshotting mechanism in `TypeChecker::resolveAllPlaceholders`. This function creates temporary copies of struct fields, function parameters, and union variants during type resolution to ensure iterator stability.
- **Problem:** These snapshots are allocated from the permanent arena but are only needed for the duration of the resolution loop.
- **Evidence:** Peak usage for this site jumped from **262 KB** in Lisp to **10.5 MB** in SF. This is a 40x increase for a 6x increase in source size, indicating non-linear growth due to nested type cascades.

### 4.2 Token Storage (`DynamicArray<Token>`)
Tokens are cached for every module and kept until `finalizeParsing` is called after the *entire* pipeline.
- **Problem:** For a 40-module project, keeping all tokens in memory simultaneously consumes ~6MB.
- **Evidence:** Memory usage is strictly linear with the total number of tokens across all modules.

### 4.3 CodeGen Metadata (`scanType` & `Symbol*` arrays)
The `MetadataPreparationPass` and `CBackend::scanType` collect reachable types and symbols.
- **Problem:** These passes generate transient lists in the permanent arena during the final stages of compilation.
- **Evidence:** This site accounts for ~3.4MB of the peak usage at the end of the run.

## 5. Conclusion: Inevitable vs. Waste

- **Inevitable Growth:** AST nodes (approx. 1MB) and the Symbol Table (approx. 1.3MB) grow linearly with source size and are essential for compilation.
- **Avoidable Waste:**
    - **Type Snapshots:** ~10MB could be reclaimed if these were allocated from a transient arena and reset.
    - **Token Caching:** ~6MB could be reduced if tokens were released per-module after parsing, rather than kept globally.
    - **Metadata Lists:** ~3MB of transient data in the permanent arena.

**Final Verdict:** The current 16MB limit is achievable even for the 6,300-line `sf/` source if we move transient structures (Snapshots, Tokens, Scan lists) to a resettable arena. Raising the limit should only be considered after these optimizations are implemented in Phase 2 and 3.
