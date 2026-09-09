# Emission-Core Compaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the two structural lowering/emitter redundancies measured at the LIROPTPASS closeout — (1) duplicate named-local stores (22,854 consecutive-identical `name = zT_N;` lines, 3×-dominant, ~8% of the 285,691-line self-emission) and (2) straight `zT_N = zT_M;` copies (14,194, dominated by call-argument materialization) — producing tighter C89 emission with byte-identical program semantics.

**Architecture:** Fix the redundancy at its **lowering source** (keep the emitter dumb): Part 1 collapses the multi-instruction named-local store emission to its minimal keep-set at the sites identified by census; Part 2 coalesces straight copies case-by-case per a strict type-identity + single-use + pure + trivial-move gate, exactly one F task per coalescible case. Corpus is the primary accuracy oracle; runtime/emission md5 gates move by design and are operator-ruled re-baselined only at closeout.

**Tech Stack:** Z98 (`sf/src/*.zig`), LIR (`lir.zig`), C89 emitter (`c89_emit.zig`), lowering (`lower.zig`); gcc `-m32 -std=c89`; seed model (`scripts/seed/build_from_seed.sh`, `archive_seed.sh`).

**Spec:** `docs/superpowers/specs/2026-09-09-emission-core-compaction-design.md`

## Global Constraints

- **Scope: compaction only; semantic optimization explicitly out.** Changes the *encoding*, never program semantics. No cross-BB/CFG/inlining/loop transforms.
- **Reference compiler per the seed model** (`release/seed/`); every F task that touches `sf/src` converges a new fixed point via the N-hop chain and **rotates nothing** (rotation happens only at Task 7). Measurement compiler = the N-hop-converged binary, stated explicitly per task report. Dump CWD = repo root, relative `sf/src/main.zig`.
- **Flag-set rule (binding):** every gcc `-c` = `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`; `-Wall -Wextra -O3 -fsyntax-only` is a SEPARATE verification gate, never the build command. Self-emission link set = `zig_runtime.c` + `zig_pal.c` + `c_exit.c`.
- **Corpus is the primary accuracy oracle:** current corpus state (HEAD `14181290`) = 419 dirs (365 `repro/mi_matrix` + 54 `repro` top-level) = 404 OK / 9 GREEN / 6 FAIL. Every F increment: corpus **zero-asymmetric** except the newly-added Part-1 repro dirs (absent → OK/GREEN). Classify by gcc exit code per QUICK_REF.md:106-126 (`dump rc≥128`=CRASH, stderr `error[(48|3042|9001|3043)]|AddressSanitizer`=ICE, gcc rc==0=OK, else FAIL; 0 `.c` emitted with a diagnostic = FAIL; green-guards counted separately). Run-gate: golden 9/9 + matrix 21/21 stdout/RUNRC byte-identical to PRE captures.
- **4-MD5 + runtime emission gates move by design:** duplicate-store removal and copy coalescing change gate-program emission. All four 4-MD5 dump gates (gol `80a0402b…`, lisp `e95bf0c5…`, json `ba07af4b…`, mud `a3a8b27a…`) and golden/matrix runtime md5s are **recorded-not-rebaselined per increment**; operator-ruled full re-baseline at the Task-6 STOP only.
- **Task-2 minimal repros stay in the corpus permanently** as the "proper emission" pin — see Task 2.
- **Seed-rotation at closeout only** (Task 7), via `bash scripts/seed/archive_seed.sh <fixed-point-binary> <fresh-gen-dir> release/seed/zig1-seed.tgz --update-changelog`, with EXPECTED_FAIL/QUICK_REF/CHANGELOG edits in the same docs-GATE commit.
- **Two-part closeout gate:** (A) N-hop self-consistency (seed → g1 → … → gn==gn+1, ≤4 hops, hop1≠hop2 expected after self-affecting changes) + (B) behavioral identity = converged compiler re-runs the full external battery byte-identical.
- **Working conventions (binding):** SDD skill mandatory (fresh implementer subagent per task + task reviewer + fix loops); compression FORBIDDEN during build sessions (overrides system alerts); memories via `mnemoria --path .opencode/memory add` under agent `<plan>-session`; edits via `edit`/`fastedit` only (X.3/X.7); no commit until a task's review is clean; pre-existing dirty/untracked set (M `2026-08-26…plan.md`, M `mnemoria/*`, ?? `.zig1_res.tmp`, ?? `.zig1_side.tmp`, ?? `examples/z98/json_parser_upgraded/`) never staged.
- Report file `.superpowers/sdd/task-EMITCOMPACT-report.md`; ledger `.superpowers/sdd/progress.md`; memory agent `emitcompact-session`.

---

### Task 1: Part-1 store-multiplicity census + Part-2 copy-taxonomy census (I, record-only)

