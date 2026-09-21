# Z98 Function-Local / Inline Type Emission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make function-local / inline named types (`const E = enum {…};` / `struct` / `union` / `error{…}` declared inside a function or as an inline type expression) emit valid C, or cleanly reject — never emit C that fails to compile.

**Architecture:** Five tasks. **B1 (I)** investigates the registration/emission path for function-local and inline named types and decides emit-properly vs clean-reject, covering `enum`, `struct`, `union`, and error-set declarations, and documents the divergence. **B2 (F)** implements the B1 design with fixtures, gates, and a seed rotation. **B3 (F)** resolves the Phase 0 deferred minors carried into this plan (operator ruling 2026-09-21). **B4 (I)** investigates the dynamic error-union `return x;` rewrap gap. **B5 (F)** implements the B4 fix with fixtures, gates, and a seed rotation.

**Tech Stack:** the self-hosted Z98 compiler (`sf/src`), the seed build model, `gcc -m32`, the `repro/mi_matrix` corpus.

**Spec:** `docs/superpowers/specs/2026-09-20-z98-manual-phase0-design.md` (AMENDMENT 17 records this plan's origin).

## Global Constraints

- Only the tasks in this plan may touch `sf/src`; each fix ships a `repro/mi_matrix/` fixture + standalone `repro/` + a `scripts/stdlib/expected_dirs.txt` pin + a seed rotation + tech-doc updates (AGENTS §1.1.1) + `EXPECTED_FAIL.md`/`QUICK_REF.md` updates.
- Run the QUICK_REF gate battery verbatim; **STOP and present on any unexpected gate movement**.
- Official Zig is the authority for validity; the C++ bootstrap is *not* authoritative.
- `edit`/`fastedit` only; no dead code; no duplicated logic.

---

### Task B1 (I): Investigate function-local / inline named-type emission

**Files:**
- Read (no edits): `sf/src/semantic_analyzer.zig`, `sf/src/symbol_registrator.zig`, `sf/src/type_registry.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`, `sf/src/main.zig`.
- Create: the findings report (SDD workspace; not committed).

**Context:** a function-local or inline named type emits invalid C. `fn f() void { const E = enum(u8){A=1,B}; var e: E = E.A; }` dumps rc=0 but gcc fails `unknown type name 'zT_…_type'`. Root: `semanticAnalyzerResolveExpr`'s `enum_decl`/`struct_decl`/`union_decl`/`error_set_decl` arm (`sf/src/semantic_analyzer.zig:2699-2702`) returns `TYPE_TYPE` without registering a named type, and `lower.zig:6585` lowers the initializer as a value local of `TYPE_TYPE`, which the emitter mangles. Module-level named types are registered by `symbol_registrator.zig` (only walks module `ast_root` children), so function-local decls never register. This reproduces on the base commit `f7f5df61` (pre-existing).

- [ ] **Step 1: Reproduce** for `enum`, `struct`, `union`, and error-set declarations in function-local and inline positions; capture the exact emitted-C failure for each.
- [ ] **Step 2: Locate the gaps** — where local named types are (or are not) registered and emitted, and why `TYPE_TYPE` leaks into lowering.
- [ ] **Step 3: Establish official-Zig validity** for each kind (function-local `const T = struct/enum/union/error{…}` and inline type expressions) and **document the divergence**: official Zig allows local types; the C++ bootstrap (`src/bootstrap/type_checker.cpp:3827`) rejects them.
- [ ] **Step 4: Decide and specify** — emit properly (register a synthesized name_id + payload + emit the typedef) vs clean-reject, per kind; the exact algorithm and edit sites; blast radius (fixed point/seed, gates, fixtures).
- [ ] **Step 5: Recommend the B2 verification plan** — fixtures (positive + any reject controls), gates, runtime guard.
- [ ] **Step 6: Report.** **No `sf/src` edits, no source commit.**

---

### Task B2 (F): Emit or cleanly reject function-local / inline named types

**Files (confirm against the B1 report):** `sf/src/semantic_analyzer.zig`, `sf/src/symbol_registrator.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`; `repro/mi_matrix/` fixtures; `repro/`; tech docs; seed rotation iff the fixed point moves.

- [ ] **Steps 1–7:** implement per B1; verify each kind emits valid C (or cleanly rejects); leave the reproductions; run the QUICK_REF gate battery verbatim (STOP on unexpected gate movement); rotate the seed iff the fixed point moves; update tech docs; commit `fix(types): support function-local named types` (or the B1-recommended message).

---

### Task B3 (F): Resolve the carried Phase 0 deferred minors

**Files:** `sf/src/comptime_eval.zig`, `sf/src/type_resolver.zig`, `sf/src/semantic_analyzer.zig`; `repro/mi_matrix/`; `scripts/seed/archive_seed.sh`; `repro/mi_matrix/EXPECTED_FAIL.md`; docs.

**Context:** the Phase 0 program (`docs/superpowers/plans/2026-09-20-z98-manual-phase0-plan.md`) closed with these deferred minors; the operator (2026-09-21) carried them into this plan so they are not lost. Each item is independent; fix, verify, and commit per the global constraints.

- [ ] **Item 1 — restore `@intCast` runtime trap coverage.** The `safe_intcast_widen_sign_xmod` option-A re-pin dropped the runtime widening-sign-change trap coverage; add a runtime fixture that exercises the `-fsafe` `@intCast` trap for a widening sign change (and its `-ffast` non-trapping counterpart), with a `repro/mi_matrix/` fixture + `expected_dirs.txt` pin.
- [ ] **Item 2 — range-check 64-bit-target casts.** `@intCast(u64,-1)` / `@as(u64,-1)` still fold (`comptime_eval.zig` ~`:159`; `type_resolver.zig` ~`:1123` skip `wb >= 64`). Add the range check so an out-of-range cast to a 64-bit target rejects (invalid-Zig diagnostic-quality gap).
- [ ] **Item 3 — generalize the `@as` diagnostic wording.** `comptime_eval.zig` ~`:314` prints "@intCast value does not fit the target type" for `@as`; make the message correct for both builtins.
- [ ] **Item 4 — give the comptime-cast reject a real location.** The `comptime_eval` `@intCast`/`@as` reject uses `source_file_id = 0` (no file:line); provide a real location if feasible without a structural change (else document why not).
- [ ] **Item 5 — fix the seed `SEED_README.txt` count.** `scripts/seed/archive_seed.sh` (~`:160`) writes "20 std .zig" while `lib/` holds 29; correct the generator so the next rotation is accurate.
- [ ] **Item 6 — fix the Task 10D call-site comment.** `sf/src/semantic_analyzer.zig:3390-3392` inaccurately describes nested-defer handling; correct the comment.
- [ ] **Item 7 — reconcile the EXPECTED_FAIL narration.** The Task 11U section narrates "202 → 203 → 204" while the single pin bump is 202 → 204; make it consistent.
- [ ] **Steps 1–7 (per item):** implement, verify against source/official Zig, leave reproductions where applicable, run the QUICK_REF gate battery verbatim (STOP on unexpected gate movement), rotate the seed iff the fixed point moves, update tech docs per AGENTS §1.1.1, commit each item (or one combined commit with a clear message).

---

### Task B4 (I): Investigate the dynamic error-union rewrap

**Files:**
- Read (no edits): `sf/src/lower.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/coercion.zig`, `sf/src/type_registry.zig`.
- Create: the findings report (SDD workspace; not committed).

**Context:** Task 10F's dynamic errdefer path in `sf/src/lower.zig` lowers `return x;` (where `x` is an error-union expression for which no static coercion was recorded) as `check_error` + `branch` + `ret val`, where `val` is the *source* error union. It skips the rewrap the `try` path performs. That is correct when the source and destination error unions share an error set and payload (the C typedef is payload-keyed and error codes are globally dense), but for a legal error-union *narrowing* — `fn f() E2!U { const x: E1!T = …; return x; }` with `E2 ⊆ E1` and `T` coercible to `U` — the error tag must be remapped and the payload coerced. The Phase 0 program recorded this as an accepted residual; the operator (2026-09-21) directs it be addressed here.

- [ ] **Step 1: Reproduce** — construct a legal Z98 program that `return x;`-narrows an error-union variable/call whose error set and/or payload differ from the function's return type; capture the wrong emitted C and/or runtime behavior (with a runtime `@panic` guard).
- [ ] **Step 2: Establish official-Zig validity** — confirm the narrowing is legal Zig (`E1!T` → `E2!U` with `E2 ⊆ E1`, `T` coercible to `U`) and what the correct semantics are.
- [ ] **Step 3: Locate the gap** — how the `try` path rewraps vs the dynamic-`return` path; the exact edit site; whether the same-set/same-payload cases are already correct and must stay unchanged.
- [ ] **Step 4: Decide and specify** — the minimal fix (rewrap on the dynamic error arm only) and the blast radius (fixed point/seed, gates, fixtures).
- [ ] **Step 5: Recommend the B5 verification plan** — fixtures (positive + same-type control), gates, runtime guard.
- [ ] **Step 6: Report.** **No `sf/src` edits, no source commit.**

---

### Task B5 (F): Rewrap a dynamic error-union return

**Files (confirm against the B4 report):** `sf/src/lower.zig`; `repro/mi_matrix/` fixtures; `repro/`; tech docs; seed rotation iff the fixed point moves.

- [ ] **Steps 1–7:** implement per B4; verify the narrowing emits the correct rewrap and that same-type returns stay byte-identical; leave the reproductions; run the QUICK_REF gate battery verbatim (STOP on unexpected gate movement); rotate the seed iff the fixed point moves; update tech docs per AGENTS §1.1.1; commit `fix(lower): rewrap a dynamic error-union return`.

---

**Accepted residuals (documented, NO action):** the `?bool` = 8 / `E!bool` 4-byte floors. Do not change these.

---

