# LIR Optimization Pass (Emission Tightening) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated pre-emission LIR optimization pass (`sf/src/lir_opt_pass.zig`) doing dead/redundant-temp elimination, copy propagation, local constant folding, and pure-chain expression nesting, shrinking the emitted C (measured ~7.6 MB zig1 self-emission vs ~3.3 MB zig0 gen-0 today) with **byte-identical runtime semantics** — then re-baseline the moved 4-MD5 gates + fixed point operator-ruled.

**Architecture:** A deterministic pass over each function's in-memory LIR immediately before c89 emission (after lowering and any spill reload). Rewrites instruction arrays + temps in place preserving semantics exactly. Emitted-C size + gcc wall/RAM (Rows C/E) are measured before and after.

Design spec: `docs/superpowers/specs/2026-09-06-lir-opt-pass-design.md` (operator-approved).

## Global Constraints

- **Full gate re-baseline posture** (operator ruling): LIROPTPASS changes every emitted program's C by design → the 4-MD5 dump-gate baselines (gol `302df36b`, lisp `3591bad9`, json `76056b97`, mud `846106ac`) and the self-compile fixed point MOVE and are re-baselined operator-ruled at the Task-5 STOP — never silent.
- **Correctness = RUNTIME byte-identity**: golden 9/9, matrix 21/21, corpus runs, upgraded-examples goldens, net round-trips byte-identical pre-vs-post; self-compile converges to a NEW fixed point (hop1==hop2).
- Pass lives in a new `sf/src/lir_opt_pass.zig`, run per function pre-emission post-reload, deterministic. No lowering change, no spill-format change, no emitter carrier change (PACK AMENDMENT 1 intact).
- `examples/z98` originals, goldens, `sf/build/`, `out_release/` untouched; stage ONLY intended files; pre-existing dirty/untracked set never staged.
- Reference compiler `/tmp/fx_subfolder/zig1` per the SEEDMIG seed model (committed seed `release/seed/zig1-seed.tgz` = zig0-built reference binary md5 `3707d33b…` + self-emission C; fixed point `24da89b9…`; provenance `release/seed/CHANGELOG.md`). Forward rebuild path: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <fresh-out>` — NEVER point `<fresh-out>` at `/tmp/fx_subfolder` (the script `rm -rf`s it); std lib (4 std `.zig`) is copied to `<fresh-out>/lib` by the script. `bash sf/scripts/build_release.sh` (zig0) remains usable ONLY while zig0 still compiles the current `sf/src` subset; the moment a task's `sf/src` needs syntax zig0 cannot parse, rebuild the reference from the seed (STOP-present on first such use). Bootstrap-staging constraint (binding): this plan's `sf/src` feature code (the new `lir_opt_pass.zig`) must be written in constructs the current seed already understands. Fixture/run recipe: `.superpowers/sdd/task-LANGWINS-report.md` Step-4 + release-0200 battery procedure (rows C/E under `/usr/bin/time -v`, median of 3).
- Fastedit per docs/sf/AGENTS.md X.7. Report `.superpowers/sdd/task-LIROPT-report.md`. Ledger `.superpowers/sdd/progress.md`. Memory agent `liroptpass-session`.
- Per-task evidence contract; STOP-present on divergence/ambiguity/plan-vs-evidence; subagent-driven execution.
- **Seed rotation is part of the Task-6 docs-GATE commit** (SEEDMIG model): Task 6 additionally runs `bash scripts/seed/archive_seed.sh <Task-5 fixed-point binary> <fresh gen dir> release/seed/zig1-seed.tgz --update-changelog`, staging `release/seed/zig1-seed.tgz` + `release/seed/CHANGELOG.md` alongside QUICK_REF.md + EXPECTED_FAIL.md (the seed rotates ONLY at this operator-approved closeout — never mid-plan). LIROPTPASS moves all four 4-MD5 gates AND the fixed point, so this rotation captures the new emission-era seed.

---

### Task 1: Record-only baseline + bloat profile (no commit)

- [ ] **Step 1: Baseline.** HEAD sha; reference md5; 4-MD5 gate values; self-emission byte count (41 `.c`, ~7.6 MB) + `.c` count; EXPECTED_FAIL version.
- [ ] **Step 2: Battery baseline.** Re-measure gcc Rows C and E (release-0200 procedure: `/usr/bin/time -v`, 3×, median wall + peak RSS) on the current compiler; record. (These are the "before" numbers.)
- [ ] **Step 3: Bloat profile.** Census of real emitted C: count emitted temp declarations, straight-line `zT_n = …;` assignment statements, and pure op chains (arithmetic/bitwise/cast/load) in a representative emitted function (e.g. one large `sf/src` module's C and one example program) to quantify the pass's targets. Record representative excerpts.
- [ ] **Step 4: Op/inst inventory.** List the LIR inst kinds (lir.zig) and classify each: pure (arithmetic `binary`/`unary`, casts `int_cast`/`float_cast`/etc., `int_const`, scalar `load` of an address, `load_bitfield`), ordered (stores, `store_bitfield`, calls, `ptr_to_int`/`int_to_ptr`, any op that can observe address identity or alias). Record which need to terminate a nesting chain and which are safe to fold/delete (this is the I deliverable refined in Task 2).
- [ ] **Step 5: Report + ledger.** Baseline + profile. No commit.

---

### Task 2: Pass design verification (I, read-only) — purity + algorithm + safety

- [ ] **Step 1: Purity/aliasing rule.** Use spec §3.2 AMENDMENT-1 (verbatim `LirInst` pure/ordered lists). Define precisely the "address taken" materialization rule: a temp may be inlined away iff (a) exactly one value consumer, (b) defining inst is PURE (from the verbatim list), (c) its address is never taken (`addr_of`/`addr_of_field` referencing it → stays a named local). Justify each classification against the emitter's C rendering (does the C op read memory? is it volatile/ordered?). Document what a nesting chain may cross and what terminates it.
- [ ] **Step 2: Algorithm design.** Specify the per-function algorithm: single backward pass computing use-counts + the `addr_taken` bit; copy-propagation (single-use, pure, not-address-taken `assign`/copy sources); constant folding over PURE ops whose operands are all `int_const`/`bool_const` (INTWIDTH width/sign semantics, lossless only); the single-use pure-chain criterion for nesting. State data structures + in-place rewrite order and the determinism argument. NOTE the existing emission-side DCE already removes unused temps — the deliverable is copy-prop/const-fold/nesting, not re-implemented dead-temp deletion.
- [ ] **Step 3: Interaction audit.** Confirm interactions: the existing emission-side DCE (c89_emit liveness) still correct on optimized input; spill/`-sN` reload ordering (pass runs post-reload, before emission; no re-spill needed or the exact ordering the census pins); packed/INTWIDTH ops (`load_bitfield`/`store_bitfield`, `enum(uN)`, narrow-int) handled as classified (safe-fold vs chain-terminator); no effect on `--dump-c89` determinism. STOP-present if any interaction is unsafe/ambiguous.
- [ ] **Step 4: Report.** Purity rule, algorithm, interaction verdicts appended to the report (and to the spec as an addendum if non-trivial). No commit.

---

### Task 3: Implement dead-temp + copy-prop + local const-fold (semantics-preserving)

- [ ] **Step 1: Implement** `sf/src/lir_opt_pass.zig` entry + copy propagation and local constant folding from the Task-2 algorithm (spec §3.2 AMENDMENT-1: pure ops from the verbatim list; `int_const`/`bool_const` operand folding; lossless INTWIDTH width/sign semantics). The existing emitter DCE already removes unused temps — do NOT re-implement dead-temp deletion. Wire the entry into the emission phase (per function, post-reload, pre-emitter).
- [ ] **Step 2: Wire + smoke.** Rebuild; self-compile round-trip rc0, 0 `error[`, 0 PANIC; `hello` and a small program compile+run byte-identical output.
- [ ] **Step 3: Run-identity gate.** golden 9/9 + matrix 21/21 runs byte-identical to pre-pass captured outputs; corpus runs zero-class-change on the common set. Record emission-size delta (self-emission byte count now vs Task-1 baseline).
- [ ] **Step 4: Record.** 4-MD5 gate values (moved — record, do NOT re-baseline), fixed point round-trip (converges to a new hop md5 — record), concerns.
- [ ] **Step 5: Commit.**

```bash
git add sf/src/lir_opt_pass.zig sf/src/<wiring per census>
git commit -m "feat: LIR opt pass — dead-temp + copy-prop + local const-fold (LIROPTPASS)"
```

- [ ] **Step 6: Report + ledger.**

---

### Task 4: Pure-chain expression nesting

- [ ] **Step 1: Implement** the nesting phase per Task-2 (spec §3.2 AMENDMENT-1 items 3-4): the "address taken" materialization rule + single-use pure chains emitted as nested C expressions via a new emitter-side `emitValueExpr(temp)` renderer (recursively renders a single-use + pure + not-address-taken temp's defining inst inline, reusing the existing cast/paren/sign/tag/sat rules); the value-consumer sites (`binary`/`unary` operands, cast values, call args, `store`/`store_*` value, `ret`, `branch`/`switch_br` cond, `print_val` value) call it instead of `resolveTempName`. Non-nestable insts keep the current `result = expr;` form. The census pins whether emission reads optimized LIR or the renderer decides inline at the arm.
- [ ] **Step 2: Wire + run-identity gate.** Rebuild; self-compile rc0/0 err/0 PANIC; golden 9/9 + matrix 21/21 runs byte-identical; corpus zero-class-change; upgraded-examples goldens + net round-trip byte-identical.
- [ ] **Step 3: Measure.** Self-emission byte count + gcc Rows C/E re-measured (3×, median) vs Task-1 baseline; record the reduction + gcc wall/RAM delta.
- [ ] **Step 4: Record.** New 4-MD5 gate values + fixed point (record, no re-baseline); concerns (any run-identity surprise → STOP-present).
- [ ] **Step 5: Commit.**

```bash
git add sf/src/lir_opt_pass.zig sf/src/<emitter per census>
git commit -m "feat: LIR opt pass — pure-chain expression nesting (LIROPTPASS)"
```

- [ ] **Step 6: Report + ledger.**

---

### Task 5: Full battery + gate re-baseline STOP-present

- [ ] **Step 1: Battery.** golden 9/9 + matrix 21/21 runs byte-identical; full corpus run-class zero-asymmetric vs Task-1; upgraded-examples + net goldens byte-identical.
- [ ] **Step 2: Self-compile.** hop1==hop2 at the NEW fixed point (42-ish `.c`, 0 `error[`, 0 PANIC).
- [ ] **Step 3: Emissions.** Record the new 4-MD5 dump-gate values + emission-size/battery deltas.
- [ ] **Step 4: STOP-present.** Re-baseline proposal for ALL FOUR gate rows + the fixed point (operator-ruled); QUICK_REF gate-table + fixed-point + new-bullet docs update in Task 6 AFTER operator approval; seed rotation to the new fixed point also happens in Task 6 (never here). No commit, no docs touched.

---

### Task 6: Docs GATE (after operator approval)

- [ ] **Step 1: QUICK_REF.** Gate-table rows gol/lisp/json/mud → new values; newest-first baseline bullet (LIROPTPASS landed: dead-temp/copy-prop/const-fold/nesting; emission-size + gcc wall/RAM deltas; run-identity evidence; fixed point re-baseline).
- [ ] **Step 2: EXPECTED_FAIL.** No fixture class changes expected (runs identical); if any corpus/EXPECTED_FAIL row's *reason* text references emission internals, reconcile; otherwise version-bump only if convention requires. Record.
- [ ] **Step 3: Commit.**

```bash
git add docs/sf/QUICK_REF.md repro/mi_matrix/EXPECTED_FAIL.md
# Seed rotation (SEEDMIG model): rotate the committed seed to the Task-5 fixed-point binary
bash scripts/seed/archive_seed.sh <Task-5-fixed-point-binary> <Task-5-fresh-gen-dir> release/seed/zig1-seed.tgz --update-changelog
git add release/seed/zig1-seed.tgz release/seed/CHANGELOG.md
git commit -m "docs: GATE — LIR opt pass emission re-baseline + seed rotation (LIROPTPASS)"
```

- [ ] **Step 4: Report + STOP-present plan close.** Language-wins follow-on order items 6-10 all delivered. Operator authority for any further plan.

---

## Plan Self-Review

1. **Spec coverage:** baseline+profile (T1), purity/algorithm I (T2), temp/dead/copy/const (T3), nesting (T4), battery + full gate re-baseline STOP (T5), docs GATE (T6); success metric = measured size + gcc deltas + run-identity; operator rulings honored.
2. **Placeholder scan:** no TBD; exact op classes/algorithms are the Task-2 I deliverable (established pattern); per-file census anchors resolved in record-only Task 1.
3. **Type/name consistency:** `lir_opt_pass.zig` + `lirOptRun`-style entry (final name per file convention in T3); report `task-LIROPT-report.md`; memory agent `liroptpass-session`.
