# zig1 Live-Set Reduction — Research Spike Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** census every allocation and every zig0-era workaround/boxing in the `sf/src` closure,
rank the **RSS** savings each could return, and hand the operator a ranked table to rule on —
**no compiler fixes are committed by this plan**.

**Architecture:** read-only allocation census + seed-probe workaround re-evaluation on the seed
compiler; the spike's output is two census tables + a ranked savings roll-up.

**Tech Stack:** the seed model (`release/seed/`, `scripts/seed/build_from_seed.sh`), the
`--markers` `arena <name>: grew` stream, `--track-memory`, `/usr/bin/time -v`, the
`repro/mi_matrix` corpus and its goldens.

**Spec:** `docs/superpowers/specs/2026-10-06-zig1-live-set-reduction-design.md` (the plan argues
from the spec; executors read both).

## Global Constraints

- **Seed model (binding).** Reference compiler rebuilt per the seed model; current seed **v92**
  (archive md5 `3cacdd44df75c0ce96abfd51af93f928`; archived binary fixed point
  `d40e875a7ba3aa55d441af56006f6023`). `sf/src` now includes the L3 fix, so the forward build is:
  `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/liveset_seed`
  (NO `FIXED_POINT_MD5` pin) and the gate is `hop1 == hop2` at the current HEAD's fixed point.
- **Metric (binding).** Peak **RSS** of the self-compile run (`/usr/bin/time -v` Maximum resident
  set size), median of ≥3 interleaved samples. `pool`/`total`/per-arena carve are context only.
  Self-compile command: `-s0 --markers --track-memory -o <fresh-dir> sf/src/main.zig`
  (CWD = repo root, RELATIVE `sf/src/main.zig`; pre-create the output dir). Per-arena carve =
  sum of `arena <name>: grew <old> -> <new>` `new` values (`sf/src/allocator.zig:193`).
- **This is a spike.** No `sf/src` fixes, no seed rotation, no dump-MD5 re-baseline. The only
  committed artifacts are this plan, the spec, and the reports. Any measurement instrumentation is
  throwaway and must not be committed.
- **Editing:** `edit`/`fastedit` only, and only if a throwaway probe is unavoidable; re-read the
  region before each edit; edit bottom-to-top.
- **Compression is FORBIDDEN during build sessions.** No push. `timeout 120` per step; aggregate
  gates (corpus classify, `verify_stdlib`, `verify_upgraded`) `timeout 600`.
- Reports go under `.superpowers/sdd/2026-10-06-zig1-live-set-reduction-plan/`.

---

### Task 0: Baseline + metric freeze (READ-ONLY)

**Files:** Report: `.superpowers/sdd/2026-10-06-zig1-live-set-reduction-plan/task-0-report.md`.

- [ ] **Step 1:** Build the seed per Global Constraints; record the resulting binary path + md5 and
  the `hop1 == hop2` fixed point.
- [ ] **Step 2:** Self-compile at `-s0` ×3 interleaved; record the `track-memory` line, the
  `/usr/bin/time -v` RSS (median) / wall, and the `.c`/`.h` counts.
- [ ] **Step 3:** Extract every `arena <name>: grew` line; sum `new` per arena; record the
  per-arena carve table and Σ (must ≈ `pool`).
- [ ] **Step 4:** Freeze the equivalence baseline: 8/8 dump-MD5 pins, corpus classify tally, stdlib
  266/0, examples 24/24, runtime goldens gol/lisp/json/mud.
- [ ] **Step 5:** Record the documented Win98 idle floor range and state that the concrete target is
  deferred to the operator's ruling on Task 3's savings table.
- [ ] **Step 6:** Write the report and commit `docs: live-set reduction plan — Task 0 baseline`.

### Task 1: Allocation-savings census (READ-ONLY)

**Files:** Report: `.superpowers/sdd/2026-10-06-zig1-live-set-reduction-plan/task-1-report.md`;
census: `.superpowers/sdd/2026-10-06-zig1-live-set-reduction-plan/allocation-census.md`.

