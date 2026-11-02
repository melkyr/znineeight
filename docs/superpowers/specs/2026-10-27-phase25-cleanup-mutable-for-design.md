# Phase 2.5 — Compiler Cleanup + Mutable-For + Fold: Design

> Status: draft for operator approval
> Date: 2026-10-27
> Sits between: P3 (toolchain/debugger, shipped) and P4 (gfx+editor, paused)

## Intent

Fix accumulated compiler defects before adding language features. Rationale (operator): "for future milestones the code will start to look even worse" — adding mutable-for and fold on top of the current structural debt makes the codebase worse; future milestones need a clean base.

## Goals

1. **Structural rot cleanup** — delete unreachable fallback tails in `lowerStmtLeaf*` (each carries a duplicated pre-T4 dispatch chain; `lowerStmtLeafFor` is ~250 lines of unreachable code), add builtin name-table completeness test (sema/lower/comptime drift), harden the delivery-scan TEMP_NONE protocol.
2. **Deferred review minors** — D9 refinements (`SEMA_GUARD_MAX` 128→~200 + limit-family classification), M4 leftovers (Win32 cmdline quoting, PE→COFF fallback, FILE aux long names, recipe `-fno-omit-frame-pointer`, real-MSVC COFF fixture recipe), `.zig1_dbg.tmp` litter, gate pipefail.
3. **Mutable `for` capture (`|*item|`)** — highest-leverage language gap from the example-idiom audit (no mutable for-capture is the root of the "C in Z98 clothes" style).
4. **Std-lib fold** — `foldU32`/`foldI32`/`foldUsize` per-type free functions; zero compiler work.
5. **Seed v124 rotation** + docs truth-up.

## Non-goals

- `@fold` builtin (deferred: 3-5 tasks, intern-id shift risk across three name tables).
- Generics, closures.
- no-CRT compiler (deferred to asm_x86).
- Real MSVC/OpenWatcom/Win98 hardware validation (operator-run).

## Anti-goals

- Do not change emitted C for existing code (byte-identity contract).
- Do not move the 8 pins without explicit authorization.
- Do not add new builtin intern points that shift name ids.

## Constraints

- Z98 strict subset, C89 output. `edit`/`fastedit` only. No push. `run.err` untouched. Implementers use no subagents.
- Corpus frozen-1124: 0 movers. 8 pins unmoved.
- Seed rotation at milestone end (`scripts/seed/archive_seed.sh --update-changelog --win9x-zip`).

## Decisions

### Mutable `for` capture
- Syntax: `for (iterable) |*item|` — `*` before the capture name.
- Capture type: `*T` (mutable iterable: `[]T`, `*[N]T`, mutable binding) / `*const T` (const iterable: `[]const T`, `*const [N]T`, `const` binding). Sema derives constness via `semanticAnalyzerIsLValueConst` (`semantic_analyzer.zig:4495`).
- Range capture rejected: `for (0..n) |*i|` → new diagnostic (range has no addressable element). Both `range_exclusive` and `for_index_range` wrappers handled.
- Address form: `load_index(decay=2)` → `&base[idx]` (uniform); `decay=1` → `&(*base)[idx]` (ptr-to-array). Emitter already supports both (`c89_emit.zig:188-235`). No new emitter op.
- C89: `const` dropped in C (`type_registry.zig:573-615`); constness enforced by sema only. Acceptable (house model).
- Sema→lower constness channel: new side channel (resolved-type entry on `for_stmt` node or parallel table). Lowering's `ptr_temp` is currently hard-coded non-const (`lower.zig:13407`, `:13437`) and must carry the sema pointer type.
- `parserParseCaptureName` (`parser.zig:701-702`) consumes the leading `|` itself and is shared by 5 sites (`:1002,1129,1898,1960,2036`) — add a parameter or inline the name parse at the for site. Do NOT break the other 4 callers.

### Std-lib fold
- `pub fn foldU32(xs: []const u32, acc: u32, f: fn (u32, u32) u32) u32` — per-type free functions in new `sf/src/std_fold.zig`.
- Also `foldI32`, `foldUsize`. No `foldPtr` in v1.

### Structural rot: `lowerStmtLeaf*` tails
- `lowerStmtStep` (`lower.zig:12851-12883`) routes all 7 machine kinds (block/labeled/if/while/for/swt/expr_stmt) to phase machines; `lowerStmtLeafStep` is the fallback for the rest.
- Each `lowerStmtLeaf*` function (`Block` :13773, `If` :13867, `While` :14056, `For` :14204, `Switch` :14455, `Return` :14586, `Jump` :14813, `VarDecl` :14920, `Misc` :15139) ends in a **duplicated pre-T4 dispatch chain** that re-calls the other leaf functions. Those tails are unreachable: `lowerStmtLeafStep` dispatches by kind before calling, so each function only ever sees its own kinds.
- `lowerStmtLeafFor` (`:14204-14454`) is entirely unreachable (for_stmt is machine-routed at `:12871`).
- Decision: **delete the unreachable arms**. `lowerStmtLeafStep` keeps only non-machine kinds (defer, errdefer, return, break, continue, var_decl, assigns, else). `lowerStmtLeafBlock` keeps only defer/errdefer (its block/labeled arms are machine-routed). Delete `lowerStmtLeafIf`/`While`/`For`/`Switch` entirely if no caller remains. Trim the duplicated tail chains from `lowerStmtLeafReturn`/`Jump`/`VarDecl`/`Misc`. Verify byte-identity + corpus 0 movers before/after.
- If any corpus input proves reachable, STOP and reconsider (do not silently keep the fallback).

