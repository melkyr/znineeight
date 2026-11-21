# Z98 std-lib Plan A test hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Plan A's std-module runtime behavior an automated gate — a harness that builds+links+runs every `stdlib_*`/`stdlib_test/*` fixture and diffs stdout+rc against committed per-fixture goldens — and add the Plan A stress/adversarial and missing expected-failure fixtures.

**Architecture:** One plan, five tasks, no `sf/src` change (fixed point UNMOVED, no seed rotation). Task 1 builds the runtime-gate harness `scripts/stdlib/run_fixtures.sh` and smoke-tests it. Task 2 captures the Plan A goldens (`expected.txt`/`expected.rc`) and wires the gate into the closeout. Task 3 adds the missing expected-failure probe fixtures. Task 4 adds the Plan A stress/adversarial tables. Task 5 is the closeout + the Plan B hardening pointer.

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), bash, `gcc -m32`, git.

**Spec:** `docs/superpowers/specs/2026-09-18-std-lib-test-hardening-design.md`.

**Sequence:** PREVIOUS plan: [`2026-09-17-std-lib-plan-a-foundation.md`](2026-09-17-std-lib-plan-a-foundation.md) (L0-L2 foundation). NEXT plan: [`2026-09-17-std-lib-plan-b-resources-stream.md`](2026-09-17-std-lib-plan-b-resources-stream.md) (L3 + L6) — with a `plan-B-test-hardening.md` written before it executes.

## Global Constraints

