# Z98 Compiler Logic-Deduplication & Reuse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Provenance / rename (2026-10-05):** this plan replaces and renames
> `docs/superpowers/plans/2026-08-17-code-reuse-consolidation-plan.md` (pre-seed-model era).
> The old plan's `C-F0..C-F7` SAFE candidates and `C-R1..C-R5` byte-identity-RISKY findings are
> **absorbed as leads** into the per-file tasks below; its audit inputs
> (`.superpowers/sdd/task-C-I1-report.md` … `task-C-I7-report.md`) remain authoritative *starting
> leads* but are stale (Aug 2026) and MUST be re-derived against current `sf/src`.

**Goal:** Reduce duplicated and re-evaluated **logic** — not only shared helpers — across every
`sf/src/*.zig` that compiles into `zig1`, file by file, preserving **runtime equivalence**, and
measurably lowering the self-compile `-s0` `pool.peak` toward the 16 MB accountability.

**Architecture:** A per-file **Analyze → Refactor** task pair, ordered biggest-file-first. Analyze
is read-only and yields a logic-duplication census under taxonomy D1–D7 (repeated predicates,
re-evaluated/nested predicates, duplicated decision ladders, duplicate writes, rebuilt derived
structures, repeated comptime-fold arms, repeated AST/LIR shapes). Refactor consolidates the
censused duplication, proves truth-table equivalence, and passes the full runtime battery; emitted
C may change, runtime behavior must not. Task 0 renames the prior plan, freezes the compiler import
closure, and re-baselines the gates at the current seed. The closeout task re-baselines any moved
dump gates operator-ruled, rotates the seed, and reconciles QUICK_REF/EXPECTED_FAIL/README memory
numbers.

**Tech Stack:** Z98 (`sf/src/*.zig`), the seed model (`release/seed/`,
`scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh`), the `repro/mi_matrix` corpus and
its goldens, `--dump-c89`, `--markers`, `--track-memory`, gcc `-m32 -std=c89`, and the
superpowers SDD workflow.

**Prior volume/plan:** supersedes `2026-08-17-code-reuse-consolidation-plan.md` (this file, renamed).
Follow-ups already landed and informing this plan: `2026-09-06-lir-opt-pass-plan.md` (LIROPTPASS,
closeout `14181290`) and `2026-09-09-emission-core-compaction-plan.md` (EMITCOMPACT, closeout
`426ca7ff`).

---

## 0. Operator rulings binding this plan (do not re-litigate)

1. **This is an amendment + rename** of the 2026-08-17 reuse plan (operator, 2026-10-05).
2. **Emission may change.** De-duplicating logic WILL change emitted C and move the fixed point.
   The oracle is **runtime equivalence**: `repro/mi_matrix` corpus + runtime goldens + the run
   batteries must stay equivalent. The four dump-MD5 gates are **recorded not re-baselined per
   increment**, then re-baselined operator-ruled once at closeout.
3. **Census is manual per-file.** No automated extractor that "does the job" — a human/agent reads
   each file. An extractor may only *aid* discovery (grep/index), never be the source of a refactor.
4. **Biggest files first** (most prone to repetition). Granularity = an Analyze task and a Refactor
   task per file (small files grouped).
5. **Memory is a first-class objective**: measure `-s0` `pool=`/RSS per refactor increment.

## Global Constraints

- **Seed model (binding).** Reference compiler rebuilt per the seed model (`release/seed/`); the
  current seed is **v91** (archive md5 `39669954c928df59263e5d03cbaacd1d`; archived binary = fixed
  point `0b8c3e4ac0b1fc49c0bdf8caf9d39945`). Rotate the seed at closeout only, via
  `bash scripts/seed/archive_seed.sh`. Every plan begins from the committed seed.
- **Bootstrap-staging constraint.** New/changed `sf/src` code must be written in constructs the
  current seed already understands; adopt new syntax only after a new fixed point exists.
- **Runtime equivalence is the oracle.** For `repro/mi_matrix` dirs: run `zig1 --dump-c89 --output-dir`
  then gcc every emitted `.c` with the binding flag-set; classify by gcc EXIT CODE per
  `docs/sf/QUICK_REF.md` (dump rc≥128 = CRASH; stderr `error[(48|3042|9001|3043)]|AddressSanitizer`
  = ICE; gcc rc==0 = OK; else FAIL; 0 `.c` + diagnostic = FAIL; green-guards counted separately).
  Run-gate the runtime goldens (gol/lisp/json/mud) and the stdlib fixture battery
  (`bash scripts/stdlib/verify_stdlib.sh <zig1>`) byte-identically.
