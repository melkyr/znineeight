# Z98 `zig1` technical-documentation refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring all 14 `sf/docs/tech_docs/*.md` documents and `INDEX.md` back into agreement with the current `zig1` source, and remove the volatile line references and dated evidence appendices that make them rot.

**Architecture:** One plan, sixteen tasks, docs-only. Tasks 1-14 each audit and correct one tech doc in pipeline order. Task 15 regenerates `INDEX.md` against the corrected docs and current source. Task 16 is the whole-set consistency review and closeout. No `sf/src`, script, fixture, or seed change; the compiler fixed point and seed are untouched.

**Tech Stack:** Markdown, the Z98 compiler sources under `sf/src/`, git.

**Spec:** `docs/superpowers/specs/2026-09-20-tech-docs-refresh-design.md`.

**Sequence:** PREVIOUS plan: none (a new documentation program). NEXT plan: none — final plan.

## Global Constraints

- **Docs only.** Do NOT edit `sf/src/**`, `scripts/**`, `sf/docs/std_lib/**`, `docs/sf/**`, fixtures, or `release/seed/**`. The compiler fixed point and seed are untouched.
- **Surgical audit + correct.** Preserve each doc's structure and still-accurate prose. Correct deleted/renamed/changed/missing content; do not rewrite the document.
- **No line references.** Remove every `file.zig:NNN` / `file.c:NNN` reference and every per-function `Line` column. Refer to symbols by name and file (spec §3).
- **No dated evidence appendices.** Remove "Evidence" / "Deep-Dive Evidence" trace sections captured against the 4 examples; keep the reference content beside them (spec §4).
- **Fold features into existing docs.** No new tech docs (spec §5). Cross-phase behavior lives in the doc that owns the code; others cross-reference it.
- **Coverage map is binding.** Each doc covers exactly the files listed for it in spec §6. `std_*.zig`, `test_*.zig`, and `sf/src/tests/` are out of scope.
- **Accuracy over volume.** Every type, function, error member, marker, and count must match current source. Read the source; never invent an API.
- **Header marker.** Collapse the header changelog blob to `[updated: 2026-09-20 — <one-line reason>]` (spec §7).
- **Edits only via `edit`/`fastedit`** (re-read the region immediately before each `fastedit`; edit bottom-to-top for multiple edits in one file). Never stage `mnemoria/` or `.zig1_*.tmp`.
- **STOP on a source defect:** if the audit finds a doc/source contradiction that is a real compiler bug, STOP and report it — do not fix `sf/src`, do not document around it.

---

## File Structure

**Modify (14 docs):**
- `sf/docs/tech_docs/00_shared_infra.md`
- `sf/docs/tech_docs/00_lexer_parser.md`
- `sf/docs/tech_docs/01_import_resolution.md`
- `sf/docs/tech_docs/02_symbol_registration.md`
- `sf/docs/tech_docs/03_type_resolution.md`
- `sf/docs/tech_docs/04_comptime_eval.md`
- `sf/docs/tech_docs/05_semantic_analysis.md`
- `sf/docs/tech_docs/06_static_analyzers.md`
- `sf/docs/tech_docs/07_lir_lowering.md`
- `sf/docs/tech_docs/08_c89_emission.md`
- `sf/docs/tech_docs/09_pipeline_orchestration.md`
- `sf/docs/tech_docs/10_c_runtime.md`
- `sf/docs/tech_docs/11_build_system.md`
- `sf/docs/tech_docs/12_async_coroutines.md`

**Regenerate (1):** `sf/docs/tech_docs/INDEX.md`.

**Reference (read-only):** the `sf/src` files in spec §6, `docs/superpowers/plans/*` and `docs/superpowers/specs/*` dated after each doc, `docs/sf/QUICK_REF.md`.

---

### Task 1: `00_shared_infra.md`

**Files:**
- Modify: `sf/docs/tech_docs/00_shared_infra.md`

**Covers (spec §6):** `allocator.zig`, `string_interner.zig`, `source_manager.zig`, `diagnostics.zig`, `pal.zig`, `growable_array.zig`, `panic.zig`, `config.zig`, `util/`.

