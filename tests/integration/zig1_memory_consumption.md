# zig1 Memory Consumption Report

Generated: 2026-05-13

## Methodology

Built zig0 with `-DMEASURE_MEMORY` (PhaseMemoryTracker in compilation_unit.cpp).
Compiled `sf/src/main.zig` to C, collecting:

1. Internal arena phase report (per-phase delta, AST nodes, types, symbols)
2. Valgrind `--tool=massif` heap profile
3. `time -v` peak RSS

## Summary

| Metric | Value |
|--------|-------|
| Zig source in release chain | 4,376 lines (12 modules) |
| Generated C output | 11,682 lines (18 files) |
| Arena internal peak (data) | **1,904,420 bytes (~1.9 MB)** |
| Arena OS allocation (heap) | ~7.44 MB |
| C++ non-arena heap | ~0.22 MB |
| Peak RSS | **~11.7 MB** |
| 16MB arena hard limit | Not hit with current release (under by ~4.3 MB) |

## Per-Phase Arena Breakdown

| Phase | Arena Delta (bytes) | AST Nodes | Types | Symbols |
|-------|--------------------|-----------|-------|---------|
| Parsing | 27,432 (1.4%) | 1,342 | 35 | 179 |
| Name Collision Detection | 0 (0%) | 27,105 | 369 | 2,033 |
| Global Signature Resolution | 173,864 (9.1%) | 27,105 | 722 | 2,470 |
| **Type Checking** | **764,353 (40.1%)** | 27,105 | 839 | 3,987 |
| Signature Analysis | 190 (0.01%) | 27,105 | 839 | 3,987 |
| C89 Validation | 106,288 (5.6%) | 27,105 | 839 | 3,987 |
| AST Lifting (all modules) | ~56,000 (2.9%) | 27,105 | 839-840 | 3,987 |
| Static Analyzers (all modules) | ~39,000 (2.0%) | 27,105 | 839-840 | 3,987 |
| Module Metadata Prep (all) | ~21,000 (1.1%) | 27,105 | 839-840 | 3,987 |
| Code Generation (all modules) | ~121,000 (6.4%) | 27,105 | 839-840 | 3,987 |

**Total tracked: ~1.31 MB** (tracker only captures explicit begin/end phases; the base 0.6 MB is from module loading before first phase marker).

## Type Checker Dominance

**Type Checking alone consumes 40% of arena memory (764 KB).** This correlates with:

- Symbol growth: 179 (post-parse) → 3,987 (post-typecheck), ×22 increase
- Type growth: 35 → 839, ×24 increase
- Type deduplications: 2,226 (interner saved this many redundant type lookups)

The symbol table and type registry are the primary arena consumers within type checking.

## Heap Profile (Valgrind Massif)

```
Peak heap: 7,658,172 bytes (7.31 MB useful + 0.27 MB overhead)
```

- 97.16% of heap → `ArenaAllocator::alloc_aligned` (internal arena chunks)
- 2.84% → C++ non-arena malloc (file I/O, DynamicArray resizes, symbol interner temp allocs)

Peak snapshot occurred at ~58M instructions, corresponding to mid-type-checking phase.

## Per-Module Code Generation

| Module | C Output Size |
|--------|--------------|
| parser.c | 206 KB |
| dump_ast.c | 81 KB (not in release) |
| lexer.c | 79 KB |
| main.c | 30 KB |
| ast.c | 18 KB |
| diagnostics.c | 18 KB |
| token.c | 16 KB |
| growable_array.c | 16 KB |
| source_manager.c | 11 KB |
| string_interner.c | 10 KB |
| Others (8 files) | ~30 KB total |

parser.zig dominates at 206 KB C output (42% of all generated code).

## Key Insights

1. **Actual arena data is only 1.9 MB** — the 16 MB limit is hit only by the arena's internal chunk allocation counter (cumulative `total_used_for_stats`), not by actual working set size.

2. **Type checking dominates** — 40% of arena goes to type resolution, symbol table, type registry.

3. **parser.zig is the largest module** — 206 KB / 11,682 KB = 18% of all generated C code.

4. **A 4-6 MB arena limit would suffice** for the actual data. The 16 MB limit is artificial and could be safely bumped to 32 MB without concern.

5. **RSS (11.7 MB) is only 2-3 MB larger than arena allocation (7.44 MB)** — the arena's heap footprint dominates RSS, with ~4 MB of stack/code/overhead.

## Recommendations

- Increase `hard_limit_` from 16MB to 24MB for headroom
- Or keep 16MB but ensure dump/test code is compiled separately (current approach)
- Type checking optimization would give largest memory benefit per-effort