- **Dump-MD5 gates are recorded per increment** (gol/lisp/json/mud). Any change is expected and
  must be reported; the final values are operator-ruled re-baselined at closeout only.
- **Self-emission fixed point** converges via the N-hop chain per refactor task; records the new
  fixed point in the task report.
- **Memory metric.** Self-compile `-s0 --markers --track-memory -o <fresh-dir> sf/src/main.zig`
  (CWD = repo root, RELATIVE `sf/src/main.zig`), record `pool=`, `perm/mod/scr`, `type_db`, and
  `/usr/bin/time -v` Maximum RSS. Track AST/LIR node counts from the markers where relevant.
- **Editing:** `edit`/`fastedit` only (AGENTS.md §X.3/§X.7: re-read region before each edit,
  bottom-to-top; insert = replace anchor line with `[new content + original anchor line]`).
- **Compression is FORBIDDEN during build sessions** (overrides system compression alerts).
- **No push.** Commit per task; stage only intended files; never stage `mnemoria/`, `.opencode/`,
  `.zig1_*.tmp`, or the pre-existing untracked stray root files.
- **Timeout policy (operator ruling R2).** Every individual compile/run step is bounded by
  `timeout 120`. The authoritative AGGREGATE equivalence gates — the whole-corpus `classify`,
  `verify_stdlib`, and `verify_upgraded` — run under a bounded `timeout 600` (they take ~2–3 min and
  cannot fit 120s). STOP-present on ambiguity, divergence, or a plan-vs-evidence conflict.

---

## Logic-duplication taxonomy (what an Analyze task must find, per file)

| ID | Name | Definition | Cost proxy |
|----|------|------------|------------|
| **D1** | Repeated predicate | the same condition/helper (`isInteger`, `isPtr`, `typeKind == X`, `isAssignable`, `classifyCoercion`, range/bounds checks) evaluated at ≥2 sites | site count × decision count |
| **D2** | Re-evaluated / nested predicate | same condition re-checked in a sub-branch, or re-derived instead of passed through / cached | re-evaluation depth |
| **D3** | Duplicated decision ladder | repeated `if`/`switch` chain encoding the same truth table | ladder length × repeats |
| **D4** | Duplicate writes / SoA triple-write | same fact written to multiple tables/fields (`rtt`+`nc`+`sym` pattern) | write count |
| **D5** | Rebuilt derived structure | a buffer/table/derived value re-materialized where it could be reused | bytes rebuilt |
| **D6** | Repeated comptime-eval / fold arm | duplicated constant-fold / width/sign arms in `comptime_eval.zig` / `lower.zig` | arm count |
| **D7** | Repeated AST/LIR shape | one source pattern lowered/emitted through N parallel code shapes | node/temp count |

Every census row: `file:line`, occurrences, the shared **truth table**, the cost proxy, and a
**consolidation hypothesis**. A **global predicate→call-site index** is built across all files
(Task 0 seeds it; each Analyze task extends it).

---

## Compiler under test

```bash
cd /workspace/znineeight
FIXED_POINT_MD5=0b8c3e4ac0b1fc49c0bdf8caf9d39945 \
  bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/dedup_seed
# gate: === [seed] Done: /tmp/dedup_seed ===
# result: /tmp/dedup_seed/zig1_5_clean + /tmp/dedup_seed/lib/
```

## Runtime / memory gate battery (every Refactor task)

```bash
# behavior
bash scripts/stdlib/verify_stdlib.sh /tmp/dedup_seed/zig1_5_clean     # stdlib fixtures
bash scripts/corpus/classify ...                                      # repro/mi_matrix classification
# runtime goldens + examples matrix + verify_upgraded.sh per QUICK_REF
# dump-MD5 (recorded, not re-baselined per increment)
# memory
rm -rf /tmp/selfc && mkdir -p /tmp/selfc
/usr/bin/time -v /tmp/dedup_seed/zig1_5_clean -s0 --markers --track-memory -o /tmp/selfc sf/src/main.zig
```

---