**Feature focus:** the memory refactor (arena tiers, `TrackingAllocator`/`Sand`, offset-addressed spill backends); `config.zig` as the single `host_is_windows` flip point; `panic.zig` (`panicHandler`); clean-diagnostics changes; `source_manager` source-text release + fault-in; `util/` (`hash`, `itoa`, `format`, `path`, `mem`).

- [ ] **Step 1: Read** the doc and every covered source file; enumerate current public types/functions/constants/markers.
- [ ] **Step 2: Audit + correct** — remove deleted symbols, fix renamed ones, add `panic.zig`/`config.zig` coverage and any new allocator/source-manager/diagnostics surface; update the Summary Table and counts; remove all line refs; drop dated evidence sections; audit Known Issues.
- [ ] **Step 3: Update the header marker** (spec §7).
- [ ] **Step 4: Self-review** every changed claim against source; commit (`docs(tech): refresh 00_shared_infra against current source`).

---

### Task 2: `00_lexer_parser.md`

**Files:**
- Modify: `sf/docs/tech_docs/00_lexer_parser.md`

**Covers (spec §6):** `token.zig`, `lexer.zig`, `parser.zig`, `ast.zig`, `print_decomposition.zig`, `dump_ast.zig`, `dump_tokens.zig`, `ast_dump_main.zig`.

**Feature focus:** current `AstKind` variant set (spec §5); parser additions for packed struct/union, `volatile`, `extern` calling convention, arbitrary-width int/`enum(uN)` backing, type aliases, switch-range, labeled break, string-literal typing; lexer f64-exponent/64-bit-decimal handling; `ast.zig` write-through `extra_children` spill; `print_decomposition.zig`; the dump tooling.

- [ ] **Step 1: Read** the doc and every covered source file.
- [ ] **Step 2: Audit + correct** — `AstKind`/`TokenKind` counts and tables, parser grammar coverage for the feature waves, `ast.zig` store layout, tooling files; remove line refs; drop evidence; audit Known Issues.
- [ ] **Step 3: Update the header marker.**
- [ ] **Step 4: Self-review** against source; commit (`docs(tech): refresh 00_lexer_parser against current source`).

---

### Task 3: `01_import_resolution.md`

**Files:**
- Modify: `sf/docs/tech_docs/01_import_resolution.md`

**Covers (spec §6):** `import_resolver.zig`, `module_registry.zig`.

**Feature focus:** module pruning (needed-only std), path normalization, resolve-time content-hash guard, search-dir resolution, module ordering.

- [ ] **Step 1: Read** the doc and both source files.
- [ ] **Step 2: Audit + correct** — resolver/registry API and data-flow, pruning behavior, ordering guarantees; remove line refs; drop evidence; audit Known Issues.
- [ ] **Step 3: Update the header marker.**
- [ ] **Step 4: Self-review** against source; commit (`docs(tech): refresh 01_import_resolution against current source`).

---

### Task 4: `02_symbol_registration.md`

**Files:**
- Modify: `sf/docs/tech_docs/02_symbol_registration.md`

**Covers (spec §6):** `symbol_registrator.zig`, `symbol_table.zig`.

**Feature focus:** current decl-kind registration set (incl. new kinds introduced by packed/volatile/arbitrary-width/calling-convention), the double-registration pass, type-stub population, interaction with the new `phase_FrontResolution`.

- [ ] **Step 1: Read** the doc and both source files.
- [ ] **Step 2: Audit + correct** — `SymbolKind`/`Symbol` tables, registration walkthrough, stub population, data flow; remove line refs; **drop the dated "Evidence: 4 Working Examples" appendix** (spec §4); audit Known Issues.
- [ ] **Step 3: Update the header marker.**
- [ ] **Step 4: Self-review** against source; commit (`docs(tech): refresh 02_symbol_registration against current source`).

---

### Task 5: `03_type_resolution.md`

**Files:**
- Modify: `sf/docs/tech_docs/03_type_resolution.md`

