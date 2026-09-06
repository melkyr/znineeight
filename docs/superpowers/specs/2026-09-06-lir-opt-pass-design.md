# LIR Optimization Pass (Emission Tightening) — Design Spec

**Date:** 2026-09-06 · **Branch:** zig1_start · **Type:** compiler internal (language-wins follow-on; plan item 10 LIROPTPASS)

## 1. Purpose

Reduce zig1's C89 emission bloat by optimizing the **LIR before c89 emission**. Measured motivation (release-0200 battery, 2026-09-06): zig1's C89 self-emission of `sf/src/main.zig` is ~7.6 MB across 41 `.c` vs zig0's gen-0 ~3.3 MB across 43 `.c` (~2.3× denser in zig0); that bloat drives the measured gcc peak ~166 MB for the `zig1_5` self-emission step vs ~85 MB for gen-0 (Rows E vs C). The bloat is pervasively *one C temp + one statement per subexpression, with unused/redundant temps and no expression nesting*. LIROPTPASS removes that at the LIR level so the emitted C is smaller, gcc input drops (RAM + wall), and generated binaries are tighter.

## 2. Binding operator decisions

- **Pass 1 scope includes expression nesting** (not just temp/dead/copy-prop/const-fold): pure op chains whose results have a single consumer are emitted as a nested C expression instead of a temp chain. (Operator ruling: "Also expression nesting now".)
- **Placement = a dedicated pre-emission pass module** `sf/src/lir_opt_pass.zig`, run per function right before c89 emission over the in-memory LIR (after any spill reload at `-sN`); deterministic; no lowering change; no spill-format change. (Operator ruling.)
- **Full gate re-baseline posture**: LIROPTPASS changes every emitted program's C by design, so all four 4-MD5 dump-gate baselines (gol `302df36b`, lisp `3591bad9`, json `76056b97`, mud `846106ac`) and the self-compile fixed point MOVE and are operator-ruled re-baselined at the battery STOP — never silent. (Operator ruling.)
- **Correctness guard = RUNTIME byte-identity**: golden 9/9, matrix 21/21, corpus runs, upgraded-examples goldens, and the net/self-host round-trips must remain byte-identical (only emission text changes). Self-compile must converge to a NEW fixed point (hop1==hop2).
- **Success metric**: measured emitted-C byte-size reduction (zig1 self-emission) + re-measured gcc wall/RAM drop (release-0200 Rows C/E procedure). No overclaim of zig0 parity; the reduction is measured and reported.
- The carrier/emission encoding decisions remain emitter-owned (PACK AMENDMENT 1); LIROPTPASS operates at the LIR level, agnostic to which backend encoding the emitter chooses.

## 3. Architecture

### 3.1 Pass module
- New `sf/src/lir_opt_pass.zig` with one entry `lirOptRun(reg, ctx, lir_fn) void` (or the file's convention), invoked per function in the emission phase immediately before the emitter walks the function (after lowering and after any spill reload). Deterministic: the same LIR always yields the same optimized LIR.
- The pass rewrites each function's instruction array + temps in place (growable structures) preserving semantics exactly.

### 3.2 Pass set (Pass 1)
1. **Dead/redundant-temp elimination**: an instruction whose result temp is never read and has no side effect is removed. (Note: the existing emission-side DCE stays; the pass makes more of it visible and cheaper, and removes *emission scaffolding* like unused `(void)`/temp decls earlier.)
2. **Copy propagation**: `b = a` where `a` has no other use/aliasing → replace later reads of `b` with `a`, drop the copy.
3. **Local constant folding**: `int_const` arithmetic/bitwise/shift/compare of two `int_const`s folds to one `int_const` (careful: width/sign semantics per INTWIDTH; only fold when lossless — no silent wrap surprises beyond the exact two's-complement value semantics the language already defines).
4. **Expression nesting (pure-chain DAG)**: a chain of *pure* instructions (arithmetic/bitwise/shift/casts/scalar loads of a value already materialized, bitfield loads) each with exactly one consumer and no intervening side effect is emitted as one nested C expression rather than a temp chain. Requires a precise **purity/aliasing rule** (I task): stores, calls, `load_bitfield`/`store_bitfield`, volatile/ordered ops, memory writes, and any instruction that could observe address identity must terminate a chain.

### 3.3 Correctness invariants
- Semantics of the program are unchanged (runs byte-identical). Only the C *encoding* of pure dataflow changes.
- Deterministic: identical input LIR → identical output (needed for the fixed-point/hop property).
- Spill/`-sN`: the pass runs after reload so spilled functions are optimized identically to non-spilled ones (the optimized result must be re-serializable only if the emitter reads optimized LIR — the census pins the exact ordering; if emission consumes LIR from the in-memory structure after reload, the pass runs post-reload and no re-spill is needed).

## 4. Measurement / acceptance evidence

- Baseline (Task 1): reference compiler self-emission byte count (7.6 MB / 41 `.c`), gcc Rows C/E (release-0200 procedure), gate values.
- Post (Task 5): self-emission byte count + gcc Rows C/E re-measured; delta reported. Gate re-baselines + fixed point re-baseline proposed operator-ruled.
- Run-identity evidence: golden 9/9 + matrix 21/21 + corpus runs byte-identical to pre-pass captured outputs; self-compile hop1==hop2 at the new fixed point.

## 5. Out of scope (later plans)

- Cross-basic-block/CFG optimization, inlining, loop transforms, alias analysis beyond the purity rule, spill-format changes, target-specific lowering, changing the emitter's carrier decisions (PACK AMENDMENT 1) — later LIROPTPASS iterations.
- Depends on nothing new from INTWIDTH/PACK (operates on LIR only) but must not conflict with PACK/INTWIDTH emission changes (executes after them in the order; pass must handle `load_bitfield`/`store_bitfield`/packed-carrier ops as opaque or pure where safe — the I task lists the op classes).