### Task 0: Preflight — rename, closure, baselines, census seed (read-only + docs)

**Files:**
- Rename (already done by this amendment): `docs/superpowers/plans/2026-08-17-code-reuse-consolidation-plan.md`
  → `docs/superpowers/plans/2026-10-05-compiler-logic-dedup-and-reuse-plan.md`; update the
  cross-reference in `docs/superpowers/plans/2026-08-17-parser-gaps-code-reuse-plan.md:5`.
- Read-only: `sf/src/**`, `.superpowers/sdd/task-C-I1..I7-report.md`, `docs/sf/QUICK_REF.md`,
  `repro/mi_matrix/EXPECTED_FAIL.md`.
- Report: `.superpowers/sdd/2026-10-05-compiler-logic-dedup-and-reuse-plan/task-0-report.md`.

- [ ] **Step 1: Freeze the compiler closure.** Compute and record the exact transitive `@import`
  closure of `sf/src/main.zig` (exclude `std_*` user modules and `sf/src/tests/**`); list every
  file with its line count. This is the authoritative per-file task scope.
- [ ] **Step 2: Build the compiler** per "Compiler under test"; record the md5.
- [ ] **Step 3: Gate baseline.** Record the current corpus classification, runtime goldens, stdlib
  battery, examples matrix, and the 4 dump-MD5 values at HEAD.
- [ ] **Step 4: Memory baseline.** Record `-s0` `pool=`/`perm/mod/scr`/`type_db`/RSS/wall and the
  `-mm16` breach behavior (expected `memory limit exceeded` rc=3).
- [ ] **Step 5: Seed the predicate index and absorb old audits.** Build the global predicate→site
  index skeleton; extract the `C-I*` audits' duplication leads (noting each is stale and must be
  re-derived).
- [ ] **Step 6: Report + commit** the rename/cross-reference/plan with
  `docs: rename code-reuse plan to logic-dedup-and-reuse (post-seed-model)`. No compiler edits.

---

## Per-file tasks (biggest-first; each Analyze and Refactor is its OWN separate task)

> **Do NOT combine an Analyze and a Refactor into one task, one dispatch, or one ledger entry.**
> Each **Analyze** task is READ-ONLY (no commit): it produces a logic-duplication census under
> taxonomy D1–D7 (file:line, occurrences, shared truth table, cost proxy, consolidation hypothesis)
> and extends the global predicate→site index. Its deliverable is its census report, reviewed before
> the paired Refactor is dispatched. Each **Refactor** task then consumes its Analyze census,
> implements only the censused consolidations, proves runtime equivalence with the full battery,
> records the dump-MD5 delta and the memory delta, and commits. Emitted C may change; runtime must
> not. The `C-*` leads are stale inputs to be re-derived, never a substitute for the census.
>
> **Scope rulings binding these tasks** (controller preflight + Task 0): (a) the frozen `main.zig`
> closure from Task 0 is the authoritative refactor scope; files found outside it (`main_dump`,
> `dump_ast`, `dump_tokens`, `constraint_checker`, `util/sort`) are triaged as dead/test-only in
> Tasks 29–30, never refactored here. (b) `state_map.zig` belongs only to Tasks 21–22. (c) dead-stub
> deletion belongs only to Tasks 29–30.

### Task 1: Analyze `c89_emit.zig` (10,510) — READ-ONLY
- Census D1–D7 in the emitter: repeated type/kind predicates, emission-order walks,
  variant-field/cast/string-escape/`#ifdef` arms (leads `C-I6 #6/#9/#10/#11/#12/#14/#17`, `C-R5`).
- Deliverable: census report. Commit: NONE.

### Task 2: Refactor `c89_emit.zig` — executed as increments 2a/2b/2c
> Operator ruling (2026-10-05): Task 2 is too large and order-sensitive for one review surface, so it
> runs as three sequential, separately-reviewed, separately-committed increments. Each increment runs
> the full battery, records its dump-MD5 delta and its `-s0` pool/RSS delta, and commits only
> `sf/src/c89_emit.zig`. All three target the same file.

