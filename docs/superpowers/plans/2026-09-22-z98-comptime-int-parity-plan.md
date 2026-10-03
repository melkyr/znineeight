# Z98 trailing compiler-issue parity — implementation plan

> **For agentic workers:** use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax. This plan is **pending to start**.

**Goal:** retire the trailing compiler divergences found while building the Volume I manual, matching official Zig 0.15.2. **Part I** (Step 0 + Tasks 1–6): replace Z98's 64-bit `{bits, sig}` comptime integers with an arbitrary-precision, signedness-free representation — removing the bounded divergence ruled in Task 9D (b). **Part II** (Tasks 7–19): the folded trailing issues (loop-capture `@intCast` invalid C; void/value-`if` statement residuals; comptime float comparisons; capture/lifetime bookkeeping; the index-capture parser gap; the seed-tooling fallback; method-call syntax/unknown struct members; call arity + argument types; `pub` visibility; comptime-known out-of-bounds index rejection; related-span diagnostics + non-ASCII message audit; then the whole-plan closeout), each with the same deliverable discipline.

**Architecture:** a small fixed-cap big-int (`ComptimeInt`) inside `sf/src/comptime_eval.zig`; signedness resolved only at coercion into a typed slot; comparison by magnitude+sign.

**Spec:** `docs/superpowers/specs/2026-09-22-z98-comptime-int-parity-design.md` (read both).

**Sequence:** PREVIOUS: `docs/superpowers/plans/2026-09-22-z98-manual-volume-I-plan.md` (Volume I — complete, including the test-hardening and visual-polish passes). **NEXT: when this plan completes, execute `docs/superpowers/plans/2026-09-22-z98-print-formatting-plan.md`** (the `print`-formatting parity plan). **After that, create the Volume II plan** (brainstorm + writing-plans).

## Global Constraints

- **Official Zig 0.15.2 is the oracle** (`/tmp/zig-x86_64-linux-0.15.2/zig`); never zig0. Every behaviour claim is validated against it.
- **Wrap EVERY binary in `timeout 120`**; never `pkill`/`kill`/`killall`; never run a blocking command.
- Use `fastedit`/`edit` per `docs/sf/AGENTS.md` §X.7; `sf/src` edits move the self-emission fixed point.
- Seed build `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/<n>`; rotate with `scripts/seed/archive_seed.sh … --update-changelog` whenever the fixed point moves.
- Each task: fixture(s) in `repro/mi_matrix/` (+ `expected.txt`/`.rc`, deterministic 3×) + standalone `repro/` program + the full QUICK_REF gate battery; **STOP and report on unexpected movement** (4-MD5 expected UNCHANGED).
- Every task ends with tech docs per AGENTS §1.1.1, `docs/sf/QUICK_REF.md`, `repro/mi_matrix/EXPECTED_FAIL.md`, and a commit.
- No scope creep: no generics/reflection, no float-precision work, no unrelated fixes.

---

### Step 0 (M): Freeze the divergence inventory

