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

### 3.2 Pass set (Pass 1) — AMENDMENT 1 (2026-09-06, grounded re-read)

Re-grounded against the actual LIR (lir.zig:22-91 `LirInst` union) and the emitter (`c89_emit.zig` emits one `zT_n = <expr>;` statement per op/literal arm, e.g. `.binary` :5326, `.unary` :5490, `.int_const` :5530; existing DCE computes per-temp `read_count` via `dceMarkReadPos`/`dceReleaseReadPos` :6771-6890). Four concretizations:

1. **Correction — "dead-temp" is largely already done by the emitter DCE.** The existing read-count liveness already skips unused temps. The real bloat is one statement per op/literal per intermediate even when used once. Pass 1 therefore targets **copy propagation, constant folding, and single-use expression nesting**, NOT re-implementing unused-temp deletion (the pass may still make liveness cheaper/earlier, but it is not the deliverable).
2. **Exact pure-vs-ordered classification** (verbatim `LirInst` kinds):
   - **PURE (fold / copy-prop / nest-safe):** `binary`, `unary`, `int_cast`, `float_cast`, `ptr_cast`, `int_to_float`, `ptr_to_int`, `int_to_ptr`, `int_const`, `float_const`, `bool_const`, `null_const`, `enum_const`, `string_const`, `undefined_const`, `set_optional_null`, `load`, `load_field`, `load_index`, `load_local`, `load_global`, `addr_of`, `addr_of_field`, `func_ref`, `make_slice`, `wrap_optional`, `unwrap_optional`, `check_optional`, `wrap_error_ok`, `wrap_error_err`, `unwrap_error_payload`, `unwrap_error_code`, `check_error`.
   - **ORDERED / side-effecting (never folded away, terminate any nesting chain):** `store`, `store_field`, `store_local`, `store_global`, `assign`, `assign_field`, `assign_index`, `call`, `call_direct`, `tail_call`, `print_str`, `print_val`, `builtin_*`, `va_start`, `va_arg`, `va_end`, `ret`, `ret_void`, `branch`, `switch_br`, `jump`, `loop_header`, `label`, `nop`.
3. **The materialization rule is "address taken".** Lowering is single-assignment (each result temp written once — SSA-like), so a temp can be inlined away iff: (a) it has exactly one value consumer, (b) its defining inst is PURE, and (c) **its address is never taken** (`addr_of`/`addr_of_field` referencing it) — otherwise it MUST stay a named local (it lives in memory). This is computed by a single backward pass setting an `addr_taken` bit per temp.
4. **The nesting mechanism is emitter-side `emitValueExpr(temp)`.** A new renderer that, for a single-use + pure + not-address-taken temp, recursively renders its defining inst as an inline C expression (reusing the existing cast/paren/sign/tag/sat rules from the arms); the value-consumer sites (`binary`/`unary` operands, `int_cast`/cast values, call args, `store`/`store_*` value, `ret`, `branch`/`switch_br` cond, `print_val` value) call it instead of `resolveTempName`. Insts that cannot nest still emit the current `result = expr;` form.

Pass 1 set (revised):
1. **Copy propagation** — `assign`/copy where the source temp is single-use, pure, not-address-taken → substitute the source at the consumer, drop the copy.
2. **Local constant folding** — a PURE op (binary/unary/int_cast/ptr_to_int-of-const etc.) whose operands are all `int_const`/`bool_const` folds to one `int_const` at LIR level (INTWIDTH width/sign semantics; lossless only — no silent wrap beyond the language's two's-complement value semantics).
3. **Expression nesting** — single-use pure chains (per items 2-4 above) emitted as one nested C expression via `emitValueExpr`; the LIR may be kept (temps dropped from the decl set) or rewritten — the census pins whether emission reads the optimized LIR or the renderer decides inline at the arm.

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