**Files:**
- Read: `sf/src/lower.zig`, `sf/src/c89_emit.zig`, `sf/src/lir.zig`, `sf/src/lir_opt_pass.zig`
- Report: `.superpowers/sdd/task-EMITCOMPACT-report.md` (appended `## Task 1`)
- No source edits, no commit, nothing staged.

**Interfaces:**
- Consumes: baseline facts below.
- Produces: the authoritative keep-set decision for Task 2 and the coalescible-case list for Tasks 3-5.

**Context / baseline (verified at HEAD `14181290`, self-emission `/tmp/t4e_run/g2/gen`, fixed point `048824c9`, 42 `.c` + 43 `.h`, 285,691 lines):**
- 22,854 consecutive-identical `name = zT_N;` lines (~8% of 285,691) — all named-local stores; multiplicity of unique store lines: 1× 5,466 / 2× 2,604 / 3× 8,954 / 4× 294 / 5× 153 / 6× 327 / higher to ~45×.
- 14,194 straight `zT_N = zT_M;` copies.
- Known emission sites: decl path `lower.zig:5500` (`.store_local`), `:5504` (`.assign` with `name_id`), `:5518` (`.assign` dst=backing `reg`); assign path `lowerAssignLValue :1119` (`.store_local`) + `:1121` (`.assign`); all render to the same C text because `name_id != 0` overrides the temp dst (`c89_emit.zig:5682`) and the backing reg maps back via the `fl_temps` reverse-lookup (`c89_emit.zig:5685`).

- [ ] **Step 1: Baseline reconfirmation.** Re-confirm HEAD `14181290`, reference / fixed-point `048824c9` (binary at `/tmp/t4e_run/g2/zig1`, canonical std at `/tmp/t4e_run/g2/lib`), 4-MD5 gate values (gol `80a0402b…`, lisp `e95bf0c5…`, json `ba07af4b…`, mud `a3a8b27a…`), EXPECTED_FAIL v76. Record in the report.
- [ ] **Step 2: Part-1 store-multiplicity census (authoritative keep-set).** For each distinct store multiplicity shape (2×/3×/4×/…/N×) and each emitting path (decl, plain assign, value-block join, capture bind, if/switch merge, `decl_local` init, loop iterator):
  - Identify the exact LIR instruction sequence emitted for one logical store.
  - Determine, by tracing **reader sites** (how later uses of the name resolve: through the backing temp via `resolveTempName`/`fl_temps`, or through the name directly), which single instruction makes the value visible to every later reader and which emitted instructions are pure dead stores.
  - Produce the **minimal keep-set** per path (expected: one keep per logical store; exact instruction chosen per reader evidence, NOT assumed).
  - Enumerate every `emitInst` site in `lower.zig` that produces a named-local store and tag each site with its multiplicity and keep/drop verdict.
  - Count the emitted line + byte delta the fix is expected to yield on the self-emission and on `examples/z98/game_of_life` + `examples/z98/mud_server` representative dumps.
- [ ] **Step 3: Part-2 copy-taxonomy census.** Walk every straight-copy-producing site in `lower.zig` (candidate list: arg-slot `:3233, :3284, :3383, :3469, :3544`; join-temp `:3948, :3957, :3994, :4005, :4032, :4036, :4075, :4083`; loop/iterator `:5118, :5171`; tail-call self-call `:5321`; decl init `:5474, :5480`; plus any the walk discovers). For each copy instance measure, against the coalescing gate in spec §4.1 (identical `TypeId`, both single-use, pure/not-addr-taken producer, scalar/pointer trivial move — reuse the existing `copyScalarKindOk` + `type_id` identity guard machinery already in `lir_opt_pass.zig`): coalescible count vs keep count + reason. Assign each Part-1-overlapping site to exactly one part.
- [ ] **Step 4: Report + ledger.** Append the full census (with per-site tables, keep-set verdicts, coalescible-case list, yield estimates) to the report. Append one ledger line to `.superpowers/sdd/progress.md`. No commit; `git status` == pre-existing set only.

---

### Task 2: Part 1 — collapse duplicate named-local stores + minimal-repro corpus fixtures (F)

**Files:**
- Modify: `sf/src/lower.zig` (sites per Task-1 census — expected: the decl + plain-assign + join paths; keep the emitter unchanged)
- Create (fixtures, corpus-bound): `repro/mi_matrix/store_dedup_const_xmod/main.zig`, `repro/mi_matrix/store_dedup_assign_xmod/main.zig`, `repro/mi_matrix/store_dedup_valueblock_xmod/main.zig` (names TBD by the implementer, must end `_xmod`)
- Report: `.superpowers/sdd/task-EMITCOMPACT-report.md` (appended `## Task 2`)
- Commit: `feat: emission-core compaction — deduplicate named-local stores + minimal-repro fixtures (Part 1)` — scoped to `sf/src/lower.zig` + the new fixture dirs only.

