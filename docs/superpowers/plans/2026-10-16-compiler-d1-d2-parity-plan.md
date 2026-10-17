# z98 compiler — D1/D2 parity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix compiler defects **D1** (optional/error-union-of-aggregate fn-pointer return) and **D2** (wrong-platform module emitted from a comptime-dead `@isWindows()` arm) at root cause; canonicalize the synthetic-composite type family; add **conditional `@import`**; adapt and truth-up the **static analyzers**.

**Spec:** `docs/superpowers/specs/2026-10-16-compiler-d1-d2-parity-design.md` (binding).

**Sequencing (MANDATORY):** this is a **middle milestone** that runs **before** z9play M6. **z9play M6 (`docs/superpowers/plans/2026-10-11-z9play-m6-win9x-plan.md`, already amended) is blocked on this plan and is the NEXT thing to do after Task 7 below.** Nothing in z9play changes during this milestone (the `Key.none` workaround stays; M6 resumes on the clean shape once T7 confirms it).

**Where the defects live:** `examples/torrent_example_defects.md` (D1/D2 entries, with minimal reproducers).

## Global Constraints

- **Plan is the only authority** (STOP-present, format `I found the intention is X, but this is impossible given Y`); if a better X/Y arises or anything is confusing/unforeseen → STOP and present; no corner cuts; no unrelated fixes.
- **`sf/src` changes ARE in scope** (this is a compiler milestone — unlike the example-only z9play milestones). Touch only what each task names; tech docs for changed subsystems.
- `edit`/`fastedit` only (AGENTS.md X.7: read the region before each edit, bottom-to-top; INSERT = replace anchor with new+original; X.3: no scripted/bulk source transforms).
- SDD subagent execution (implementer + task review per task; fix rounds resume via task_id; scoped re-reviews). Memory via `mnemoria --path .opencode/memory add --agent Zni-005 --type … --summary …`.
- GIT hard rule: no push / reset / checkout / restore / clean / stash-drop / force-push / history-rewrite. Untracked `run.err` + dirty `progress.md` deltas left alone. Commits `refactor(<file>): …` / `fix(<file>): …` (src + tech docs) + `docs(sdd): <task> report` (git add -f explicit paths); controller commits ledger lines as `docs(sdd): … ledger`.
- **Battery gates (spec §6):** corpus class-file byte-identical (frozen md5 `518eca1a9b5d3e1cc5a48abce214abd8`, `1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH`, 0 movers) + goldens 5/5 + mi_matrix 25+oob (`scripts/stdlib/run_fixtures.sh`) + examples 26/26 build + 26/26 run (CWD=example-dir) + `scripts/stdlib/verify_stdlib.sh` 285/0 + seed two-hop `hop1==hop2` (`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>` → `<out>/zig1_5_clean`) + 8 `--dump-c89` pins **recorded old→new (MAY move — operator-approved)** + markers telemetry. Reports under `.superpowers/sdd/2026-10-16-compiler-d1-d2-parity-plan/`.
- Build reference: seed **v98**, fixed point `f18b69ece1917bf970a036b276e5e403` (will move — recorded).

## File Structure (touch sets per task)

- `sf/src/type_registry.zig`, `sf/src/type_resolver.zig` — T1 (canonical composites + late layout).
- `sf/src/c89_emit.zig` (typedef ordering/emit dispatch) — T2.
- `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`, `sf/src/comptime_eval.zig` — T3 (comptime-if fold).
- `sf/src/parser.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/type_resolver.zig`, `sf/src/lower.zig`, `sf/src/module_registry.zig` — T4 (conditional `@import`).
- `sf/src/analyzer.zig` + `sf/src/tests/test_analyzer_bin.zig` — T5.
- `sf/docs/tech_docs/**` — T6; `examples/torrent_example_defects.md` (D1/D2 → FIXED) — T6.
- `repro/mi_matrix/**` — T0 fixtures.

---

### Task 0: Preflight + fixtures