### Task 2a: Refactor `c89_emit.zig` — compiler-side, no emitted-text change (LOW risk)
- Clusters: D1-1 hoisted-temp lookup; D1-3 is-main (+ delete the dead `is_main`@2572); D1-6 delete
  the dead `getCheckedCastFnName`@5705; D1-7 include predicates; D5-1/D5-2 itoa/marker helpers;
  D5-4 `cnameDedupKey`; D5-6 dedup sets; D6-4 `float_const` single-format; D3-10 build-script loops;
  plus the Task 1 census gap `nameManglerPopulateKeywords` (487-551), folded in by operator ruling.
- Expected: measurable `-s0` pool delta; dump-MD5 ideally unchanged (record regardless).
- Commit `refactor(c89_emit): deduplicate compiler-side logic (2a)`.

### Task 2b: Refactor `c89_emit.zig` — emitted-text refactors — split into 2b1/2b2/2b3
> Operator ruling (2026-10-05): 2b bundles ~15 emitted-text clusters — too large for one review
> surface — so it runs as three sequential, separately-reviewed, separately-committed area
> increments. Each runs the full battery, records its dump-MD5 delta and `-s0` pool/RSS delta, and
> commits only `sf/src/c89_emit.zig`. Emitted C may change; runtime equivalence is the oracle.

### Task 2b1: Refactor `c89_emit.zig` — field/call emission helpers (MED risk)
- Clusters: D7-1 field-name resolution ladder; D7-2/D2-3 variant-field designator; D7-3/D6-3 array
  copy/zero; D7-4 call-argument loop; the four retained D1-1 sites (variant-src `emitFieldAssign`;
  `getTempEffType`; `.load_field res_ty`; `.store_field sf_src_ty`).
- Commit `refactor(c89_emit): deduplicate field/call emission (2b1)`.

### Task 2b2: Refactor `c89_emit.zig` — type/decl emission (MED risk)
- Clusters: D5-5 synthetic type-name builders; D3-5/D6-1 `emitSharedHeader`≡`emitSpecialTypes`
  passes; D3-6 `emitModule`/`emitModuleFile`; D3-7 `emitFunctionSignature`/`emitFunctionForwardDecl`;
  D3-11 `#define` macro loops; D1-4 global extern decl emission.
- Commit `refactor(c89_emit): deduplicate type/decl emission (2b2)`.

### Task 2b3: Refactor `c89_emit.zig` — semantic tables / opcode descriptors (MED risk)
- Clusters: D1-2 int-kind truth tables; D3-3 LirInst shape descriptors; D4-1 `written_type` writes;
  D3-8 cast-emission helper; D3-9 optional/EU wrap-unwrap ladder.
- Commit `refactor(c89_emit): deduplicate semantic tables/descriptors (2b3)`.

### Task 2c: Refactor `c89_emit.zig` — order-sensitive (HIGH risk)
- Clusters: D3-2/D2-1/D2-2 `tstEdges` single walker (topo order → 4 MD5 gates); D7-5 string escape;
  D7-6 `#ifdef` arms; D7-7 binary/unary; D7-8 print route; D6-2 int-const fold.
- Runtime-equivalence gated; dump-MD5 deltas recorded.
- Commit `refactor(c89_emit): deduplicate order-sensitive logic (2c)`.

### Task 3: Analyze `lower.zig` (9,681) — READ-ONLY
- D2/D6/D7: repeated fold arms, cond-to-bool, capture tails, comptime helpers
  (leads `C-I5 #2/#6/#7/#14`, `C-F5`).
- Deliverable: census report. Commit: NONE.

### Task 4: Refactor `lower.zig` — split into 4a/4b/4c
> Operator ruling (2026-10-05): the census's top clusters are temp-order/emitted-text observable, so
> Task 4 runs as three sequential, separately-reviewed, separately-committed area increments. Each
> runs the full battery, records its dump-MD5 delta and `-s0` pool/RSS delta, and commits only
> `sf/src/lower.zig`. Emitted C may change; runtime equivalence is the oracle.

### Task 4a: Refactor `lower.zig` — field/compound lowering ladders (MED risk)
- Clusters: D7-1 compound-assign arm template (34 arms); D3-1/D7-9 field-access/store/addr ladders
  (~450 ln); D7-9 packed field store/load; D7-5 for-loop skeleton.
- Commit `refactor(lower): deduplicate field/compound lowering (4a)`.

