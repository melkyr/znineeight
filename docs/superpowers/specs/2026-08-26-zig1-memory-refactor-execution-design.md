# zig1 Memory Refactor Execution — Allocation → Warnings → Migrations — Design

**Date:** 2026-08-26
**Status:** DRAFT (awaiting operator approval)
**Branch:** zig1_start
**Baseline:** HEAD `a4171677` (roadmap doc); reference zig1 `/tmp/fx_subfolder/zig1`, self-compiled `/tmp/zig1_5/zig1_5_clean`

## Goal

Execute the zig1 memory refactor roadmap (self-compile pool ≤ 16 MiB, never-OOM-Windows) **and** make the emitted C compile **warning-clean at `-O2`/`-O3`** (so mingw/msvc6/openwatcom will not raise them). Ordered per operator ruling: **allocation wins first → warnings second (they add code) → struct migrations third**.

## Scope Decisions (operator-ruled 2026-08-26)

- **One big plan** covering all roadmap items (0-7) + all `-O2`/`-O3` warning classes (incl. the benign tail → warning-clean build).
- **Ordering:** Phase 1 allocation wins (roadmap items 0, 3, 4(a)) → Phase 2 warnings (portability) → Phase 3 struct migrations (items 1, 2, 5) → Phase 4 tail (item 7 markers, item 6 spill reserve, GATE).
- **Golden-sample runtime protocol:** at the start of every emission-affecting task, capture a **golden sample** with the reference zig1 (its emission + compiled/run stdout+rc for the gate + runtime-fixture set) into a gitignored dir. When byte-identity breaks, runtime must match the golden sample — never guessed.
- **Byte-identity:** 4 MD5 gates are keep-or-re-baseline with golden-sample evidence (operator pre-authorized re-baseline; emitter fixes A2/A3/A5 are emission-affecting by design).
- **Hard target frame:** zig1 self-compiles ≤ 16 MiB pool; compilation never OOMs a 32 MB physical P3/P4 Win98 host. zig0 dialect is the binding constraint (no packed/bitfield/anytype/@Type); custom binary encoding allowed.
- **Everything incl. benign tail:** the plan targets **0 warnings** at `-Wall -Wextra -O3` on both the compiler's own emitted C and `zig1_5`'s emission.

## Background — measured facts (2026-08-26)

- **Pool 83,210 K = 5.08× the 16 MiB (16,384 K) target; live total 20,372 K = 24.3% over.** Pool gap ≈ 61.4 MiB, of which **allocation-strategy ≈ 58 MiB** (module chain 64 MiB for 16.4 MiB live = 4.0× doubling overshoot; never-reclaimed per-`@import` arenas 4.2 MiB; scratch 6.2 MiB; perm 2.1 MiB). Live gap = 3,988 K ≈ 3.9 MiB (AST 5.76 MB + LIR 3.5-4.2 MB + resolution tables, simultaneously resident at lowering).
- **`checkCombinedPeak` (allocator.zig:216-228) gates pool.peak vs POOL_SIZE (256 MiB), NOT max_mem (16 MiB) — 16 MB budget UNENFORCED** (`--max-mem` dead, main.zig:142/914-917).
- **Allocation levers (roadmap items 3+4):** exact-fit final segment + growth cap kill most of the 58 MiB; per-`@import` arena reuse recovers 4.2 MiB. Zero code migration.
- **Struct migrations (items 1+2+5):** AstNode 32→24 B (−1.44 MB), LirInst 32→20 B (−1.3-1.5 MB), side arrays + token union (−0.75-0.9 MB). After these, live ≈ 16.5-17 MiB; crossing ≤16 MiB needs item 5's optimistic edge or item 6 spill.
- **`-O2`/`-O3` warnings (all pre-existing in the reference emission; surfaced by optimization):**
  1. **Zero-length arrays** — `unsigned int dummy[0]` at source_manager.c:285/290 (empty u32-slice emission) → **C90-invalid, breaks msvc6/openwatcom**.
  2. **Maybe-uninitialized ×3** — `lower.zig:1553/1573` `payload_tid` (bindOptionalCapture / maybeDisambiguateCaptureIfTypeDiffers; flagged at -O2 and -O3), `parser.zig:1100` `member_buf` (parserParseErrorSetDeclBody; flagged -O3-only IPA). Read may be guarded (member_buf guarded by `member_count > 0`); payload_tid reachability needs verification.
  3. **Shift-parens loss** — `comptime_eval.zig:146/190` `(1 << (wb - 1))` emits `(1ULL << (u64)wb - 1U)`; C semantics correct (shift by wb-1) but gcc `-Wparentheses`.
  4. **Benign tail** (128-129 warnings): unused discard temps (`_`, `__1`, `wt2_1`…), unused labels (`__loop_0_end`), unused params/static fns, duplicate `const`, ISO C90 decimal constants (`4294967295`, `2166136261`, `18446744073709551615`), string-literal pointer init.
