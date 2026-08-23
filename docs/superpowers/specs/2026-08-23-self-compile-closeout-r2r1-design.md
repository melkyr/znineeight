# Self-Compile 194-Error Closeout + R2/R1 Residual — Design

**Date:** 2026-08-23
**Branch:** `zig1_start`
**Status:** Approved (operator rulings inline)

## Goal

Close out the 194-error self-compile plan, extend the solved fixtures for analogous valid-Zig shapes, and fix the final 12 self-compile gcc errors via R/I/F: **R2 `zT_<n> undeclared` ×11** + **R1 `incompatible types … unsigned int ← Opt_10` ×1**.

## Background (final residual state)

The 194-error closeout plan reduced self-compile gcc errors **194 → 12** through: F-MIGRATE (bare `pal`, 5→0), F-A (LirInst tag-emission, R1 86→38), F-B (name-keyed conflation, R1 38→7 + R3 22→0), F-ORELSE (6→0, json re-baselined), F-C (`.f_2` 2→0 + too-few-args 1→0 + 32 extra `zT_` cleared).

The final 12 (verified in `/tmp/emit_errs_fc5.txt`):

| # | Class | Count | Evidence |
|---|-------|-------|----------|
| R2 | `zT_<n> undeclared … did you mean zT_<n+1000/100>?` | **11** | c89_emit ×6 (zT_5666→7666, 5675→6675, 5707→7507, 5716→7516, 5757→7557, 5766→7566), import_resolver ×2 (72→272, 131→311), main ×1 (68→168), module_registry ×2 (27→127, 98→99) |
| R1 | `incompatible types when assigning … unsigned int ← Opt_10` | **1** | lower_1EB7D337.c:31469 |

### R2 mechanism (controller-verified, do NOT re-derive)

The emitted C declares `zT_7666` and uses it in one function (c89_emit_7CEF756E.c:52922, :57501-57503) but a *different* function references `zT_5666` (line 65076) without declaring it — the `zT_N` vs `zT_N+1000` gcc hint points at the other function's temp. This is a **cross-function hoisted-temp index drift**, **distinct** from F-B's name-keyed `emitHoistedDecls` dedup (which is already fixed and re-verified). The R/I for R2 must pin the exact drift site.

### R1 mechanism (known, out-of-scope in prior plan)

`zT_970 = rt` where `rt` is `Opt_10`-typed (optional-typed `var rt` inside `lowerExprImpl`, lower.zig:1501 `resolvedTypeTableGet` result) — the R1-family conflation residual F-B explicitly left. Now in scope.

## Architecture

Single plan, ten tasks in sequence:

1. **GATE-CLOSE** (docs) — reconcile the 194-plan's docs: EXPECTED_FAIL v44→v45 (final 12-error state + all landed fixes + json re-baseline), QUICK_REF json row `9720478c…`→`d31e43b1…`, 194-plan closeout record. Closes the prior plan's pending GATE work.
2. **A-ANALYZE** (read-only) — review the 24 solved `emission_*_xmod` fixtures; per fixture enumerate analogous valid-Zig shapes (if↔switch, while↔for, flat↔nested block, single↔multi-capture, orelse-block variants, tagged-union↔plain-union) with per-variant verdict: **COVERED** (already exercised) / **ADD** (new RED fixture needed) / **N-A** (shape absent in dialect). Report `.superpowers/sdd/task-A-analyze-report.md`.
3. **A-ADD** (fixtures) — commit new RED fixtures for every ADD verdict.
4. **R-R2** (fixture) — fresh RED fixture for the `zT_<n>` temp-index drift (NOT the F-B conflation fixture `emission_zT_undeclared_xmod`, which exercises a different mechanism).
5. **I-R2** (read-only) — pin the upstream fix for the temp-index drift; byte-identity reasoning; STOP on fork.
6. **F-R2** (fix) — apply fix; R2 fixture GREEN; self-compile re-count observational.
7. **R-R1** (fixture) — fresh RED fixture for `Opt_10` assign.
8. **I-R1** (read-only) — pin the upstream fix; STOP on fork.
9. **F-R1** (fix) — apply fix; R1 fixture GREEN; re-count observational.
10. **GATE-FINAL** (docs) — final sweep + reconcile (if R2/R1 reached 0, self-compile is now gcc-clean — record the milestone).

## Global Constraints

- **Soft success gate (operator ruling):** each F task's HARD gate = its fixture GREEN (gcc -c rc=0) + no functional regression; the self-compile re-count is **observational only** (may not hit 0 if a fix unmasks a new shape). **Runtime-identity governs** (byte-diff with runtime-identical behavior = re-baseline default; byte-diff with any runtime/correctness doubt = STOP).
- **4 MD5 baselines (authoritative):** gol `4afb203fdde7a880ec6e7aed32543691`, lisp `5f886646b164a70c52bf042eb54bda78` (repo-root CWD), **json `d31e43b19f752e40b9fd4b8885b13600`** (re-baselined by F-ORELSE), mud `a1d0dd55aada9c3fd904ae33f54de32e`. Matrix 21/21.
- **Emission-only.** Only `sf/src` files named by the I reports are touched. `sf/build/out_release/` is WEDGED — never touch/list. All runs `timeout 120`.
- **Build:** `bash sf/scripts/build_release.sh` → gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`; then reinstall std (`mkdir -p /tmp/fx_subfolder/lib && cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`).
- **Editing:** `edit`/`fastedit` only (AGENTS.md §X.7). **Z98 constraints** (AGENTS.md §1.3): no anytype/@Type; `@intCast` for i32↔usize; switch requires `else`.
- **Fixtures** under `repro/mi_matrix/`, full-graph (3+ modules) where the mechanism needs scale, RED = exact self-compile error text, NOTES.md per the established `emission_*_xmod` convention.
- Commit messages verbatim per task. STOP on any issue/confusion.
- Self-compile re-count recipe: `bash scripts/self_compile/build_zig1_5.sh` then `cd /tmp/zig1_5/gen && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /workspace/znineeight/sf/src/include -c *.c 2>/tmp/emit_errs_<n>.txt`.

## Out of Scope

- The `zT_<n>` R2 class beyond the 11 current errors (observational re-count may reveal more sites of the same mechanism — those are in scope for the fix; NEW mechanisms found are out of scope → STOP).
- Any parser/sema/lowering fix not named by an I report.
- Memory work, determinism plan T3-T6, non-residual classes.