### Builtin name tables
- Do **not** unify (intern-id shift risk). Add **completeness test**: `scripts/compiler/gate_builtin_names.sh` compares `"@..."` string-literal sets across `semantic_analyzer.zig`, `lower.zig`, `comptime_eval.zig`. Fail on drift.

### Delivery-scan TEMP_NONE
- Invariant documented at `lower.zig:2318-2330`. Add a `@panic` if `child_res == TEMP_NONE` is delivered to a machine slot. Verify it never fires on the corpus. If it fires, the invariant is wrong — STOP.

### D9 refinements (supersedes the "keep ICE for now" ruling)
- Raise `SEMA_GUARD_MAX` 128 → 200 (measure wall at 1MB first; settle at the measured value, may be 180).
- Reclassify `ERR_9001_ICE` → limit-family classification so the corpus `ICE_RE` (`scripts/corpus/classify:31`, `error\[(48|9001|3043)\]`) no longer buckets guard-trips as ICE. Risk: corpus classification changes. Must measure before/after.

## What's left to the builder

- Exact wording of the range-rejection diagnostic and its error code.
- Whether `SEMA_GUARD_MAX = 200` is achievable at 1MB (measure; may settle at 180).
- Whether the delivery-scan `@panic` fires on any corpus input (if so, the invariant is wrong).
- Real-MSVC COFF fixture validation (operator-run recipe in `lin_bin/instructions.txt`).
- Whether the leaf-tail deletion is safe on all 1188 corpus dirs + 336 stdlib + 26 examples (byte-identity proof).

---

## Addendum 2026-10-28 — Win9x toolchain conformance + GUI side task (operator rulings)

Scope added after the operator's Win98/OWC bring-up (`lin_bin/error/` evidence: OWC `E1058` typedef-as-variable, `winnt.h` `E1026/E1043`, `zig_nocrt.c` `E1123`, LF batch files, 16-color VM failures):

- **Task 7 — Win9x toolchain conformance (compiler work):**
  - D11 (new defect entry): emitted C mixes declarations and statements (`decl_local` names appear after the `zig_poison_fill` preamble). Fix = hoist declarations before statements; strict C89. One-time 8-pin re-baseline authorized (dump bytes move; goldens/runtime unchanged).
  - `zig_nocrt.c` must always provide at least one external definition (OWC rejects typedef-only TUs).
  - **CRLF rule:** every Windows-facing text artifact ships CRLF — emitted `.bat`/`.lnk`/`.rsp`, `README.txt`, `SEED_README.txt`, and every repo dev `.bat`. Gate-enforced. `build_target.sh` (shell) stays LF; the gate never demands CRLF on `.sh`.
  - **Flag policy:** generated scripts drop OWC `/za`/`/we` and MSVC `/Za`/`/WX`; the codebase is to be warning-error-clean, with per-warning relaxation only after the operator's OWC/MSVC census if unfixable.
  - **Warning-clean dialect + scope (2026-10-28 amendment):** `gate_warn_clean.sh` = `gcc -std=c89 -pedantic -Wall -Werror -Wno-long-long` over the emitted program C **and all shipped runtime C** (`zig_runtime.c`, `zig_pal.c`, `zig_nocrt.c`, `c_exit.c`). `-Wno-long-long` is the sole suppression and is gcc-gate-only — it must never appear in generated MSVC/OWC script strings; the emitted `zig_compat.h` already maps `_MSC_VER`→`__int64`/`ui64` and `__WATCOMC__`/gcc→`long long`/`ULL`, and the operator's OWC logs show zero long-long diagnostics. Step 1 enumerates the full warning-category census (whole self-emission + runtime); each category is fixed in-scope or STOP-ped for a ruling. MSVC/OWC validation remains operator-run (no local toolchains; `<repo>/lin_bin/error/` holds OWC logs only).
  - **MinGW fallback script:** `build_mingw_crt.bat` + `build_mingw_nocrt.bat` (Windows-hosted gcc) emitted with every `-osw` output and shipped in the seed `win/`.
- **Task 9 (T7b) — emission warning-clean at the origin (2026-10-28 amendment):** `gate_warn_clean.sh` = gcc `-m32 -std=c89 -pedantic -Wall -Werror -Wno-long-long` (sole suppression) over the **full self-emission** + shipped runtime + representative programs; every warning class is fixed at its emitter/runtime origin (pointer-sign cast discipline, implicit prototypes, overlength literal, header-static externalization, trailing returns). The **single** 8-pin re-baseline happens at the END of Task 9 — Tasks 7 and 9 both move dump bytes, so Task 7 records interim values and documents its pin case as expected-RED.
- **Runtime single source:** `sf/src/emit_support.zig` is the only hand-edited support source; `sf/src/include/*` becomes a generated snapshot refreshed by `scripts/gen_emit_support.sh <built-zig1>` and guarded by `scripts/check_emit_support.sh` (no hand edits after Task 7 Step 0).
- **Task 8 — GUI side task:** 16-color (4bpp) machines get an automatic GDI-only fallback in `std_gfx_pal` (DirectDraw init failure or depth < 8bpp); fatal startup errors become visible (`MessageBoxA`) in GUI builds. Cell API unchanged.
- Seed target for the milestone closeout: **v128** (v124–v127 already shipped).