- [ ] **Step 1:** Enumerate every allocation entry point in the closure (`sandAlloc`,
  `u32ArrayListEnsureCapacity`/`...Append`, `growableSandInit`, `*ArrayList` boxes, `SpillStore`
  opens, inline `[N]` buffer fields). Record the total site count.
- [ ] **Step 2:** For each site build the per-site row (spec §Workstream 1): file:line; owning
  arena/lifetime; object + count at self-compile; per-object overhead (arena pad/header);
  alloc+copy redundancy; over-sizing; live-vs-dead.
- [ ] **Step 3:** For the highest-value rows, compute the expected **touched-RSS** drop from the
  Task 0 `arena grew` trace (only touched pages raise RSS; cite the L3 lesson).
- [ ] **Step 4:** Produce a shortlist of save-allocation candidates with byte estimates and risk;
  write the census table + report and commit.

### Task 2: zig0-workaround / boxing re-evaluation (READ-ONLY)

**Files:** Report: `.superpowers/sdd/2026-10-06-zig1-live-set-reduction-plan/task-2-report.md`;
census: `.superpowers/sdd/2026-10-06-zig1-live-set-reduction-plan/workaround-census.md`.

- [ ] **Step 1:** Enumerate the `AGENTS.md` §1.3 Z98-limitation workarounds, any `zig0`/bootstrap
  named comments in the closure, and pointer-boxing sites (`*T` fields where an inline `T` might
  replace the indirection).
- [ ] **Step 2:** For each candidate, write a tiny seed probe and compile it with the seed to test
  whether the direct construct is now accepted (flagship: the `sf/src/token.zig:131` packed
  `Token` 24 B→16 B FIXME; PACK-AGG has since landed).
- [ ] **Step 3:** Classify each: still-blocked / now-removable / removable-with-caveat; estimate
  the byte delta and risk (emitted-text/markers observable?). For boxing sites, record the actual
  arena header/pad cost.
- [ ] **Step 4:** Write the workaround/boxing table + report and commit.

### Task 3: Savings roll-up (READ-ONLY) — SPIKE TERMINAL

**Files:** Report: `.superpowers/sdd/2026-10-06-zig1-live-set-reduction-plan/task-3-report.md`.

- [ ] **Step 1:** Merge Tasks 1–2 into one ranked table, ordered by expected **touched-RSS** drop,
  each row carrying: mechanism, files/sites, measured/estimated bytes, risk, effort, and the gate
  that would prove it.
- [ ] **Step 2:** List rejected and deferred levers with the disconfirming number (including the
  deferred out-of-scope workstreams).
- [ ] **Step 3:** Write the roll-up and commit `docs: live-set reduction — savings census + roll-up`.
  **STOP.** Present the ranked savings for the operator's ruling. **No fixes. No imposed
  recommendation. No fixed target.** The operator decides which levers to fund.

---

## Prospective fixes (OUT OF SCOPE unless the operator rules on Task 3)

These are **not** tasks of this spike. After the operator rules, a separate fix plan is authored,
one task per confirmed lever, each `measure → implement (edit/fastedit) → corpus+goldens+stdlib+
examples+dump-MD5 battery → record RSS delta (median ≥3) → commit`. Illustrative shapes only:

- **F-ALLOC-*** remove alloc+copy redundancy / over-sizing / retained-after-last-read found by
  Task 1.
- **F-TOKEN** restore the 16 B packed `Token` once the seed accepts it (Task 2 flagship).
- **F-WORKAROUND-*** replace now-removable zig0-era workarounds with the direct construct.
- **F-BOX-*** inline a `*T` field where the indirection no longer earns its bytes.

## Closeout

- Final report under `.superpowers/sdd/2026-10-06-zig1-live-set-reduction-plan/`; commit docs only.
  No compiler code changed, no seed rotated, no dump-MD5 re-baselined.