- [ ] Freeze the battery baseline (spec §6 anchors). Land the defect reproducers as fixtures: `fnptr_opt_aggregate_*_xmod` (D1 coercion + D1 emit shapes), `iswindows_deadarm_*_xmod` (D2), `conditional_import_*_xmod` (§4) — red/expected-class recorded before any fix.
- [ ] Inventories: (i) every synthetic-composite GetOrCreate site (optional/error_union/array/tuple/slice/fn); (ii) every comptime-condition consumer (sema if-without-else allowance, lowering `if`, `and`/`or`, `while`); (iii) analyzer surface vs current language.
- [ ] **Scan the corpus for reject fixtures whose only error sits in a comptime-dead arm** (class-mover risk for T3) — STOP-present if any exist.

### Task 1: D1 identity — canonical synthetic composites

**Files:** `sf/src/type_registry.zig`, `sf/src/type_resolver.zig`.
- [ ] Unconditional key-cache in `typeRegistryGetOrCreateOptional` / `GetOrCreateErrorUnion` / `GetOrCreateArray` (+ tuple/slice audit) — model on `typeRegistryGetOrCreatePtr`. Ensure `layoutEnsure`/`typeResolverResolve` resolves late-created composites (on-demand `layoutEnsure` if created after the topological pass).
- [ ] Make `typeRegistryIsAssignable`'s `fn_type` comparison structural (return + params) as belt-and-braces.
- [ ] D1 coercion fixture green; battery green. Commit `fix(type_registry): D1 — canonical synthetic composite types`.

### Task 2: D1 emit — composite typedef ordering

**Files:** `sf/src/c89_emit.zig` (+ `sf/src/type_registry.zig` if the edge is the gap).
- [ ] Repro-driven: pin whether the failure is ordering (fn-return edge suppressed by `typeHasForwardDecl` in `typeRefEdgeTarget`) or a missing composite typedef (the per-kind emit dispatch at `c89_emit.zig:1440-1453` omits optional/error_union/slice).
- [ ] Fix so every composite typedef is emitted and ordered before every spelling reference (fn-ptr return/params, slice elem, etc.). D1 emit fixture green; battery green. Commit `fix(c89_emit): D2-class ordering for optional/error-union returns` (or `fix(type_registry)` if the edge lives there).

### Task 3: Comptime-if folding (D2 root) — Zig rule

**Files:** `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`, `sf/src/comptime_eval.zig`, `sf/src/main.zig` (module-closure half — Amendment 1).
- [ ] When an `if`/`else` condition is comptime-known (trigger set per spec §3), the untaken arm is **not analyzed and not lowered** (Zig semantics); the `if` takes the live arm's value/type. Runtime conditions untouched.
- [ ] D2 fixture green (wrong-platform module **not** emitted; both targets cross-build). Battery green (pins may move where dead code disappears). Commit `fix(semantic_analyzer): D2 — comptime-if eliminates the untaken arm`.

### Task 4: Conditional `@import` (Zig idiom)

**Files:** `sf/src/parser.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/type_resolver.zig`, `sf/src/lower.zig`, `sf/src/module_registry.zig`.
- [ ] `const impl = if (@isWindows()) @import("a.zig") else @import("b.zig");` (and the `switch` form) resolves to the live module; `import_expr` works in expression position. Fixtures green (cross-build both ways). Battery green. Commit `feat(semantic_analyzer): conditional @import (comptime module selection)`.

### Task 5: Static analyzers — adapt + truth-up

**Files:** `sf/src/analyzer.zig`, `sf/src/tests/test_analyzer_bin.zig`, `tests/analyzers/**`, docs `docs/design/static_analyzers.md`, `docs/sf/STATIC_ANALYZERS_p2.md`, `docs/tech_debt/static_analyzers.md`.
- [ ] SignatureAnalyzer accepts fn-ptr returns of `?Aggregate`/`E!Aggregate` (post-T1/T2) and covers the current surface (arbitrary-width ints, `.tag`, packed-union members); Lifetime/NullPointer/DoubleFree cover captures (tech-debt §2.1) and current surface. Analyzer tests green; docs truth-upped. Commit `fix(analyzer): D1/D2 surface + drift truth-up` (split docs commit if cleaner).