- **`-O3` verification (measured):** zig1_O3 builds clean (0 errors), self-emission byte-identical, RSS 40,404 KB ≈ -O0, **pool/total byte-identical to -O0** (memory is `-O`-independent), self-compile wall 0.48 s (vs 1.32 s) = 2.75× faster.

## Architecture — 4 phases, 14 tasks

- **Phase 1 — Allocation wins (3 tasks):** M0 budget tripwire; M3 segment-growth policy (exact-fit); M4 per-`@import` arena reuse.
- **Phase 2 — Warnings (5 tasks):** W-I investigate maybe-uninit; W-1 zero-length array; W-2 shift-parens; W-3 source `undefined` fixes; W-4 benign-tail emitter cleanup → **0 warnings**.
- **Phase 3 — Struct migrations (3 tasks):** M1 AstNode 32→24; M2 LirInst 32→20; M5 AST side arrays + token union.
- **Phase 4 — Tail (3 tasks):** M7 marker coarsening; M6 I/O spill (reserve, gated on pool still >16 MiB); GATE full sweep + reconciliation.

## Components / Data Flow

- Emitter fixes live in `c89_emit.zig` (W-1, W-2, W-4) — these change the emitted C for **every** program (self-emission and user emission). Source `undefined` fixes live in `lower.zig`/`parser.zig` (W-3). Memory fixes live in `allocator.zig`/`main.zig` (M0, M3), `parser.zig` (M4), `ast.zig`/`lir.zig`/`token.zig` + their consumers (M1, M2, M5), `pal.zig`/`main.zig` (M7).
- Golden sample per emission-affecting task: `/tmp/golden_<TASK>/` (gitignored) = reference zig1 emission + run outputs of the 4 gates + runtime fixture set.
- Runtime fixture set (deterministic, covers parser/lower/emit/TCO/fn-ptr/std): `emission_assoc_chain_xmod`, `tco_return_try`, `tco_defer`, `tco_factorial`, `fn_ptr_struct_field`, `quicksort`, `func_ptr_return`, `hello`, `emission_lower_crash_xmod`.

## Error Handling / Testing

- **Runtime is the oracle:** every task's acceptance = golden-sample runtime matches (byte-identity may be re-baselined with evidence).
- Standard gates each task: rebuild zig1 + zig1_5, self-compile 0 errors, 4 MD5 keep-or-re-baseline, Z98 dialect, `timeout 120` (900 builds).
- Warning-clean gate (Phase 2 end + GATE): `-Wall -Wextra -O3` on the emitted compiler C and on `zig1_5`'s emitted C → **0 warnings, 0 errors**.
- Pool measurement: `--track-memory --markers` self-compile → `pool=` ≤ 16,384 K (target), or documented spill-reserve fallback (M6).
- Memory is `-O`-independent (measured): allocation/migration progress is verified by `pool=`/`total=` at any `-O`.

## Out of Scope

- The migration to a richer dialect (future objective).
- Any roadmap item beyond items 0-7 (no new features).
- Re-baselining execution itself (operator rules per-task on golden evidence).
- Any `sf/build/out_release/` or non-plan source changes.
