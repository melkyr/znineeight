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
- **Every command/run under `timeout 120`.** STOP-present on ambiguity, divergence, or a
  plan-vs-evidence conflict.

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

## Per-file task groups (biggest-first; each = Analyze then Refactor)

> Each group's **Analyze** task is read-only (census + truth tables + hypothesis); its **Refactor**
> task implements the consolidations with the runtime battery and commits. A group may be split
> when its Refactor is too large for one review surface; small files are grouped. The `C-*` leads
> are inputs, not a substitute for the census.

### G1: `c89_emit.zig` (10,510)
- **Analyze** (`### Task G1a`): census of D1–D7 in the emitter — repeated type/kind predicates,
  emission-order walks, variant-field/cast/string-escape/`#ifdef` arms (leads `C-I6 #6/#9/#10/#11/#12/#14/#17`, `C-R5`).
- **Refactor** (`### Task G1b`): consolidate; the emitter is order-sensitive — any emission-order
  change is runtime-gated, and the dump-MD5 delta is recorded.
- Files: `sf/src/c89_emit.zig`. Commit `refactor(c89_emit): deduplicate <cluster> logic`.

### G2: `lower.zig` (9,681)
- Analyze: D2/D6/D7 — repeated fold arms, cond-to-bool, capture tails, comptime helpers
  (leads `C-I5 #2/#6/#7/#14`, `C-F5`). Refactor accordingly.
- Commit `refactor(lower): deduplicate <cluster> logic`.

### G3: `semantic_analyzer.zig` (7,016)
- Analyze: D1/D2/D3 — `isAssignable`/`classifyCoercion` and coercion/type predicates
  (leads `C-R2`, `C-I3`). Refactor with truth-table equivalence.
- Commit `refactor(sema): deduplicate <cluster> logic`.

### G4: `type_resolver.zig` (2,524) · G5: `parser.zig` (2,263) · G6: `lir_opt_pass.zig` (2,150)
- Analyze each for D1–D3 (parser: repeated precedence/`maybeDisambiguateCapture` shapes; resolver:
  inference predicates; opt pass: pure/ordered classification repeats). Refactor each.
- Commits `refactor(<file>): deduplicate <cluster> logic`.

### G7: `main.zig` (1,917) + `main_dump.zig` (326) + `dump_ast.zig` (315) + `dump_tokens.zig` (156)
- Analyze: duplicated CLI/phase/dump dispatch; D1/D3. Refactor.
- Commit `refactor(main+dump): deduplicate dispatch logic`.

### G8: `comptime_eval.zig` (1,902)
- Analyze: D6 — duplicated width/sign table + fold arms. Consolidate with exhaustive truth-table case tests.
- Commit `refactor(comptime_eval): deduplicate width/fold logic`.

### G9: `type_registry.zig` (1,410) · G10: async trio (`async_state_machine` 1,275, `async_analysis` 752, `async_frame_layout` 685)
- Analyze D1–D4; refactor.
- Commits `refactor(type_registry): …`, `refactor(async): …`.

### G11: IR/store tier — `ast` (1,050), `lir` (603), `lir_stream` (319), `spill_store` (245), `resolved_type_table` (234), `state_map` (119)
- Analyze: D4/D5 — SoA triple-writes, rebuilt buffers (leads `C-R3`, `C-R4`). Refactor.
- Commit `refactor(ir-store): deduplicate table writes/buffers`.

### G12: support — `emit_support` (1,037), `name_mangler` (7), `cinclude` (32), `extern_c` (3)
- Analyze; refactor or fold dead stubs.
- Commit `refactor(emit-support): …` / `chore(dead-code): …`.

### G13: `lexer.zig` (1,016) + `token.zig` (203)
- Analyze D1–D3; refactor.
- Commit `refactor(lexer): deduplicate token-class logic`.

### G14: mid/small — `diagnostics` (971), `analyzer` (920), `module_registry` (742), `symbol_registrator` (505), `allocator` (359), `pal` (282), `growable_array` (271), `source_manager` (262), `coercion` (225), `front_resolution` (216), `const_alias_prepass` (234), `symbol_table` (147), `import_resolver` (151), `string_interner` (171), `state_map` (already G11), `constraint_checker` (72), `panic` (21), `util/*` (hash/format/itoa/mem/path/util/sort)
- Analyze D1–D7; refactor in sub-batches (this group absorbs old `C-F0` shared primitives and
  `C-F1..C-F7` SAFE candidates).
- Commit `refactor(<area>): deduplicate shared <cluster>`.

### G15: dead-file / stub cleanup
- Analyze: confirm zero importers for the tiny/legacy files (`name_mangler.zig`, `extern_c.zig`,
  `main_exp.zig`, `config.zig`, `test_a.zig`, `test_b.zig`, `assign_helper.zig`, and duplicate
  `util/growable_array.zig`) before any deletion. Refactor: delete only proven-dead files.
- Commit `chore(dead-code): remove unused compiler modules`.

---

### Task N: Closeout

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