**Interfaces:**
- Consumes: Task-1 keep-set verdicts (the exact instruction to keep per path).
- Produces: single-store emission (no consecutive duplicate `name = zT_N;` lines) + permanent corpus repros pinning it.

- [ ] **Step 1: Minimal repros FIRST (RED against current emission).** Author the fixture(s) so that at HEAD (pre-fix) each one (a) compiles/classifies OK and runs GREEN with byte-exact stdout, and (b) its emitted C **contains consecutive duplicate named-local-store lines** (the defect the fix removes). Each fixture follows corpus convention: header comment stating the GREEN contract + the "proper emission" invariant, `const std = @import("std");`, `pub fn main() void`, `std.io.printInt`/`std.io.writeByte` output, deterministic stdout. Cover at least: (1) a `const x = f()` decl (3× shape), (2) a plain `x = expr` assignment (2× shape), (3) a value-block / if-else-merge store shape (higher-multiplicity shape). Verify each dumps a `.c` containing ≥1 pair of adjacent identical `name = zT_N;` lines. Record emitted-C line evidence in the report.
- [ ] **Step 2: Implement the dedup at the Task-1-identified source sites.** Apply the minimal keep-set per path so each logical named-local store emits exactly one LIR instruction (hence one C statement). Do NOT add an emitter peephole — fix the lowering source. Keep the emitter byte-logic untouched.
- [ ] **Step 3: Emission gate.** Re-dump the new fixtures: emitted C must contain **zero** consecutive duplicate `name = zT_N;` lines (grep-able invariant) while stdout stays byte-exact GREEN. Re-dump the self-emission + representative examples: confirm no consecutive-duplicate named-store lines remain anywhere and record the new self-emission line/byte totals.
- [ ] **Step 4: Run-identity + corpus gate.** Golden 9/9 + matrix 21/21 stdout/RUNRC byte-identical to PRE captures. Corpus sweep at `-s0`: zero-asymmetric on the pre-existing 419 dirs; the new fixture dirs classify OK (GREEN at run gate). 4-MD5 re-dumped and **recorded-not-rebaselined** (values will move). Self-compile converges to a new fixed point (N-hop, ≤4 hops, record chain + hop md5s). Record all evidence.
- [ ] **Step 5: Commit.** Stage only `sf/src/lower.zig` + the new fixture dirs; commit with the message above.
- [ ] **Step 6: Report + ledger.** Append evidence + concerns; append ledger line.

---

### Task 3: Part 2 — arg-slot copy coalescing (F)

**Files:**
- Modify: `sf/src/lower.zig` (arg-slot emission sites) and/or `sf/src/lir_opt_pass.zig` (per the Task-1 census verdict — the fix lands where the census proves the copy is produced/droppable)
- Report: `.superpowers/sdd/task-EMITCOMPACT-report.md` (appended `## Task 3`)
- Commit: `feat: emission-core compaction — coalesce call-argument slot copies (Part 2, case 1)`

**Interfaces:**
- Consumes: Task-1 coalescible verdict for the arg-slot case (`lower.zig:3233, :3284, :3383, :3469, :3544`).
- Produces: arg expressions materialized without the redundant intermediate copy where the type-identity + single-use + pure + trivial-move gate passes.

- [ ] **Step 1: Implement coalescing for the arg-slot case only**, per the census verdict. A copy `dst=src` (or producer-result rename to `dst`) collapses iff identical `TypeId`, both single-use, pure/not-addr-taken producer, scalar/pointer trivial move — otherwise keep the copy (type boundary). Never emit a type-changing coalesce.
- [ ] **Step 2: Run-identity + corpus gate** (identical recipe to Task-2 Step 4): golden 9/9 + matrix 21/21 byte-identical to PRE; corpus `-s0` zero-asymmetric on the pre-existing 419 dirs; 4-MD5 recorded-not-rebaselined; N-hop convergence recorded; self-emission line/byte delta recorded.
- [ ] **Step 3: Commit** (message above, scoped to the census-identified files).
- [ ] **Step 4: Report + ledger.**

---

### Task 4: Part 2 — join-temp copy coalescing (F)

**Files:**
- Modify: per Task-1 census (expected `sf/src/lower.zig` join-temp sites `:3948, :3957, :3994, :4005, :4032, :4036, :4075, :4083` and/or `sf/src/lir_opt_pass.zig`)
- Report: `.superpowers/sdd/task-EMITCOMPACT-report.md` (appended `## Task 4`)
- Commit: `feat: emission-core compaction — coalesce join-temp copies (Part 2, case 2)`

- [ ] **Step 1: Implement coalescing for the join-temp case only** (if/switch/orelse/catch merge results), same gate as Task 3.
- [ ] **Step 2: Run-identity + corpus gate** (recipe as Task-2 Step 4).
- [ ] **Step 3: Commit** (message above).
- [ ] **Step 4: Report + ledger.**

