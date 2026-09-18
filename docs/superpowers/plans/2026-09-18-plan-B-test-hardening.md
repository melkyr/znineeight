# Z98 std-lib Plan B test hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the runtime gate to the Plan B (L3 + L6) modules, harden the harness with the three Important items carried from Plan A's final review, and add the Plan B stress/adversarial and expected-failure fixtures.

**Architecture:** One plan, five tasks, no `sf/src` change (fixed point UNMOVED, no seed rotation). Task 1 hardens the harness (capture mode + broadened discovery + gcc/link diagnostics) and re-verifies the 68 existing goldens. Task 2 captures the Plan B goldens as Plan B's modules land. Task 3 adds the Plan B expected-failure probes. Task 4 adds the Plan B stress tier. Task 5 is the closeout + the Plan C hardening pointer.

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), bash, `gcc -m32`, git.

**Spec:** `docs/superpowers/specs/2026-09-18-std-lib-test-hardening-design.md`.

**Sequence:** PREVIOUS plan: [`2026-09-18-plan-A-test-hardening.md`](2026-09-18-plan-A-test-hardening.md) (L0-L2 hardening). NEXT plan: [`2026-09-17-std-lib-plan-b-resources-stream.md`](2026-09-17-std-lib-plan-b-resources-stream.md) (L3 + L6) — this hardening plan executes **alongside/after** Plan B's modules land (its Tasks 2-4 need the Plan B fixtures to exist); Task 1 (the harness hardening) runs before/independent of Plan B.

## Global Constraints

- **Baseline (re-verify at Task 1).** Record HEAD, the self-compile fixed point, the seed version/archive md5, the corpus `EXPECTED_FAIL.md` header. Expected at authoring: HEAD `438e0de9`; fixed point `414cccee639bdb61c7a9f1f2ddddb166`; seed v29 archive md5 `910a4d673f0fa95f8473c08e143ceb54`; corpus 770 = 717 OK / 28 GREEN / 25 FAIL; runtime gate 68/68.
- **No `sf/src` change.** The fixed point MUST stay at Plan B's baseline (recorded at Task 1). If it moves, STOP.
- **Build only via the seed model.** Never invoke `zig0`. Binding gcc flag-set; `timeout 120`.
- **Determinism (R6):** every fixture's stdout must be identical across 3 runs and equal to its committed `expected.txt`.
- **No silent skips:** every discovered std fixture MUST have a committed golden + be in `scripts/stdlib/expected_dirs.txt`.
- **A found bug is not fixed in place:** STOP and report a separate I/F pair.
- **Fixture naming contract (binding, closes the carried finding):** Plan B std fixtures are named `repro/mi_matrix/stdlib_<module>_<name>_xmod/` (the `_xmod` suffix); workflow fixtures live under `stdlib_test/`.
- **Edits only via `edit`/`fastedit`**; never stage `mnemoria/` or `.zig1_*.tmp`; declare every residual gap.

---

## File Structure

**Modify (harness — Task 1, folds in the 3 carried Important items):**
- `scripts/stdlib/run_fixtures.sh` — add a `--capture` mode; broaden the discovery filter to any `stdlib_*` dir (or add an "unpinned std-looking dir" guard); echo the gcc/link diagnostics on failure.
- `scripts/stdlib/expected_dirs.txt` — regenerated from the broadened discovery.
- `docs/sf/QUICK_REF.md` — document `--capture` + the naming contract.

**Create (Plan B goldens):** `expected.txt`/`expected.rc` for every Plan B fixture (the `std_file`/`std_stdin`/`std_net`-UDP/`std_stream` unit fixtures + the `stdlib_test/*` workflow fixtures).

**Create (Plan B expected-failure probes):** `repro/mi_matrix/stdlib_<module>_<name>_trap_xmod/` or `_err_xmod` for the Plan B failure paths (e.g. a `std_file` open-failure, a `std_stream` EOF/partial-line case, a `std_net` UDP timeout) with declared `expected.rc`/`expected.txt`.

**Create (Plan B stress tier):**
- `repro/mi_matrix/stdlib_file_stress_xmod/` — large read/write/seek round-trips, binary data with `\r\n\0`, EOF boundaries.
- `repro/mi_matrix/stdlib_stdin_stress_xmod/` — long lines, EOF without a trailing newline, buffer-overflow boundary.
- `repro/mi_matrix/stdlib_net_udp_stress_xmod/` — loopback send/recv at max datagram, zero-length, truncation.
- `repro/mi_matrix/stdlib_stream_stress_xmod/` — a long line stream, no trailing newline, empty source, interleaved readers.

**Modify (closeout):** `repro/mi_matrix/EXPECTED_FAIL.md` (bump once), `docs/sf/QUICK_REF.md` (counts).

**Reference (read-only):** the Plan B plan + its spec, the hardening spec, `docs/sf/QUICK_REF.md`.

---

### Task 1: Harness hardening (the 3 carried Important items) + 68-golden re-verify

**Files:**
- Modify: `scripts/stdlib/run_fixtures.sh`, `scripts/stdlib/expected_dirs.txt`, `docs/sf/QUICK_REF.md`

**Interfaces:**
- Consumes: the Plan A harness.
- Produces: a `--capture` mode; a broadened discovery filter; gcc/link diagnostics on failure.

