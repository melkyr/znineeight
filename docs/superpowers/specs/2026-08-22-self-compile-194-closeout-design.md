# Self-Compile 194-Error Closeout — Design

**Date:** 2026-08-22
**Branch:** `zig1_start`
**Status:** Approved (operator rulings inline)

## Goal

Close the 194 residual self-compile gcc errors so the compiler is one step closer to self-hosting. NOT a hard `build_zig1_5.sh rc=0` gate (that forces scope creep across all tasks). Success = each class's fixture flips GREEN with no functional regression, and the self-compile error count trends down-or-flat.

## Background

The residual-closeout plan (`2026-08-20-self-compile-residual-closeout-plan.md`) fixed 4 classes (A2/C2/E2/F-SWITCH) and brought self-compile from 425 → 194 gcc errors. The 194 (from `/tmp/emit_errs_e2down.txt`, `gcc -c` of the 40 self-emitted `.c`) split into 6 classes:

| # | gcc error class | Count | Dominant file(s) | Shape |
|---|---|---|---|---|
| R1 | `incompatible types when assigning` | 86 | lower.c 59, semantic 8, type_resolver 6 | `Type`←`CoercionKind` (enum→enum), `unsigned int`←`Slice/Opt` — temp-typed-wrong |
| R2 | `zT_<n> undeclared` | 68 | c89_emit 38, type_registry 17, symbol_reg 5 | temp referenced but declaration skipped (void-skip guard) |
| R3 | `request for member` | 22 | lower.c 19, semantic 3 | `.is_self`/`.result`/`.call_block_idx` on non-struct (CallInfo/LirInst variant-payload) |
| R4 | `has no member` | 8 | type_resolver 5, c89_emit 3 | `EnumPayload has no member 'payload'`, anon struct `f_2` |
| R5 | `pal` undeclared | 5 | semantic 2, symbol_reg 1, type_registry 2 | global `pal` load type loss |
| R6 | misc | 5 | — | subscripted×3, too-few-args×1, aggregate×1 |

Also recorded latents (NOT in the 194, from F-SWITCH reports): value-position enum literals (lower.zig:1503-1537 falls back to `node.payload` slot-index — bites `.eof` in `kindNum(.eof)`); self-compile qualified-member switch case labels dropped at lower.zig:3862/:4689.

## Architecture

**V → R×6 (batched) → STOP → I → F → soft re-count check → GATE → M-FINAL.**

- **V** (read-only): enumerate collection-iteration sites that store/read a slot index as if it were a semantic value (the switch-on-enum bug class). Report which are live self-compile errors vs latent.
- **R1–R6** (one per class, ALL in a row, no STOP between): each builds a full-graph (3+ module) fixture using **valid Zig** that reproduces the exact self-compile error text, plus a **probable mechanism** as the I starting point (explicitly stated as possibly wrong). If a class is too complex to fixture even full-graph, the R reports that (surfaced at STOP).
- **STOP**: present V + all R reports to operator. Merge shared root causes across R's; re-scope or drop any unfixtureable class; amend plan if needed.
- **I** (per merged root cause, read-only): pin the upstream-correct fix.
- **F** (per root cause): apply fix; per-task gate = fixture GREEN + runtime-identical.
- **GATE** (docs reconcile) + **M-FINAL** (whole-branch review).

## Global Constraints

- **Fixture fidelity rule:** each fixture uses **valid Zig** and reproduces the **exact self-compile error text** (full-graph, 3+ module chain). The fixture is a *diagnostic*: if it flips GREEN but self-compile errors remain, that proves the residual is full-graph-scale, not scope creep.
- **Per-task F gate (hard): fixture GREEN + no functional regression.** Runtime-identity is the gate, NOT byte-identity. Benign C-emission differences that do not affect functionality do not fail the gate.
- **Soft observation (not blocking):** the self-compile class re-count decreased-or-flat (recorded; if fixture is GREEN but count didn't drop, that's acceptable — it means full-graph-scale residual — as long as there's no functional regression).
- **Terminal gate: NO `rc=0` requirement.** Report the final self-compile error count as a metric; the true pass/fail = 21-example matrix + 4 MD5 gates runtime-identical.
- **4 MD5 gates (current authoritative baselines):** gol `4afb203fdde7a880ec6e7aed32543691`, lisp `5f886646b164a70c52bf042eb54bda78` (repo-root CWD), json `9720478c937409a29fe23ae0199821cf`, mud `a1d0dd55aada9c3fd904ae33f54de32e`. When an MD5 differs: the gate is **runtime-identical**, and re-baseline is the default response (not an exception).
- **`sf/build/out_release/` is WEDGED — NEVER touch/list/build into it.** All compiler runs `timeout 120`; `--output-dir` must pre-exist.
- **Build:** `bash sf/scripts/build_release.sh` → gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`; then reinstall std (`mkdir -p /tmp/fx_subfolder/lib && cp sf/src/std.zig std_io.zig std_arena.zig std_net.zig /tmp/fx_subfolder/lib/` — script wipes /tmp/fx_subfolder).
- **Editing:** `edit`/`fastedit` only (AGENTS.md §X.7: re-read region before each edit, bottom-to-top; fastedit: re-read after every edit, never `end_line = start_line - 1`).
- **Z98 constraints** (AGENTS.md §1.3): no anytype/@Type; concrete maps; `@intCast` for i32↔usize; switch requires `else`.
- **The plan is the ONLY authority.** STOP on any issue/confusion. Subagents mandatory.
- **Commit messages verbatim per task.**

## Out of Scope

- Making `build_zig1_5.sh` reach rc=0 as a hard gate (deferred; count reported as metric).
- Memory (AST-spill/16 MB) work.
- Non-residual fixes and the documented latents (value-position enum literals, qualified-member switch case labels) unless an R task proves one is the actual root of a class.