- **Baseline (re-verify at Task 1).** Record HEAD, the self-compile fixed point, the seed version/archive md5, the corpus `EXPECTED_FAIL.md` header. Expected at authoring: HEAD `8cc04678`; fixed point `414cccee639bdb61c7a9f1f2ddddb166`; seed v29 archive md5 `910a4d673f0fa95f8473c08e143ceb54`; corpus 763 = 710 OK / 28 GREEN / 25 FAIL.
- **No `sf/src` change.** The fixed point MUST stay `414cccee…`. If it moves, STOP (a source edit leaked in).
- **Build only via the seed model:** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <fresh_out>`. **Never invoke `zig0`.**
- **gcc flag-set (binding):** `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`. `timeout 120` on every binary.
- **Determinism (R6):** every fixture's stdout must be identical across 3 runs and equal to its committed `expected.txt`; no addresses/wall-clock/PID dependence.
- **No silent skips:** every discovered `stdlib_*`/`stdlib_test/*` fixture MUST have a committed golden, or the harness fails.
- **A found bug is not fixed in place:** if a hardening task uncovers a real compiler/std defect, STOP and report it as a separate I/F pair (as Plan A's Task 4b/6b did).
- **Edits only via `edit`/`fastedit`** (re-read the region immediately before each edit; edit bottom-to-top for multiple edits in one file).
- **Never stage** `mnemoria/` or `.zig1_*.tmp`.
- **Declare every residual gap.**

---

## File Structure

**Create (harness):**
- `scripts/stdlib/run_fixtures.sh` — the runtime-gate harness (discovery, build/link/run, golden diff, 3× determinism).
- `scripts/stdlib/verify_stdlib.sh` — the closeout entry that calls the harness over the std fixture set (or the harness itself, if it is already closeout-shaped).

**Create (goldens):** `repro/mi_matrix/<dir>/expected.txt` + `expected.rc` for every Plan A fixture (the `stdlib_bits_*`, `stdlib_os_*`, `stdlib_time_*`, `stdlib_debug_*`, `stdlib_buf_*`, `stdlib_str_*` dirs) and `stdlib_test/bits_buf_str_usage`, `stdlib_test/os_time_usage`.

**Create (missing expected-failure probes):**
- `repro/mi_matrix/stdlib_bits_trap_xmod/` — `extract`/`insert` out-of-range offsets trap (expected rc).
- `repro/mi_matrix/stdlib_os_exit_xmod/` — `std_os.exit(N)` yields rc N.

**Create (Plan A stress tables):**
- `repro/mi_matrix/stdlib_bits_stress_xmod/` — a hand-written `insert∘extract` / rotate-inverse sweep over many field layouts + widths.
- `repro/mi_matrix/stdlib_buf_stress_xmod/` — many appends across many doublings; every encoder round-tripped by a matching decode; max-size within the arena.
- `repro/mi_matrix/stdlib_str_stress_xmod/` — adversarial separators/whitespace/empties; `join∘split` identity; `replace` aliasing; long inputs.
- `repro/mi_matrix/stdlib_debug_stress_xmod/` — `writeCoreDump`/`backtrace` at scale (a deep call chain), `logInt` boundaries.

**Modify (closeout):**
- `scripts/closeout/verify_upgraded.sh` — invoke the stdlib runtime gate (a new phase) or call `scripts/stdlib/verify_stdlib.sh`.
- `docs/sf/QUICK_REF.md` — document the harness CLI + the golden convention.
- `repro/mi_matrix/EXPECTED_FAIL.md` — bump once at closeout (record the hardening + the new fixtures).

**Reference (read-only):** the Plan A spec/plan, `docs/sf/QUICK_REF.md`, `docs/sf/AGENTS.md`.

---

### Task 1: Runtime-gate harness + smoke run

**Files:**
- Create: `scripts/stdlib/run_fixtures.sh`
- Read: `scripts/corpus/list_corpus_dirs.sh` (the `emit_dir` resolution), `scripts/corpus/classify` (the build/run recipe), `docs/sf/QUICK_REF.md`

**Interfaces:**
- Consumes: a seed-built `zig1_5_clean`.
- Produces: `run_fixtures.sh <zig1> [<dir>...]` — for each fixture dir, builds+links+runs and reports PASS/FAIL against `<dir>/expected.txt` + `expected.rc`; exits nonzero on any mismatch or missing golden.

- [ ] **Step 1: Record the baseline** (HEAD; the fixed point via a fresh seed build; the seed md5; the EXPECTED_FAIL header; the corpus count).
- [ ] **Step 2: Write the harness.** It must: discover the std fixture dirs (the `emit_dir` rule); for each, `zig1 -ffast -o <tmp> <entry>`; compile every emitted `.c` with the binding flag-set; `sh <tmp>/build_target.sh linux <prog>`; run under `timeout 120` capturing stdout+rc; run 3× and require identical stdout; diff stdout bytes to `<dir>/expected.txt` and rc to `<dir>/expected.rc`; fail on a missing golden; print a per-dir PASS/FAIL summary.
- [ ] **Step 3: Smoke-run it** over a small known set (e.g. `stdlib_bits_table_xmod`, `stdlib_str_split_alias_xmod`, `stdlib_debug_trap_xmod`) with the goldens captured by hand in the same step, and confirm PASS.
- [ ] **Step 4: Verify the gate fails correctly** — corrupt a temporary copy of one golden and confirm the harness reports FAIL + nonzero rc.
- [ ] **Step 5: Confirm the fixed point is UNMOVED** and commit (`feat(stdlib): add the runtime-gate harness (Plan A hardening Task 1)`).

---

### Task 2: Capture the Plan A goldens + wire the gate into closeout

**Files:**
- Create: `expected.txt`/`expected.rc` for every Plan A fixture (the `stdlib_bits_*`, `stdlib_os_*`, `stdlib_time_*`, `stdlib_debug_*`, `stdlib_buf_*`, `stdlib_str_*` dirs + the two `stdlib_test/*` programs).
- Create/Modify: `scripts/stdlib/verify_stdlib.sh`; `scripts/closeout/verify_upgraded.sh`; `docs/sf/QUICK_REF.md`.

**Interfaces:**
- Consumes: the Task 1 harness.
- Produces: a fully golden-covered Plan A fixture set + a closeout-invoked gate.

- [ ] **Step 1: Capture each golden** by running the harness's build/run path once per fixture and committing the observed stdout+rc (only after manually confirming the output matches the fixture's documented GREEN contract — a golden must not freeze a wrong output).
- [ ] **Step 2: Wire the gate** into the closeout (`verify_upgraded.sh` calls `verify_stdlib.sh` / the harness) so `CLOSEOUT OK` requires the runtime gate to pass.
- [ ] **Step 3: Run the full gate** over all Plan A fixtures; confirm every one PASSes (or is a declared probe with its expected rc).
- [ ] **Step 4: Document the harness CLI + the golden convention** in `docs/sf/QUICK_REF.md`.
- [ ] **Step 5: Confirm the fixed point is UNMOVED** and commit (`test(stdlib): capture Plan A runtime goldens + wire the gate (Plan A hardening Task 2)`).

---

### Task 3: Missing expected-failure probes

**Files:**
- Create: `repro/mi_matrix/stdlib_bits_trap_xmod/` (+ goldens), `repro/mi_matrix/stdlib_os_exit_xmod/` (+ goldens).
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (if the probes need a declared entry).

**Interfaces:**
- Consumes: the harness + the golden convention.
- Produces: the expected-failure assertions the Plan A fixtures lacked.

- [ ] **Step 1: `stdlib_bits_trap_xmod`** — call `bits.extract`/`bits.insert` with an out-of-range offset (`off+len > 32`) and assert the process traps (expected rc = the trap signal; empty stdout). Note: a single fixture can only trap once, so cover `extract` and `insert` in separate probe dirs or a two-process harness — state the choice.
- [ ] **Step 2: `stdlib_os_exit_xmod`** — call `std_os.exit(N)` for a chosen N and assert the process exits with rc N (empty stdout).
- [ ] **Step 3: Run the harness** over the new probes; confirm the expected rc is asserted (the gate treats a probe's `expected.rc` as the contract).
- [ ] **Step 4: Confirm the fixed point is UNMOVED** and commit (`test(stdlib): add the missing expected-failure probes (Plan A hardening Task 3)`).

---

### Task 4: Plan A stress / adversarial tables

**Files:**
- Create: `repro/mi_matrix/stdlib_bits_stress_xmod/`, `stdlib_buf_stress_xmod/`, `stdlib_str_stress_xmod/`, `stdlib_debug_stress_xmod/` (+ goldens).

**Interfaces:**
- Consumes: the harness + the golden convention.
- Produces: the hand-written stress/adversarial tier for Plan A.

- [ ] **Step 1: `stdlib_bits_stress_xmod`** — a hand-written sweep: for a table of (off, len, value) field layouts, assert `extract(insert(0, v, off, len), off, len) == v`; assert `rotr32(rotl32(x, n), n) == x` for n in a written set including 0/31/32/33; widths at the boundaries.
- [ ] **Step 2: `stdlib_buf_stress_xmod`** — append across many doublings (a written sequence to a large length); for each encoder (`appendU16/32/64BE/LE`), append then decode byte-by-byte and assert the value round-trips; fill to the arena's maximum and assert the exact-fit boundary.
- [ ] **Step 3: `stdlib_str_stress_xmod`** — adversarial separators (leading/trailing/consecutive/all-separator), empty and whitespace-only inputs, long inputs; assert `join(split(s, sep), sep) == s` for a written table; assert `replace`'s aliasing contract; `trim` over all-whitespace and mixed.
- [ ] **Step 4: `stdlib_debug_stress_xmod`** — `backtrace` over a deep hand-written call chain; `writeCoreDump` at scale; `logInt` at i32 boundaries (INT_MIN/INT_MAX/0/-1).
- [ ] **Step 5: Run the harness** over the stress fixtures; confirm PASS + 3× determinism.
- [ ] **Step 6: Confirm the fixed point is UNMOVED** and commit (`test(stdlib): add the Plan A stress/adversarial tier (Plan A hardening Task 4)`).

---

### Task 5: Closeout + next-plan pointer

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (bump once), `docs/sf/QUICK_REF.md`, `scripts/closeout/verify_upgraded.sh` (if not already).

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: the Plan B hardening pointer.

- [ ] **Step 1: Run the full closeout:** the corpus count/classes (compile gate), the runtime gate (all Plan A fixtures + probes + stress), `check_emit_support.sh`, the self-compile, `CLOSEOUT OK`.
- [ ] **Step 2: Bump `EXPECTED_FAIL.md`** once with a Plan A hardening section (the new fixtures, the golden convention, the fixed point).
- [ ] **Step 3: Update `QUICK_REF.md`** with the harness CLI + the golden convention.
- [ ] **Step 4: Record the next-plan pointer:**

```markdown
## Next plan
Plan A hardening complete. NEXT: write `docs/superpowers/plans/2026-09-18-plan-B-test-hardening.md`
(reusing this harness for the L3/L6 goldens + stress tier), then execute
`docs/superpowers/plans/2026-09-17-std-lib-plan-b-resources-stream.md`.
```

- [ ] **Step 5: Commit** (`chore(stdlib): Plan A hardening closeout (Plan A hardening Task 5)`).

---

## Self-Review

- **Spec coverage:** spec §2 (the runtime gate) → Tasks 1-2; §3 (the stress tier + expected-failure pins) → Tasks 3-4; §4 (the sequence) → the `Sequence:` line + Task 5 Step 4; §5 (the conventions) → the Global Constraints; §6 (risks) → the golden-capture discipline (Task 2 Step 1) + the probe handling (Task 3).
- **Placeholder scan:** every step names concrete files + the observable result; the goldens are captured, not invented.
- **Type consistency:** the harness CLI, the `expected.txt`/`expected.rc` convention, and the `scripts/stdlib/*` paths are used identically across tasks.