- [ ] **Step 1: Record the baseline** (HEAD; the fixed point via a fresh seed build; the seed md5; the EXPECTED_FAIL header; the runtime gate 68/68).
- [ ] **Step 2: Add `--capture` mode** — `run_fixtures.sh --capture <zig1> [dirs...]` writes the observed stdout+rc to each fixture's `expected.txt`/`expected.rc` (and prints what it wrote), with a guard that refuses to capture for a fixture whose program rc is unexpected (so a crashing fixture is not silently frozen). Document the "review the observed output against the documented GREEN contract before committing a capture" rule in the header + QUICK_REF.
- [ ] **Step 3: Broaden discovery** — replace the hardcoded `_xmod` filter with `^repro/mi_matrix/stdlib_[^/]*/$` (any `stdlib_*` dir), regenerate `expected_dirs.txt`, and add a cheap guard that fails if a `stdlib_*` dir exists but is not in the pin.
- [ ] **Step 4: Surface gcc/link diagnostics** — on `GCCFAIL`/`BUILD-RC`, echo the first line of `.gccerr`/`.builderr`.
- [ ] **Step 5: Re-verify** the 68 existing goldens still PASS after the refactor; confirm the fixed point is UNMOVED. Commit (`refactor(stdlib): capture mode + broadened discovery + diagnostics (Plan B hardening Task 1)`).

---

### Task 2: Capture the Plan B goldens

**Files:**
- Create: `expected.txt`/`expected.rc` for every Plan B fixture; modify `scripts/stdlib/expected_dirs.txt`.

**Interfaces:**
- Consumes: Task 1's `--capture`.
- Produces: the Plan B runtime goldens.

- [ ] **Step 1: For each Plan B std fixture** (the `std_file`/`std_stdin`/`std_net`-UDP/`std_stream` unit fixtures + the `stdlib_test/*` workflows), confirm the observed output matches the fixture's documented GREEN contract, then capture via `--capture`.
- [ ] **Step 2: Update `expected_dirs.txt`** with the new dirs (regenerate via the broadened discovery).
- [ ] **Step 3: Run the full gate**; confirm every fixture PASSes.
- [ ] **Step 4: Confirm the fixed point is UNMOVED**; commit (`test(stdlib): capture Plan B runtime goldens (Plan B hardening Task 2)`).

---

### Task 3: Plan B expected-failure probes

**Files:**
- Create: the Plan B probe fixtures + goldens; modify `scripts/stdlib/expected_dirs.txt`.

**Interfaces:**
- Consumes: the harness + the golden convention.
- Produces: the Plan B failure-path assertions.

- [ ] **Step 1: Add probes** for the Plan B failure paths — e.g. a `std_file` open-failure (`FileError`), a `std_stream` EOF/partial-line case, a `std_net` UDP timeout — each with a declared `expected.rc`/`expected.txt` (a single-failure-per-process probe where the path aborts/exits).
- [ ] **Step 2: Update `expected_dirs.txt`**; run the full gate; confirm the probes assert their expected failure.
- [ ] **Step 3: Confirm the fixed point is UNMOVED**; commit (`test(stdlib): add the Plan B expected-failure probes (Plan B hardening Task 3)`).

---

### Task 4: Plan B stress / adversarial tier

**Files:**
- Create: `repro/mi_matrix/stdlib_{file,stdin,net_udp,stream}_stress_xmod/` + goldens; modify `scripts/stdlib/expected_dirs.txt`.

**Interfaces:**
- Consumes: the harness + the golden convention.
- Produces: the Plan B stress tier.

- [ ] **Step 1: `stdlib_file_stress_xmod`** — large read/write/seek round-trips; binary data with `\r\n\0`; EOF boundaries.
- [ ] **Step 2: `stdlib_stdin_stress_xmod`** — long lines; EOF without a trailing newline; the buffer-overflow boundary.
- [ ] **Step 3: `stdlib_net_udp_stress_xmod`** — loopback send/recv at the max datagram; zero-length; truncation behavior (with a `ports.txt` if it binds a fixed port).
- [ ] **Step 4: `stdlib_stream_stress_xmod`** — a long line stream; no trailing newline; empty source; interleaved readers.
- [ ] **Step 5: Update `expected_dirs.txt`**; run the full gate; confirm PASS + 3× determinism.
- [ ] **Step 6: Confirm the fixed point is UNMOVED**; commit (`test(stdlib): add the Plan B stress/adversarial tier (Plan B hardening Task 4)`).

---

### Task 5: Closeout + next-plan pointer

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (bump once), `docs/sf/QUICK_REF.md`.

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: the Plan C hardening pointer.

- [ ] **Step 1: Run the full closeout:** the corpus count/classes, the runtime gate (all Plan B fixtures), `check_emit_support.sh`, the self-compile, `CLOSEOUT OK`.
- [ ] **Step 2: Bump `EXPECTED_FAIL.md`** once with a Plan B hardening section (the new fixtures, the golden convention, the fixed point, the seed).
- [ ] **Step 3: Update `QUICK_REF.md`** counts (the pinned dir count).
- [ ] **Step 4: Record the next-plan pointer:**

```markdown
## Next plan
Plan B hardening complete. NEXT: author `docs/superpowers/plans/2026-09-18-plan-C-test-hardening.md`
(L4/L5 goldens + stress tier), then execute `docs/superpowers/plans/2026-09-17-std-lib-plan-c-data-codecs.md`.
```

- [ ] **Step 5: Commit** (`chore(stdlib): Plan B hardening closeout (Plan B hardening Task 5)`).

---

## Self-Review

- **Spec coverage:** spec §2 (the runtime gate) → Tasks 1-2; §3 (the stress tier + expected-failure pins) → Tasks 3-4; §4 (the sequence) → the `Sequence:` line + Task 5 Step 4; §5 (the conventions) → the Global Constraints; the 3 carried Important items → Task 1 Steps 2-4.
- **Placeholder scan:** every step names concrete files + the observable result.
- **Type consistency:** the `--capture` CLI, the `expected.txt`/`expected.rc` convention, and the `scripts/stdlib/*` paths are used identically across tasks.