---

### Task 5: Part 2 — remaining coalescible copy cases (F)

**Files:**
- Modify: per Task-1 census (candidate: loop/iterator `:5118, :5171`; tail-call self-call `:5321`; decl-init copies `:5474, :5480`; and any additional coalescible case Task 1 enumerated)
- Report: `.superpowers/sdd/task-EMITCOMPACT-report.md` (appended `## Task 5`)
- Commit: `feat: emission-core compaction — coalesce remaining copy cases (Part 2, close)`

- [ ] **Step 1: Implement coalescing for every remaining coalescible case** Task 1 enumerated, each under the same gate. Cases the census tagged "keep" are NOT forced.
- [ ] **Step 2: Full Part-2 verification**: run-identity (golden 9/9 + matrix 21/21), corpus `-s0` zero-asymmetric, 4-MD5 recorded-not-rebaselined, N-hop convergence recorded, self-emission + Row E deltas measured vs the Task-1 baseline. Confirm the Part-1 repros still emit single-store (no regression).
- [ ] **Step 3: Commit** (message above).
- [ ] **Step 4: Report + ledger.**

---

### Task 6: Full battery + N-hop + gate re-baseline STOP-present (I, record-only)

**Files:**
- Report: `.superpowers/sdd/task-EMITCOMPACT-report.md` (appended `## Task 6`)
- No commit, nothing staged.

- [ ] **Step 1: Full external battery** on the N-hop-converged compiler (measurement compiler stated explicitly): golden 9/9 + matrix 21/21 run byte-identity; corpus 419+new-dirs sweep zero-asymmetric; upgraded-examples goldens + net round-trips; mingw32 `-osw` cross as the final step (0 new warnings, POST ⊆ PRE); warning sets POST ⊆ PRE; compat audit greps POST ≤ PRE.
- [ ] **Step 2: Measurement:** self-emission total line + byte count and gcc Row E (3× median wall/RSS) vs the Task-1 baseline; report deltas.
- [ ] **Step 3: N-hop determinism (gate A)** from the committed seed v5; record the chain and confirm gn==gn+1 ≤4 hops.
- [ ] **Step 4: STOP-present the operator-ruled re-baseline:** all four 4-MD5 rows → new values (runtime-identical per the battery), fixed point → new value, Task-7 docs-GATE plan. Await operator approval before Task 7.

---

### Task 7: Docs GATE + seed rotation v5→v6 (F, after operator approval)

**Files:**
- Modify: `docs/sf/QUICK_REF.md` (4 gate-table rows + one newest-first bullet above the Post-LIROPTPASS bullet), `release/seed/CHANGELOG.md`, `release/seed/zig1-seed.tgz` (rotated)
- Verify (no edit expected): `repro/mi_matrix/EXPECTED_FAIL.md` (v76 — bump only if fixture movement occurred; the new repro dirs classify OK/GREEN so no RED row changes)
- Report: `.superpowers/sdd/task-EMITCOMPACT-report.md` (appended `## Task 7`)
- Commit: `docs: GATE — emission-core compaction re-baseline + seed rotation (EMITCOMPACT)`

- [ ] **Step 1: Rotate the seed v5→v6** via `bash scripts/seed/archive_seed.sh <fixed-point-binary> <fresh-gen-dir> release/seed/zig1-seed.tgz --update-changelog`; verify archive md5 == CHANGELOG row, internal binary == the operator-approved fixed point, layout intact, 0 spill.
- [ ] **Step 2: Docs edits** — QUICK_REF gate-table rows to the operator-approved 4-MD5s + newest-first bullet (emission line/byte + Row E deltas, corpus + repro-pin facts, fixed point, seed v6); EXPECTED_FAIL bump only if warranted.
- [ ] **Step 3: Commit** the docs-GATE set (exactly the 3-4 files); pre-existing dirty set never staged.
- [ ] **Step 4: Report + ledger close**, then STOP-present the plan close for operator sign-off.

---

## Next-up items (NOT tasks of this plan — spec §7, kept so they aren't forgotten)

- **Stdlib growth** (usability): grow the 4-file / 389-line stdlib (string/io/math/debug modules); stdlib in Z98 exercises + pins shipped features.
- **C89-ahead features:** `volatile` (HW/MMIO), `static` function-local/file-scope, `do…while`, type-alias (`const T = u32`). Skip `goto`/`long double`/preprocessor; no method syntax / named `anytype`.
- **Semantic optimization** (cross-BB/CFG/inlining/loop): deferred as too risky.
- **LIROPTPASS record Minors for triage:** `lower.zig:1526` latent wide-enum-switch panic; two test `EnumPayload` constructors missing `.explicit_backing`; layout-B enum flag spurious; width-32+ admission-cap reliance.
