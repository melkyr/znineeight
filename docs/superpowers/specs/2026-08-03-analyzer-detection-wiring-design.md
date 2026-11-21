# Analyzer Detection Wiring — Design Spec

**Version:** 1.0
**Date:** 2026-08-03
**Status:** Draft

## 1. Goal

Wire the three currently-dead static analyzer detection paths (null, lifetime, doublefree) so they actually run on function bodies. Fix any false diagnostics against the corpus. Restore corpus to at least 161/19/6/0 (no regression from post-F1 state).

## 2. Architecture

All work in `sf/src/analyzer.zig`. The `visitStatement` function (line 643) already contains full control-flow-aware analysis logic (if/while/switch/for forking+merging, defer queue, return checking). The 3 `run*Analyzer` entry points currently bypass it by passing no-op callbacks directly to `walkBlock`.

**Fix pattern:** Route callbacks THROUGH `visitStatement` via a wrapper:

```
runNullAnalyzer → Wrapper.visit → visitStatement(ctx, state, ni, onNullStmt)
                             → walkBlock(..., Wrapper.visit) for nested blocks
```

Same pattern for all 3 analyzers. The wrapper struct captures the original callback as a closure. `visitStatement` gains a 5th parameter `visit_fn` for recursive `walkBlock` calls inside nested control flow.

## 3. Changes — 6 edit sites in analyzer.zig

| # | Line | Change |
|---|------|--------|
| A | :643 | Add 5th param `visit_fn: fn(*AnalyzerContext, *StateMap, u32) void` to `visitStatement` |
| B | :657,666,674,679 | 4 recursive `walkBlock(on_stmt, ...)` → `walkBlock(visit_fn, ...)` |
| C | :749 | `runNullAnalyzer`: replace `walkBlock(..., onNullStmt)` with wrapper calling `visitStatement(ctx, s, ni, onNullStmt, wrapper.visit)` |
| D | :768 | `runLifetimeAnalyzer`: same pattern with `onLifetimeStmt` |
| E | :773 | `runDoubleFreeAnalyzer`: same pattern with `onDoubleFreeStmt` |
| F | :737 | `onDoubleFreeStmt`: add `handleFreeCall(ctx, state, node_idx)` before `handleOwnershipPass` |

**Test file update:** `sf/src/tests/test_analyzer_bin.zig` — 4 direct `visitStatement` call sites need the new 5th `visit_fn` argument.

## 4. Diagnostics enabled by wiring

### Null detection (`--no-null-check` skips)
| Code | Severity | Meaning |
|------|----------|---------|
| ERR_2004 | Error | Definite null dereference |
| WARN_6001 | Warning | Deref of uninitialized pointer |
| WARN_6002 | Warning | Potential null dereference |

### Lifetime detection (`--no-lifetime-check` skips)
| Code | Severity | Meaning |
|------|----------|---------|
| ERR_2020 | Error | Returning address of local |
| ERR_2021 | Error | Returning address of param |
| WARN_6010 | Warning | Returning pointer via variable |
| WARN_6011 | Warning | Returning slice of local |

### Double-free detection (`--no-leak-check` skips)
| Code | Severity | Meaning |
|------|----------|---------|
| ERR_2005 | Error | Double free |
| WARN_6006 | Warning | Freeing untracked pointer |
| WARN_6005 | Warning | Memory leak (already enabled) |

## 5. Gate strategy — Independent per-path verification

Each detection path verified independently against the 186-repro corpus using existing skip flags:

1. **Null-only**: `--no-lifetime-check --no-leak-check`
2. **Lifetime-only**: `--no-null-check --no-leak-check`
3. **Doublefree-only**: `--no-null-check --no-lifetime-check`
4. **All three**: no skip flags

False positives from any path → flag isolated to that path → fix or document.

Standard gates also apply:
- Build: `bash sf/scripts/build_release.sh` → 0 errors
- test_analyzer_bin: passes (updated call sites)
- 4 MD5 baselines: mud `9fde02d8`, gol `d0d3051d`, lisp `10d09c99`, json `3492a935`

## 6. Success criteria

- Corpus: at least 161/19/6/0 (no regression)
- 4 z98 examples MD5 byte-identical
- Each wired path verified independently — zero unexpected corpus hits
- All 3 paths disabled by existing CLI flags

## 7. Risk assessment

**Low risk.** All 6 changes are mechanical routing (pass-through, no new analysis logic). The analysis logic in `visitStatement` already exists and has been statically verified. Null/lifetime/doublefree detection is standard static analysis — false positives from well-formed Z98 should be rare. State tracking bugs (merge precision loss, missed arena resets) are the only real risk and can be isolated with per-path corpus verification.

## 8. Out of scope

- Fixing pre-existing analyzer bugs (state merge precision, walkBlock depth handling)
- Adding new diagnostics or expanding existing ones
- Modifying `validateSignatureType` to handle non-ident_expr type nodes
- Null/lifetime/doublefree detection in multi-module contexts (cross-module tracking)