**Covers (spec §6):** `type_resolver.zig`, `type_registry.zig`, `const_alias_prepass.zig`, `front_resolution.zig`.

**Feature focus:** `front_resolution.zig` (the `phase_FrontResolution` front pass — module-init resolution + `resolveStmtTypes`); arbitrary-width int/`enum(uN)` type layer (`width_bits`/`is_signed`, backing widths); packed struct/union TypeKinds; `volatile`; calling-convention fn types; type aliases; `TYPE_VA_LIST` and the sentinel TypeId table.

- [ ] **Step 1: Read** the doc and every covered source file; verify the sentinel TypeId table and `TypeKind` variants against `type_registry.zig`.
- [ ] **Step 2: Audit + correct** — add `front_resolution.zig` coverage, the new type kinds/widths/qualifiers/conventions, alias forms; update the sentinel table and counts; remove line refs; drop evidence; audit Known Issues.
- [ ] **Step 3: Update the header marker.**
- [ ] **Step 4: Self-review** against source; commit (`docs(tech): refresh 03_type_resolution against current source`).

---

### Task 6: `04_comptime_eval.md`

**Files:**
- Modify: `sf/docs/tech_docs/04_comptime_eval.md`

**Covers (spec §6):** `comptime_eval.zig`.

**Feature focus:** current foldable-builtin set (`@isWindows`, `@sizeOf`/`@alignOf`, arbitrary-width/enum-backing folds); const-cycle depth cap + located `error[3050]`; ident-chain folding.

- [ ] **Step 1: Read** the doc and the source file.
- [ ] **Step 2: Audit + correct** — builtin table, fold rules, cycle guard, diagnostics; remove line refs; drop evidence; audit Known Issues.
- [ ] **Step 3: Update the header marker.**
- [ ] **Step 4: Self-review** against source; commit (`docs(tech): refresh 04_comptime_eval against current source`).

---

### Task 7: `05_semantic_analysis.md`

**Files:**
- Modify: `sf/docs/tech_docs/05_semantic_analysis.md`

**Covers (spec §6):** `semantic_analyzer.zig`, `coercion.zig`, `resolved_type_table.zig`, `constraint_checker.zig`, `assign_helper.zig`.

**Feature focus:** the socket builtins were REMOVED (networking is now the `std_net` extern surface); the async builtins (`@asyncInit`/`@asyncResume`/`@asyncSuspend`/`@asyncFrameSize`); introspection/pointer/bitcast builtins; switch-range; string-literal typing; enum→int promotion; packed/`volatile`/arbitrary-width checks; c89-ahead hard errors; clean diagnostics; `assign_helper.zig`.

- [ ] **Step 1: Read** the doc and every covered source file.
- [ ] **Step 2: Audit + correct** — the builtin dispatch table and removed socket arms, the new builtin families, coercion/constraint rules, error codes; remove line refs; drop evidence; audit Known Issues.
- [ ] **Step 3: Update the header marker.**
- [ ] **Step 4: Self-review** against source; commit (`docs(tech): refresh 05_semantic_analysis against current source`).

---

### Task 8: `06_static_analyzers.md`

**Files:**
- Modify: `sf/docs/tech_docs/06_static_analyzers.md`

**Covers (spec §6):** `analyzer.zig`, `state_map.zig`.

**Feature focus:** current analyzer passes and `StateMap` fork/merge semantics; any behavior changed by the later feature waves.

- [ ] **Step 1: Read** the doc and both source files.
- [ ] **Step 2: Audit + correct** — analyzer/`StateMap` API and merge semantics, `PtrState`/`Provenance`/`AllocState`; remove line refs; **drop the dated "Deep-Dive Evidence (P6)" appendix** (spec §4); audit Known Issues.
- [ ] **Step 3: Update the header marker.**
- [ ] **Step 4: Self-review** against source; commit (`docs(tech): refresh 06_static_analyzers against current source`).

---

### Task 9: `07_lir_lowering.md`

**Files:**
- Modify: `sf/docs/tech_docs/07_lir_lowering.md`

**Covers (spec §6):** `lower.zig`, `lir.zig`, `lir_opt_pass.zig`, `lir_stream.zig`, `spill_store.zig`.