- [ ] Extend and run the Task 9D shape matrix (`/tmp/…` probes) against the **current** compiler + the Zig 0.15.2 oracle; record every fold shape whose signedness is recovered by a heuristic today (`declared type`, literal, `@intCast`/`@as`, `0 - X`) and every currently-unfoldable shape, in a table in the report.
- [ ] Confirm the 4-MD5/corpus baseline (do not change code).
- [ ] Report the frozen table (it becomes Task 1's input).

### Task 1 (I): Design the representation + coercion rules

- [ ] Decide the limb layout/cap (e.g. 8×u32 = 256 bits), the overflow policy (unfoldable → the existing reject path), and the exact coercion/range-check rules per target kind (ints, arb ints, enum backings, array sizes) preserving today's diagnostics.
- [ ] Enumerate every consumer of `ComptimeVal.bits`/`.sig` in `sf/src` and specify how each migrates.
- [ ] Report: representation, op inventory, coercion table, migration list, risk notes. No code.

### Task 2 (F): `ComptimeInt` core + arithmetic

- [ ] Implement the big-int core and add/sub/mul/div/mod/negate/bit ops/shifts at arbitrary precision with Zig-truncating division; replace the 64-bit integer paths in `comptimeEvalBinOp`/`comptimeEvalEvaluateDepth`.
- [ ] Fixtures: arithmetic at/beyond 64 bits (e.g. `2^64`, `2^100` magnitudes), Zig-oracle-checked; a no-over-rejection control for in-range values.
- [ ] Gate battery + seed rotation + docs + commit.

### Task 3 (F): Signedness-free comparisons + logical folds

- [ ] Compare by magnitude+sign; make `cmp_eq/ne/lt/le/gt/ge` and short-circuit `and`/`or`/`not` Zig-exact for arbitrary magnitudes; delete `comptimeEvalSignClass`/`comptimeEvalOperandCompareSigned`/the `0 - X` special case.
- [ ] Fixtures: the Task 9D divergence shapes (`(umax - 1) > 0`, `0 < (umax - 1)`, `(umax - 1) > zero`, `umax > (0 + 0)`, `(a + 1) == 2`) now ACCEPTED and Zig-equal; `umax < 0` still rejected; the over-acceptance shapes still rejected; unreduced `i64`-extreme comparisons exact.
- [ ] Flip `comptime_compare_diverge_reject_xmod` into the accept path (or replace it) and update EXPECTED_FAIL/spec §7.2; gate battery + seed + docs + commit.

### Task 4 (F): Coercion into typed slots

- [ ] Make every materialisation site range-check the `ComptimeInt` against the target's width/signedness (decls, params, returns, `@intCast`/`@as`, array sizes, enum backings), preserving the existing diagnostic codes/messages.
- [ ] Fixtures: in-range accepts, out-of-range rejects per target (incl. the `@intCast(u64, 0 - 1)`-class), Zig-oracle-checked; gate battery + seed + docs + commit.

### Task 5 (F): Re-point the fold consumers + retire the divergence

- [ ] Migrate `evalConstU32Full`/`evalConstI64Full`/`comptimeValFitsType` and the array-size/enum paths to the new representation; remove the now-dead 64-bit special cases and the documented divergence.
- [ ] Update `docs/reference/Language_Spec_Z98.md` §7.2 (divergence note replaced by the exact semantics), tech docs 03/04, QUICK_REF, EXPECTED_FAIL; gate battery + seed + commit.

### Task 6 (F): Closeout of the comptime-int core (Part I)

- [ ] Whole-set review: spec §3/§4/§5 coverage, oracle parity on the frozen Task 0 table, all gates; update the spec status to implemented, note any residual (float comparisons, the cap).
- [ ] Final commit + report (the plan is then COMPLETE), and record the retired divergence in the ledger.

---

# Part II — folded trailing issues

**Context (operator ruling 2026-09-23):** the trailing compiler divergences discovered while building the Volume I manual are folded into THIS plan so it is dedicated to the trailing-issue clean-up. Each task follows the same discipline as Part I (Zig 0.15.2 oracle; `timeout 120` everywhere; fixture(s) + standalone repro; the full QUICK_REF gate battery; seed rotation iff the fixed point moves; tech docs per AGENTS §1.1.1; QUICK_REF + EXPECTED_FAIL updates; commit; STOP and report on unexpected movement).

### Task 7 (F): `@intCast` on a loop capture emits invalid C

**Defect (pre-existing; found by the Task 10C review):** `@intCast(<for-range capture>)` inside the capture's own loop emits invalid C with no diagnostic (`emit rc=0`; gcc `'zT_6' undeclared`), with or without a rename involved. Zig 0.15.2 accepts the shape.
- [ ] Investigate the exact mechanism (the capture temp's declared type/width vs the `@intCast` target; how the emitted temp reference is formed), then fix it minimally.
- [ ] Fixture (`repro/mi_matrix/`) + standalone repro; Zig-oracle cross-check; controls (a non-capture `@intCast`, a copied variable).
- [ ] Gate battery + seed rotation + docs + commit — `fix(lower): lower @intCast on a loop capture correctly`.

### Task 8 (F): the void/value-`if` statement residuals

**Defects (pre-existing; carried from Task 9D):** (i) `_ = foo();` (discarding a void call) ICEs with `error[3043] invalid temp index 0`; (ii) `return if (c) foo();` (a void `if` returned) is front-end-accepted but emits gcc-invalid C. Zig 0.15.2 accepts both.
- [ ] Investigate and fix both (the `hoisted_temps[TEMP_NONE]` paths), minimally.
- [ ] Fixtures + standalone repros; Zig-oracle cross-check; controls (a void call statement, a non-void value discard).
- [ ] Gate battery + seed rotation + docs + commit — `fix(lower): handle void temporaries in discard and return`.

### Task 9 (F): comptime float comparisons

**Defect (bounded divergence):** comptime float comparisons never fold, so a comptime-true float condition is rejected (`error[3059]`). Zig 0.15.2 folds them.
- [ ] Investigate the float fold path (the private float sub-evaluator + the comparison arms) and add the float comparison folds at the existing precision.
- [ ] Fixtures + standalone repro; Zig-oracle cross-check; controls (integer comparisons unchanged; float `{}` formatting residuals stay OUT of scope).
- [ ] If IEEE-exact parity proves out of reach, **STOP** and present the bounded divergence for a ruling instead of guessing.
- [ ] Gate battery + seed rotation + docs + commit.

### Task 10 (F): capture/lifetime bookkeeping hygiene

**Residual (from the Task 10C investigation):** `capture_shadow.count` is never meaningfully used (the 8 `capture_shadow.count = 0` sites are dead writes because the table's `Get` ignores `count`), `local_decl_count` is never reset per function, and `maybeDisambiguateCapture` over-renames when no earlier same-named local exists.
- [ ] Decide the minimal correct bookkeeping (make the count effective, or delete the field/writes; reset the per-function counters in the function-lowering init), with no behavior change for valid programs.
- [ ] Regression coverage: the Task 10D fixture + a cross-function name-reuse probe; gate battery + seed rotation + docs + commit.

### Task 11 (F): the index-capture parser gap

**Gap:** `for (arr, start..)` / `for (arr, start..end)` (Zig's explicit-start index form) is rejected by the Z98 parser (`error[2000]` at the `,`; `lower.zig`'s `range_inclusive` branch is dead). Z98 does support `for (arr) |x, i|` over arrays.
- [ ] Investigate and implement the Zig form (parser + sema + lowering) — the goal is Zig parity.
- [ ] Fixtures + standalone repro; Zig-oracle cross-check; controls (the existing `for (arr) |x, i|` and a `for (0..n) |i|` range).
- [ ] Gate battery + seed rotation + docs + commit.

### Task 12 (F): seed-tooling fallback

- [ ] Fix `scripts/seed/build_from_seed.sh --reconstruct-only` so its fallback reproduces the archived fixed point (compile the runtime TUs under the canonical flags instead of leaving them on the link line), or correct the comment/behavior so it is not misleading.

### Task 13 (F): reject method-call syntax and unknown struct members (S1)

**Defect (found while writing chapter 10; a spec-forbidden construct silently accepted):** `nine.square()` (a member call on a struct value) compiles rc=0, emits `zT_3 = zT_2();` with `zT_2` undeclared → gcc failure, no diagnostic. The Z98 spec forbids the construct: `docs/reference/Language_Spec_Z98.md:367` — "**No Method Syntax**: `struct.func()` is not supported; use `func(struct)`" (also `docs/sf/AGENTS.md:91`); method-syntax desugaring is listed only as a **future extension** (`docs/sf/Design_p2.md:18`, `:1943` §14.3; `AST_PARSER_p2.md:885`; `AST_LIR_Lowering_p2.md:612`). Z98 structs cannot contain function decls, so the shape is always invalid Z98 (official Zig rejects this exact program: `no field or member function named 'square'`).
- [ ] Add a **new dedicated diagnostic** (operator ruling: a fresh code, e.g. `ERR_3060_METHOD_SYNTAX_NOT_SUPPORTED`) and clean-reject the member-call shape (and unknown struct member access) with rc=2 and 0 `.c`, matching the spec; keep valid free-function calls and real struct-field access unchanged.
- [ ] Fixtures (`repro/mi_matrix/*_reject_xmod` + `expected.rc`) + a standalone repro; controls (a free-function call, a real field access); Zig 0.15.2 oracle cross-check.
- [ ] Gate battery + seed rotation + docs + commit — `fix(sema): reject method-call syntax on a struct value`.

### Task 14 (F): enforce call arity + argument types (S2)

**Defect (found while writing chapter 10; severity High — silent miscompile):** `add(2)` / `add(1, 2, 3)` (wrong arity) compile rc=0 and fail only at gcc (`too few`/`too many arguments`); `add(1, true)` (wrong argument type) builds+links+runs and prints `2` — a silent `bool`→`int` coercion. Zig 0.15.2 rejects all three (`expected 2 argument(s), found 1/3`; `expected type 'i32', found 'bool'`).
- [ ] Enforce arity and per-argument assignability at the call site (reuse the existing assignability/coercion machinery and its diagnostic codes where they fit; match Zig's rejection), leaving the valid call forms unchanged.
- [ ] Fixtures + standalone repros; Zig-oracle cross-check; controls (exact-arity correct-type calls, `@intCast`-based conversions).
- [ ] Gate battery + seed rotation + docs + commit.

### Task 15 (F): enforce `pub` visibility across modules (S3)

**Defect (found while writing chapter 10):** a non-`pub` function is callable from an importing module (`helper.secret(21)` rc=0, builds, runs, prints `21`); `ERR_3007_VISIBILITY_VIOLATION` is declared (`sf/src/diagnostics.zig:37`) but never emitted. Zig 0.15.2 rejects (`'secret' is not marked 'pub'`).
- [ ] Emit `ERR_3007_VISIBILITY_VIOLATION` for a cross-module reference to a non-`pub` declaration (functions first; then any other flat/nested module-member shape the investigation finds asymmetric — the known asymmetry: the flat module-member value arm is pub-gated at `semantic_analyzer.zig:672` while the nested-module branch has no check); same-module access stays unchanged.
- [ ] Fixtures + standalone repros; Zig-oracle cross-check; controls (a `pub` fn across modules; a non-pub fn used within its own module).
- [ ] Gate battery + seed rotation + docs + commit.

### Task 17 (F): reject a comptime-known out-of-bounds index at compile time

**Defect (found while writing chapter 12; a Zig divergence):** a **comptime-known** out-of-bounds array index (`scores[5]` on a `[5]i32`, `scores[scores.len]`) is not rejected at compile time. Z98 emits rc=0 and defers to the runtime check: under `-fsafe` (the default) it traps (rc 133 — verified live) but under `-ffast` it silently reads the wrong value (verified: `scores[5]` prints `90`). Zig 0.15.2 rejects at compile time (`error: index 5 outside array of length 5`). The `-fsafe` runtime check itself is correct and must stay.
- [ ] Investigate whether the index is already a folded comptime value at the indexing sites (semantic analysis / lowering), then add a compile-time bounds check for a comptime-known index on a fixed-size array (and the constant-slice-range analogue), matching Zig's rejection; keep the runtime-index `-fsafe` trap unchanged.
- [ ] Fixtures + standalone repro; Zig-oracle cross-check; controls (an in-range comptime index; a runtime index that still traps under `-fsafe` and reads garbage under `-ffast` as before).
- [ ] Gate battery + seed rotation + docs + commit — `fix(sema): reject a comptime-known out-of-bounds index`.

### Task 18 (F): related-span diagnostics + non-ASCII message audit

**Defects (found while writing chapter 13):** (i) no diagnostic emits related spans — `diagnosticCollectorAddRelatedSpan` (`sf/src/diagnostics.zig:404`) has **zero call sites** in `sf/`, so a diagnostic can never point at the earlier declaration the way Zig's `note:` does; (ii) several `error[3000]`-class "type mismatch" messages embed a raw UTF-8 **em dash** (`sf/src/semantic_analyzer.zig:1723/1803/1877/2371/3725`), which an ASCII/ISO-8859-1 manual page cannot quote byte-exactly (chapter 13 had to substitute `error[3057]` for this reason).
- [ ] Emit related spans for at least the shadow/redeclaration diagnostics (`error[3057]` pointing at the previous declaration) and any other site where Zig emits a note; verify the collector renders them in the emitted diagnostic.
- [ ] Replace the non-ASCII bytes in diagnostic message strings with ASCII (`-`/`--`) keeping the meaning; audit every diagnostic message string for non-ASCII bytes.
- [ ] Fixtures/repros + Zig-oracle cross-check; gate battery + seed rotation + docs + commit.

### Task 19 (F): whole-plan closeout

- [ ] Whole-plan closeout: update both specs' status, re-run the frozen-inventory/oracle parity check, run all gates, retire the divergence notes that Part I/II fixed, note any residual (the big-int cap, float-format limits), final commit + report — the plan is then COMPLETE.