### Task 4b: Refactor `lower.zig` — call/expr lowering (MED risk)
- Clusters: D7-2/D4-1 call-argument loops; D7-4/D3-2 switch expr-vs-stmt; D6-1/D7-6 binary/unary arm
  prologue+shape; D7-3 capture-binding tail.
- Commit `refactor(lower): deduplicate call/expr lowering (4b)`.

### Task 4c: Refactor `lower.zig` — data-structure/printer/value helpers (LOW–MED risk)
- Clusters: D5-2 `LirFunction` header rebuild; D5-1 ArrayList grow boilerplate; D1-2 `printFmt` kind
  ladders; D4-2 local-decl SoA writes; D5-4 `TypeResolveEnv` rebuild; D1-1 int width/signedness;
  D1-4 `resolvedTypeTableGet`; D1-5 ICE helpers; D6-2 fold-lookup; D2-1 condition tag; D1-6/D6-3
  AST-kind sets; D3-5 eu_box; D1-3 symbol predicates; D2-2 synthName; D5-5 marker/itoa; D5-3 hoistTemps.
- Commit `refactor(lower): deduplicate data-structure/value helpers (4c)`.

### Task 5: Analyze `semantic_analyzer.zig` (7,016) — READ-ONLY
- D1/D2/D3: `isAssignable`/`classifyCoercion` and coercion/type predicates (leads `C-R2`, `C-I3`).
- Deliverable: census report. Commit: NONE.

### Task 6: Refactor `semantic_analyzer.zig`
- Truth-table equivalence required. Commit `refactor(sema): deduplicate <cluster> logic`.

### Task 7: Analyze `type_resolver.zig` (2,524) — READ-ONLY
- D1–D3: inference predicates. Deliverable: census report. Commit: NONE.

### Task 8: Refactor `type_resolver.zig`
- Commit `refactor(type_resolver): deduplicate <cluster> logic`.

### Task 9: Analyze `parser.zig` (2,263) — READ-ONLY
- D1–D3: repeated precedence / `maybeDisambiguateCapture` shapes. Deliverable: census report. Commit: NONE.

### Task 10: Refactor `parser.zig`
- Commit `refactor(parser): deduplicate <cluster> logic`.

### Task 11: Analyze `lir_opt_pass.zig` (2,150) — READ-ONLY
- D1–D3: pure/ordered classification repeats. Deliverable: census report. Commit: NONE.

### Task 12: Refactor `lir_opt_pass.zig`
- Commit `refactor(lir_opt_pass): deduplicate <cluster> logic`.

### Task 13: Analyze `main.zig` (1,917) + dump dispatch — READ-ONLY
- D1/D3: duplicated CLI/phase/dump dispatch, scoped to the frozen closure.
- Deliverable: census report. Commit: NONE.

### Task 14: Refactor `main.zig` + dump dispatch
- Commit `refactor(main+dump): deduplicate dispatch logic`.

### Task 15: Analyze `comptime_eval.zig` (1,902) — READ-ONLY
- D6: duplicated width/sign table + fold arms. Deliverable: census report. Commit: NONE.

### Task 16: Refactor `comptime_eval.zig`
- Exhaustive truth-table case tests. Commit `refactor(comptime_eval): deduplicate width/fold logic`.

### Task 17: Analyze `type_registry.zig` (1,410) — READ-ONLY
- D1–D4. Deliverable: census report. Commit: NONE.

### Task 18: Refactor `type_registry.zig`
- Commit `refactor(type_registry): deduplicate <cluster> logic`.

### Task 19: Analyze async trio — `async_state_machine` (1,275) · `async_analysis` (752) · `async_frame_layout` (685) — READ-ONLY
- D1–D4. Deliverable: census report. Commit: NONE.

### Task 20: Refactor async trio
- Commit `refactor(async): deduplicate <cluster> logic`.

### Task 21: Analyze IR/store tier — `ast` (1,050) · `lir` (603) · `lir_stream` (319) · `spill_store` (245) · `resolved_type_table` (234) · `state_map` (119) — READ-ONLY
- D4/D5: SoA triple-writes, rebuilt buffers (leads `C-R3`, `C-R4`). Deliverable: census report. Commit: NONE.

### Task 22: Refactor IR/store tier
- Commit `refactor(ir-store): deduplicate table writes/buffers`.

### Task 23: Analyze support — `emit_support` (1,037) + live support files — READ-ONLY
- D1–D7. Dead stubs deferred to Tasks 29–30. Deliverable: census report. Commit: NONE.