**Feature focus:** `lir_opt_pass.zig` (copy propagation, local const-fold, expression nesting), `lir_stream.zig` + `spill_store.zig` (offset-addressed spill, Ram/Disk backends); packed `load_bitfield`/`store_bitfield`; arbitrary-width int ops; `volatile`; calling convention; c89-ahead lowering (checked cast/div/shift/bounds/null, undefined poison); async lowering; the current `LirInst` variant set.

- [ ] **Step 1: Read** the doc and every covered source file; count `LirInst` variants.
- [ ] **Step 2: Audit + correct** — add `lir_opt_pass`/`lir_stream`/`spill_store` coverage, the new instruction families and lowering arms, frame/layout notes; update the `LirInst` count; remove line refs; drop evidence; audit Known Issues.
- [ ] **Step 3: Update the header marker.**
- [ ] **Step 4: Self-review** against source; commit (`docs(tech): refresh 07_lir_lowering against current source`).

---

### Task 10: `08_c89_emission.md`

**Files:**
- Modify: `sf/docs/tech_docs/08_c89_emission.md`

**Covers (spec §6):** `c89_emit.zig`, `name_mangler.zig`, `cinclude.zig`, `emit_support.zig`.

**Feature focus:** `emit_support.zig` (self-contained output dir, emitted runtime/platform support, `net_prelude.h` gating); companion build scripts (sh/bat/owc); packed/int-width/`volatile`/calling-convention emission; c89-ahead guard emission; emission-core compaction; self-contained f64 formatting; module pruning in emission.

- [ ] **Step 1: Read** the doc and every covered source file.
- [ ] **Step 2: Audit + correct** — add `emit_support.zig` coverage and the self-contained-output behavior, the new emission paths and helpers, the removed socket-emission section; update counts; remove line refs; drop evidence; audit Known Issues.
- [ ] **Step 3: Update the header marker.**
- [ ] **Step 4: Self-review** against source; commit (`docs(tech): refresh 08_c89_emission against current source`).

---

### Task 11: `09_pipeline_orchestration.md`

**Files:**
- Modify: `sf/docs/tech_docs/09_pipeline_orchestration.md`

**Covers (spec §6):** `main.zig`, `main_dump.zig`, `main_exp.zig`, `strip_main.zig`.

**Feature focus:** the phase sequence now includes `phase_FrontResolution` and `phase_AsyncFrameSize`; current CLI flags (`-fsafe`/`-ffast`, `-o` C89 default, `--dump-c89` alias, `--output-dir`, markers/memory flags); self-contained output-dir orchestration; the tooling mains.

- [ ] **Step 1: Read** the doc and every covered source file; list the phase functions and CLI flags from source.
- [ ] **Step 2: Audit + correct** — the phase list/sequence, checkpoint markers, CLI table, output-dir flow, tooling mains; remove line refs; drop evidence; audit Known Issues.
- [ ] **Step 3: Update the header marker.**
- [ ] **Step 4: Self-review** against source; commit (`docs(tech): refresh 09_pipeline_orchestration against current source`).

---

### Task 12: `10_c_runtime.md`

**Files:**
- Modify: `sf/docs/tech_docs/10_c_runtime.md`

**Covers (spec §6):** `sf/src/include/*`, `extern_c.zig`, `extern_c_z98.zig`.

**Feature focus:** current `zig_runtime.c`/`.h`, `zig_pal.c`, `net_prelude.h`, `zig_compat.h`, `c_exit.c`; the checked-cast helpers, trap, and print helpers; the `extern_c*.zig` declarations; the std_net extern target.

- [ ] **Step 1: Read** the doc and every file under `sf/src/include/` plus the two `extern_c*.zig` files.
- [ ] **Step 2: Audit + correct** — the runtime function inventory and semantics, the emitted-support relationship to `emit_support.zig`, the extern declarations; remove line refs; drop evidence; audit Known Issues.
- [ ] **Step 3: Update the header marker.**
- [ ] **Step 4: Self-review** against source; commit (`docs(tech): refresh 10_c_runtime against current source`).

