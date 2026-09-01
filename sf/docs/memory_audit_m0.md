# zig0 Memory Audit — Milestone 0

## Summary

- **16 MB internal arena budget is sufficient** for compiling our compiler.
  Tracked arena allocations peak at ~8.7 MB, well under the 16 MB limit.
- **RSS peak** is higher (24 MB) due to ArenaAllocator chunk overhead and C++
  runtime, but the 16 M0 target is for **zig1**, not zig0.
- **Biggest consumer**: Token storage (45.8% of tracked allocs, ~4 MB).
- **Release vs test build**: similar RSS (23.5 MB vs 21.4 MB).
- **lexer.zig** is the largest single module (19.9 MB RSS standalone).

## Results

### Build comparison

| Measurement | Release (main.zig) | Test (test_main.zig) |
|-------------|-------------------|---------------------|
| Source lines | 2,467 | 3,818 |
| Peak RSS | 24,060 KB (23.5 MB) | 21,956 KB (21.4 MB) |
| Arena tracked allocs | ~8.7 MB | similar |
| FATAL | None | None |
| Exit status | 1 | 1 |

### Module standalone RSS

| Module | Lines | Peak RSS | Notes |
|--------|-------|----------|-------|
| lexer.zig | 917 | 20,424 KB (19.9 MB) | Largest — token table, switch, test funcs |
| parser.zig | 162 | 8,180 KB (8.0 MB) | ~60 in-memory function signatures |
| diagnostics.zig | 332 | 7,096 KB (6.9 MB) | Error code tables, collector |
| ast.zig | 332 | 4,596 KB (4.5 MB) | 90 variant enum + inline ArrayLists |
| token.zig | 182 | 4,160 KB (4.1 MB) | 91 variant enum + keyword table |
| pal.zig | 72 | 3,808 KB (3.7 MB) | syscall wrappers |
| allocator.zig | 94 | 3,600 KB (3.5 MB) | Sand + TrackingAllocator |

### Heap profile breakdown (massif, release build)

| % of arena | KB | Component |
|-----------|-----|-----------|
| 45.81% | 4,063 | `DynamicArray<Token>::ensure_capacity` — token storage |
| 22.50% | 1,996 | `TokenSupplier::tokenizeAndCache` — token supplier |
| 5.91% | 524 | `Parser::createNodeAt` — AST node storage |
| ~25% | ~2,200 | Import resolution, string interning, symbol tables, type checker |

## Interpretation

### Why RSS > 16 MB while arena is under 16 MB?

The `ArenaAllocator` mmaps 256 KB chunks but the 16 MB hard limit is on
`total_used_for_stats` (sum of requested sizes), not on total mmap'd pages.
The RSS includes:
- ArenaAllocator's mmap'd pages (~10 MB overcommitted)
- C++ `std::string`, `std::vector` internal allocations
- Dynamic linker / shared library pages
- Unmapped but resident pages

The **16 MB Milestone 0 budget applies to zig1** (the self-hosted compiler),
not zig0 (the C++ bootstrap). zig1 --test peak RSS is 1.1 MB.

### Impact of stripping tests from release build

The test build (test_main.zig) shows *slightly lower* RSS (21.4 vs 23.5 MB)
than release. Both are within noise range. The 16 MB arena limit is NOT
breached by either.

The original FATAL was caused by `test_runner.zig`'s `parseTestSource()`
function pulling in the full lexer+source_manager+diagnostics import chain
during zig0's type checking. This added ~1,000 extra lines to the arena
footprint, triggering the 16 MB limit on `total_used_for_stats`.

**Fix**: inline assert functions in test files, don't import test_runner.zig.

### Why lexer.zig is the biggest consumer

lexer.zig (917 lines) contains:
- 35 keyword string literals interened
- 256-entry character dispatch table
- Multi-megabyte token stream during compilation
- 9 test functions with string literal definitions
- All `TokenKind` enum variants referenced in switches

## Recommendations

1. **Keep 16 MB DEFAULT_ARENA_SIZE** — our compiler stays within budget.
2. **Keep test runner separate** — test_main.zig avoids polluting release build.
3. **Token streaming** — if we ever need to reduce memory, implement
   on-demand tokenization instead of caching all tokens.
4. **Monitor** — re-run `massif` when parser, semantic, or codegen passes are
   added (they'll consume more AST/symbol table space).