### Task 24: Refactor `emit_support` + live support
- Commit `refactor(emit-support): deduplicate <cluster> logic`.

### Task 25: Analyze lexer tier — `lexer.zig` (1,016) + `token.zig` (203) — READ-ONLY
- D1–D3. Deliverable: census report. Commit: NONE.

### Task 26: Refactor lexer tier
- Commit `refactor(lexer): deduplicate token-class logic`.

### Task 27: Analyze mid/small closure files — READ-ONLY
- `diagnostics` (971) · `analyzer` (920) · `module_registry` (742) · `symbol_registrator` (505) ·
  `allocator` (359) · `pal` (282) · `growable_array` (271) · `source_manager` (262) ·
  `coercion` (225) · `const_alias_prepass` (234) · `front_resolution` (216) · `symbol_table` (147) ·
  `import_resolver` (151) · `string_interner` (171) · `util/*` (hash/format/itoa/mem/path/util).
- D1–D7; absorb old `C-F0` shared primitives and `C-F1..C-F7` SAFE candidates as stale leads.
- May be split into sub-batches by the controller if too large for one review surface.
- Deliverable: census report. Commit: NONE.

### Task 28: Refactor mid/small closure files
- Commit `refactor(<area>): deduplicate shared <cluster>`.

### Task 29: Analyze dead-file / stub cleanup (importer proof) — READ-ONLY
- Confirm zero importers for the tiny/legacy/out-of-closure files (`name_mangler.zig`, `extern_c.zig`,
  `main_exp.zig`, `config.zig`, `test_a.zig`, `test_b.zig`, `assign_helper.zig`, duplicate
  `util/growable_array.zig`, and the out-of-closure dump files from Task 13).
- Deliverable: importer-proof report. Commit: NONE.

### Task 30: Delete proven-dead compiler modules
- Delete only files Task 29 proved dead. Commit `chore(dead-code): remove unused compiler modules`.

---

### Task 31: Closeout — whole-set re-verify, memory, dump-MD5, seed rotation

**Files:** `docs/sf/QUICK_REF.md`, `repro/mi_matrix/EXPECTED_FAIL.md`, `README.md`,
`release/seed/**` (rotation), this plan, `.superpowers/sdd/.../task-*-report.md`.

- [ ] **Step 1: Whole-set runtime re-verify** — corpus + runtime goldens + stdlib battery +
  examples matrix byte-equivalent vs the Task-0 baseline.
- [ ] **Step 2: Memory delta** — record `-s0` `pool=`/RSS vs Task 0; state the movement toward the
  16 MB target (and the honest remainder).
- [ ] **Step 3: Dump-MD5 re-baseline** — operator-ruled; update QUICK_REF gate rows + fixed point.
- [ ] **Step 4: README memory reconciliation** — replace the stale v27-era numbers (Row D, §155,
  §240, §146) with the measured current values; note `pool=` is cumulative carve, not RSS.
- [ ] **Step 5: Seed rotation** — rotate v91 → v92 via `scripts/seed/archive_seed.sh`; verify the
  two-hop closure; update `release/seed/CHANGELOG.md` + `SEED_README.txt`.
- [ ] **Step 6: Spec/plan status** + final commit
  `docs: compile-logic-dedup closeout — runtime-equivalent, memory re-measured, seed rotated`.

---

## Open items carried from the audit era (triage during Analyze, do not assume)

- `lower.zig:1526` latent wide-enum-switch panic; two test `EnumPayload` constructors missing
  `.explicit_backing`; layout-B enum flag spurious; width-32+ admission-cap reliance (LIROPTPASS record Minors).
- `C-R3` triple-write and `C-R4` hoistTemps double-buffer are prime D4/D5 candidates.
- `EXTERN_C`/`cinclude` dead stubs and the duplicate `util/growable_array.zig` need an importer check.

## Notes

- The prior plan's byte-identity constraint is intentionally lifted here; do NOT carry its
  "allocation behavior byte-identical" requirement into Refactor tasks.
- `pool=` is the monotonic carve of the shared `memory_pool_buf` (never reset); report it *and* RSS.
- Keep the plan's per-file reports under
  `.superpowers/sdd/2026-10-05-compiler-logic-dedup-and-reuse-plan/`.