---

### Task 13: `11_build_system.md`

**Files:**
- Modify: `sf/docs/tech_docs/11_build_system.md`

**Covers (spec §6):** `sf/scripts/*`, `scripts/seed/*`, `release/seed/*`.

**Feature focus:** the seed bootstrap model (`release/seed/zig1-seed.tgz`, `scripts/seed/build_from_seed.sh`, archive rotation), the binding gcc flag set, and the emitted companion build scripts (sh/bat/owc).

- [ ] **Step 1: Read** the doc and the build/seed scripts.
- [ ] **Step 2: Audit + correct** — the build paths, seed model, flag sets, companion-script behavior; remove line refs; drop evidence; audit Known Issues.
- [ ] **Step 3: Update the header marker.**
- [ ] **Step 4: Self-review** against source; commit (`docs(tech): refresh 11_build_system against current source`).

---

### Task 14: `12_async_coroutines.md`

**Files:**
- Modify: `sf/docs/tech_docs/12_async_coroutines.md`

**Covers (spec §6):** `async_analysis.zig`, `async_frame_layout.zig`, `async_state_machine.zig`, `std_async.zig`.

**Feature focus:** this doc is recent (2026-09-20) but still carries line references; confirm the analysis/frame-layout/state-machine/`std.async` surface is current, including `suspendUntil`, `waitFor`, and the frame/pool ABI.

- [ ] **Step 1: Read** the doc and every covered source file.
- [ ] **Step 2: Audit + correct** — remove all line refs; confirm the API/marker/ABI tables; drop any dated evidence; audit Known Issues.
- [ ] **Step 3: Update the header marker.**
- [ ] **Step 4: Self-review** against source; commit (`docs(tech): refresh 12_async_coroutines against current source`).

---

### Task 15: `INDEX.md`

**Files:**
- Modify: `sf/docs/tech_docs/INDEX.md`

**Interfaces:**
- Consumes: the corrected docs from Tasks 1-14.

**Feature focus:** regenerate the master index against current source (spec §8).

- [ ] **Step 1: Read** `INDEX.md`, then the corrected docs and their covered sources.
- [ ] **Step 2: Regenerate §A** phase flow — add `phase_FrontResolution` and `phase_AsyncFrameSize`, correct the phase table (functions, files, markers, arena tiers).
- [ ] **Step 3: Regenerate §B** function → file locator with **no line numbers**; §C markers; §D sentinel TypeId table; §E data structures; §F AstKind → phases; §G arena tiers — each verified against source.
- [ ] **Step 4: Regenerate the coverage table** from spec §6, with refreshed `AstKind`/`LirInst`/`TypeKind` counts and the new/renamed files.
- [ ] **Step 5: Self-review** every table against source; commit (`docs(tech): regenerate the pipeline master index`).

---

### Task 16: Whole-set consistency review + closeout

**Files:**
- Review: all `sf/docs/tech_docs/*.md`.

- [ ] **Step 1: Review the set** for cross-doc consistency (shared facts stated once, not contradicted), complete coverage-map assignment (every non-std `sf/src` file in exactly one doc), zero remaining line references, zero remaining dated evidence appendices, and uniform header markers.
- [ ] **Step 2: Fix** any inconsistency found (docs only).
- [ ] **Step 3: Commit** (`docs(tech): tech-docs refresh closeout — whole-set review`).

---

## Self-Review

- **Spec coverage:** §2 method → every task's audit steps; §3 line refs → Global Constraints + every task; §4 evidence → Tasks 1-14; §5 feature waves → the per-task Feature focus; §6 coverage map → the per-task Covers + Task 15 Step 4; §7 header → every task; §8 INDEX → Task 15; §9 conventions → Global Constraints; §10 plan index → the `Sequence:` line.
- **Placeholder scan:** every task names concrete files, source coverage, and the observable result; the feature lists name real landed subsystems.
- **Type consistency:** the 14 doc filenames and their coverage match spec §6 exactly; the task order matches the doc numbering plus the `INDEX.md` final task.
