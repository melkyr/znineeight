# zig0 16MB Hard Limit Exceeded — Task 77 Blocked

## Summary

zig0's internal `ArenaAllocator` has a hardcoded `hard_limit_` of 16 MB
(`memory.hpp:144`). Our compiler source has grown to ~4,200 lines across 13
modules. Compiling any test entry point that includes `parser.zig` with the
Task 77 additions pushes `total_used_for_stats` 32 bytes past the 16 MB limit.

## Environment

- **Commit:** `86b3978` (with resolveCallSite cross-module fix)
- **Zig0 build:** `g++ -Isrc/include src/bootstrap/bootstrap_all.cpp -o sf/build/zig0`
- **Target:** `./zig0 -o out/zig1_test.c sf/src/test_main.zig`

## Error

```
FATAL: Memory limit exceeded (Requested: 16777248 bytes, Limit: 16777216 bytes)
```

## Root Cause

`memory.hpp:144` hardcodes the arena hard limit:
```cpp
ArenaAllocator(size_t capacity_cap)
    : ... hard_limit_(16 * 1024 * 1024) {}
```

The `total_used_for_stats` counter tracks cumulative bytes requested from the
arena. This counter always increases (bump allocator, no free). The limit is
independent of `DEFAULT_ARENA_SIZE` in `main.cpp`.

## History

| State | Lines | Bytes over | Date |
|-------|-------|-----------|------|
| Before Task 76 | ~3,900 | 0 (fit) | May 4 |
| Task 76 (30-arm switch + exprPrec) | ~4,100 | 43 | May 4 |
| After trimming (removed 4 stub fns) | ~4,050 | 0 (fit) | May 4 |
| Task 77 (22-case dispatch + 14 helpers) | ~4,200 | 32 (test) / 144 (release) | May 5 |

**Note:** Test build (`test_main.zig`) overshoots by 32 bytes; release build
(`main.zig`) overshoots by 144 bytes. The test build excludes `main.zig`'s
`runCompiler` phase functions (`dump.zig`, `c89_emit.zig`, etc.) which means
the release build has more module overhead even though the test build has more
source files. The difference is due to module-level symbol table entries vs
function-level AST nodes: `main.zig` imports more top-level modules (dump,
name_mangler, etc.) than `test_main.zig`.

## Fix Options

All require a single-line change in `memory.hpp:144`:
```cpp
// Before (hardcoded 16MB):
hard_limit_(16 * 1024 * 1024)

// After (tied to capacity_cap, controlled by DEFAULT_ARENA_SIZE):
hard_limit_(capacity_cap)
```

Then bump `DEFAULT_ARENA_SIZE` in `main.cpp:15` from 16 MB to 32 MB.

## Impact

Without this fix, the self-hosted compiler cannot grow beyond ~4,050 lines of
Z98 source. Final target is ~8,000 lines.

## Workaround Attempted

Removing 4 function declarations (parserParseExpression, parserParsePostfixChain,
parserParseCatchRHS, parserParseOrelseRHS) saved ~120 bytes of arena usage.
This is not sustainable — each new function adds ~30 bytes to the cumulative
arena total.