### Task 6: Docs + defect ledger

- [ ] Tech docs (`sf/docs/tech_docs/**`: type registry / semantic analysis / lowering / emission) for comptime-if folding, conditional `@import`, canonical composites. `examples/torrent_example_defects.md`: D1/D2 → **FIXED at root cause** (mechanism + fix commit; note the z9play `Key.none` workaround is retained per operator ruling). Commit `docs: D1/D2 fixed at root cause`.

### Task 7: Next-milestone review → z9play M6

- [ ] Re-read the amended `docs/superpowers/plans/2026-10-11-z9play-m6-win9x-plan.md` and judge it against the fixed compiler: two separate platform modules selected via `@isWindows()` cross-build clean on both targets; `readKey_fn` may return `?Key` (D1 fixed) though z9play keeps `Key.none`; conditional `@import` available if M6 prefers it. If an amendment is required, **STOP-present** it; else record "no amendment needed".

**Gate:** approved M6 amendment or justified "no amendment needed".

---

## After Task 7 (stated for the record)

**The next thing to do is z9play M6 — `docs/superpowers/plans/2026-10-11-z9play-m6-win9x-plan.md`** (Win9x `waveOut` audio + Win9x console backend + `@isWindows()` selection; workspace `.superpowers/sdd/2026-10-11-z9play-m6-win9x-plan/` already exists with Task 0 done). M6 has been waiting on this compiler milestone; resume it immediately after T7. Then M7 (TUI + `std.fs` directory iteration) and optional M8 (FLAC).

---

## Amendments

### Amendment 1 — T3 touch-set widen (operator ruling A, 2026-10-16)

T0 evidence (reviewer-verified) refuted the plan's assumed D2 channel: the lowering comptime fold already eliminates untaken arms; the wrong-platform module is pulled in by `sf/src/main.zig:1306+` module-reachability (all-fn scan of hoisted temps/return/params through `pruneTypeMarkByValue` `main.zig:1149-1199`, which marks the type OWNER's module reachable — never-called modules' fns pin their module). No edit in T3's original 3 files can stop that emission. **Ruling A:** T3's touch set += `sf/src/main.zig` (module-closure fix: scan only call-reachable fns, or add type-owner edges only from reachable fns) as ONE task together with the sema fold (untaken arm not analyzed) in the named 3 files. Deliverable unchanged: D2 fixtures green at root (wrong-platform module not emitted; both targets cross-build). Cost if wrong: main.zig edit where a pure-sema fix would have sufficed (impossible per evidence) or closure semantics change with wider blast radius than needed (mitigated by the battery's pins 0/8 requirement + frozen-corpus gate).

### Amendment 2 — T4 true Zig laziness + C2 clobber fix (operator, 2026-10-16)

T4 evidence refuted the analysis-time module model: `@import` modules are PARSE-registered (`parser.zig:780`), before any analysis gate — emission pruned (no `@cInclude` leak) but an untaken arm's `@import("missing.zig")` / file-syntax error still surfaces, unlike Zig's lazy file loading. **Ruling (C1b):** T4's touch set += `sf/src/main.zig` (import-queue/phase restructure) so an untaken arm's `@import` NEVER loads its file — true Zig laziness. **Ruling (C2):** fix now the pre-existing `parserParseBuiltinCall` `@import` `child_buf_len = 0` clobber (corrupts call args / tuple / array literals; switch-prong case already fixed locally) — the general 1-line delete is authorized despite the no-unrelated-fixes default (operator call). C3 (dead `int zG_impl` storage slot) + C4 (switch match = bool-case+else only) stay DISCLOSED, unfixed. Cost if wrong: import-phase restructure blast radius (mitigated by pins 0/8 + frozen-1124 gate); C2 general fix could shift unrelated parses (mitigated by battery + the corrupt-shape classes being today-broken).
