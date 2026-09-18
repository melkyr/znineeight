# Z98 std-lib Plan B test hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the runtime gate to the Plan B (L3 + L6) modules, harden the harness with the three Important items carried from Plan A's final review, and add the Plan B stress/adversarial and expected-failure fixtures.

**Architecture:** One plan, six tasks, no `sf/src` change except Task 5a-F (the operator-ruled I/F fix; the fixed point is UNMOVED through Tasks 1-4 + 5a-I, MOVED by 5a-F, and the seed rotates at 5a-F). Task 1 hardens the harness (capture mode + broadened discovery + gcc/link diagnostics) and re-verifies the existing goldens. Task 2 verifies the Plan B goldens (already captured with Plan B). Task 3 adds the one missing Plan B expected-failure probe. Task 4 adds the Plan B stress tier. Task 5a-I/5a-F pin and fix the exact-multiple long-line defect. Task 5 is the closeout + the Plan C hardening pointer.

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), bash, `gcc -m32`, git.

**Spec:** `docs/superpowers/specs/2026-09-18-std-lib-test-hardening-design.md`.

**Sequence:** PREVIOUS plan: [`2026-09-18-plan-A-test-hardening.md`](2026-09-18-plan-A-test-hardening.md) (L0-L2 hardening). Plan B ([`2026-09-17-std-lib-plan-b-resources-stream.md`](2026-09-17-std-lib-plan-b-resources-stream.md), L3 + L6) has **landed** (its fixtures + goldens exist; the runtime gate is 106/106), so this hardening plan executes **after** it. Task 1 (the harness hardening) is the primary remaining work; Task 2 verifies the already-landed goldens; Task 3 fills the one missing probe; Task 4 adds the stress tier; Task 5a-I/5a-F pin and fix the exact-multiple long-line defect (the operator-ruled I/F pair); Task 5 is the closeout.

## Global Constraints

- **Baseline (re-verify at Task 1).** Record HEAD, the self-compile fixed point, the seed version/archive md5, the corpus `EXPECTED_FAIL.md` header. Expected at execution (refreshed after Plan B landed): HEAD `796f20d3`; fixed point `414cccee639bdb61c7a9f1f2ddddb166`; seed v29 archive md5 `910a4d673f0fa95f8473c08e143ceb54`; corpus 803; `EXPECTED_FAIL.md` v141; runtime gate 101/101 (pin 101).
- **No `sf/src` change — EXCEPT Task 5a-F** (the operator-ruled I/F fix for the exact-multiple long-line defect). Tasks 1-4 + 5a-I MUST leave the fixed point at Plan B's baseline (recorded at Task 1); Task 5a-F moves it by design. If it moves anywhere else, STOP.
- **Build only via the seed model.** Never invoke `zig0`. Binding gcc flag-set; `timeout 120`.
- **Determinism (R6):** every fixture's stdout must be identical across 3 runs and equal to its committed `expected.txt`.
- **No silent skips:** every discovered std fixture MUST have a committed golden + be in `scripts/stdlib/expected_dirs.txt`.
- **A found bug is not fixed in place:** STOP and report a separate I/F pair (the exact-multiple long-line defect found in Task 4 became Task 5a-I/5a-F).
- **Fixture naming contract (binding, closes the carried finding):** Plan B std fixtures are named `repro/mi_matrix/stdlib_<module>_<name>_xmod/` (the `_xmod` suffix); workflow fixtures live under `stdlib_test/`.
- **Edits only via `edit`/`fastedit`**; never stage `mnemoria/` or `.zig1_*.tmp`; declare every residual gap.

---

## File Structure

**Modify (harness — Task 1, folds in the 3 carried Important items):**
- `scripts/stdlib/run_fixtures.sh` — add a `--capture` mode; broaden the discovery filter to any `stdlib_*` dir (or add an "unpinned std-looking dir" guard); echo the gcc/link diagnostics on failure.
- `scripts/stdlib/expected_dirs.txt` — regenerated from the broadened discovery.
- `docs/sf/QUICK_REF.md` — document `--capture` + the naming contract.

**Verify (Plan B goldens — already landed with Plan B):** `expected.txt`/`expected.rc` for every Plan B fixture (the `std_file`/`std_stdin`/`std_net`-UDP/`std_stream` unit fixtures + the `stdlib_test/*` workflow fixtures).

**Create (the one missing Plan B expected-failure probe):** `repro/mi_matrix/stdlib_file_openerr_xmod/` for the `std_file` open-failure (`FileError.OpenFailed`) with a declared `expected.rc`/`expected.txt`. (The other Plan B probes already exist: `stdlib_stdin_readerr_xmod`, `stdlib_net_udp_settimeout_xmod`, `stdlib_stream_readline_noeof_xmod`.)

**Create (Plan B stress tier):**
- `repro/mi_matrix/stdlib_file_stress_xmod/` — large read/write/seek round-trips, binary data with `\r\n\0`, EOF boundaries.
- `repro/mi_matrix/stdlib_stdin_stress_xmod/` — long lines, EOF without a trailing newline, buffer-overflow boundary.
- `repro/mi_matrix/stdlib_net_udp_stress_xmod/` — loopback send/recv at max datagram, zero-length, truncation.
- `repro/mi_matrix/stdlib_stream_stress_xmod/` — a long line stream, no trailing newline, empty source, interleaved readers.

**Create (the exact-multiple long-line pins — Task 5a-I):**
- `repro/mi_matrix/stdlib_stdin_multiple_xmod/` — a `std_stdin.readLine` exact-multiple long line (RED before Task 5a-F).
- `repro/mi_matrix/stdlib_stream_multiple_xmod/` — a `std_stream.readLineSync` exact-multiple long line (RED before Task 5a-F).

**Modify (Task 5a-F):** `sf/src/std_stdin.zig` (`readLine`), `sf/src/std_stream.zig` (`readLineSync`) — the fix (the fixed point MOVES; the seed rotates).

**Modify (closeout):** `repro/mi_matrix/EXPECTED_FAIL.md` (bump once), `docs/sf/QUICK_REF.md` (counts).

**Reference (read-only):** the Plan B plan + its spec, the hardening spec, `docs/sf/QUICK_REF.md`.

---

### Task 1: Harness hardening (the 3 carried Important items) + 101-golden re-verify

**Files:**
- Modify: `scripts/stdlib/run_fixtures.sh`, `scripts/stdlib/expected_dirs.txt`, `docs/sf/QUICK_REF.md`

**Interfaces:**
- Consumes: the Plan A harness.
- Produces: a `--capture` mode; a broadened discovery filter; gcc/link diagnostics on failure.

- [ ] **Step 1: Record the baseline** (HEAD; the fixed point via a fresh seed build; the seed md5; the EXPECTED_FAIL header; the runtime gate 101/101).
- [ ] **Step 2: Add `--capture` mode** — `run_fixtures.sh --capture <zig1> [dirs...]` writes the observed stdout+rc to each fixture's `expected.txt`/`expected.rc` (and prints what it wrote), with a guard that refuses to capture for a fixture whose program rc is unexpected (so a crashing fixture is not silently frozen). Document the "review the observed output against the documented GREEN contract before committing a capture" rule in the header + QUICK_REF.
- [ ] **Step 3: Broaden discovery** — replace the hardcoded `_xmod` filter with `^repro/mi_matrix/stdlib_[^/]*/$` (any `stdlib_*` dir), regenerate `expected_dirs.txt`, and add a cheap guard that fails if a `stdlib_*` dir exists but is not in the pin.
- [ ] **Step 4: Surface gcc/link diagnostics** — on `GCCFAIL`/`BUILD-RC`, echo the first line of `.gccerr`/`.builderr`.
- [ ] **Step 5: Re-verify** the 101 existing goldens still PASS after the refactor; confirm the fixed point is UNMOVED. Commit (`refactor(stdlib): capture mode + broadened discovery + diagnostics (Plan B hardening Task 1)`).

---

### Task 2: Verify the Plan B goldens (already captured with Plan B)

**Files:**
- Verify: `expected.txt`/`expected.rc` for every Plan B fixture; `scripts/stdlib/expected_dirs.txt`.

**Interfaces:**
- Consumes: Task 1's `--capture` (for any re-capture).
- Produces: confirmation that the Plan B runtime goldens are present + correct.

**Status at Task 2 start:** the Plan B goldens already landed with Plan B
(the runtime gate is 101/101), so this task is a **verification**, not a
capture. Only re-capture via `--capture` if a fixture's observed output
disagrees with its documented GREEN contract.

- [ ] **Step 1: For each Plan B std fixture** (the `std_file`/`std_stdin`/`std_net`-UDP/`std_stream` unit fixtures + the `stdlib_test/*` workflows), confirm a committed `expected.txt`/`expected.rc` exists and its content matches the fixture's documented GREEN contract.
- [ ] **Step 2: Confirm every Plan B dir is in `expected_dirs.txt`** (regenerate via the broadened discovery and diff).
- [ ] **Step 3: Run the full gate**; confirm every fixture PASSes.
- [ ] **Step 4: Confirm the fixed point is UNMOVED**; commit (`test(stdlib): verify Plan B runtime goldens (Plan B hardening Task 2)`).

---

### Task 3: Plan B expected-failure probes

**Files:**
- Create: the missing Plan B probe fixture + golden; modify `scripts/stdlib/expected_dirs.txt`.

**Interfaces:**
- Consumes: the harness + the golden convention.
- Produces: the Plan B failure-path assertions.

**Status at Task 3 start:** most Plan B probes already landed with Plan B —
`stdlib_stdin_readerr_xmod` (the read-error -> `error.Io` mapping),
`stdlib_net_udp_settimeout_xmod` (asserts `error.Timeout`), and
`stdlib_stream_readline_noeof_xmod` (the EOF / partial-line path). The only
gap is the `std_file` open-failure (`FileError`) probe.

- [ ] **Step 1: Add the `std_file` open-failure probe** (`repro/mi_matrix/stdlib_file_openerr_xmod/`) — opening a nonexistent path yields `FileError.OpenFailed`; assert it, with a declared `expected.rc`/`expected.txt` (a single-failure-per-process probe).
- [ ] **Step 2: Confirm the three existing Plan B probes are present + in the pin**; update `expected_dirs.txt`; run the full gate; confirm the probes assert their expected failure.
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

### Task 5a-I: Pin the exact-multiple long-line defect (I)

**Files:**
- Create: `repro/mi_matrix/stdlib_stdin_multiple_xmod/`, `repro/mi_matrix/stdlib_stream_multiple_xmod/` (+ their `expected.txt`/`expected.rc`); modify `scripts/stdlib/expected_dirs.txt`, `repro/mi_matrix/EXPECTED_FAIL.md`.

**Interfaces:**
- Consumes: the harness + the golden convention.
- Produces: RED pins for the exact-multiple long-line defect.

**Context (operator ruling m1568/m1569):** Plan B hardening Task 4 found that an exact-multiple long line (`len % buf.len == 0`) makes both `std_stdin.readLine` (`sf/src/std_stdin.zig:99-122`) and `std_stream.readLineSync` (`sf/src/std_stream.zig:95-104,152-162`) emit a spurious empty line (a 4-byte buffer over `"abcd\nz\n"` -> `[abcd] [] [z]`). The operator ruled: declare + pin + fix as a separate I/F pair, BEFORE the Task 5 closeout.

- [ ] **Step 1: Add the RED pins** — `stdlib_stdin_multiple_xmod` and `stdlib_stream_multiple_xmod`, each reading an exact-multiple long line and asserting the exact expected lines (the current behaviour emits the spurious empty line, so the assert traps -> RED).
- [ ] **Step 2: Clarify the contract** (blueprint §3 L3/L6 + the hardening spec) for the exact-multiple boundary (currently only the "longer than buf" case is specified).
- [ ] **Step 3: Declare the defect** in `EXPECTED_FAIL.md`; update `expected_dirs.txt`; record the RED (a runtime assert trap).
- [ ] **Step 4: Commit** (`test(stdlib): pin the exact-multiple long-line defect (Plan B hardening Task 5a-I)`). No `sf/src` change; the fixed point stays UNMOVED for this task.

---

### Task 5a-F: Fix the exact-multiple long-line defect (F)

**Files:**
- Modify: `sf/src/std_stdin.zig` (`readLine`), `sf/src/std_stream.zig` (`readLineSync`); the Task 5a-I fixtures + goldens.

**Interfaces:**
- Consumes: the Task 5a-I RED pins.
- Produces: the fix; the fixed point MOVES; the seed rotates.

- [ ] **Step 1: Fix `std_stdin.readLine`** so a line whose length is an exact multiple of `buf.len` does not emit a trailing empty line.
- [ ] **Step 2: Fix `std_stream.readLineSync`** the same way.
- [ ] **Step 3: Flip the Task 5a-I pins RED -> GREEN**; re-capture their goldens; run the full gate; confirm 3× determinism.
- [ ] **Step 4: Re-verify the gates** (`check_emit_support.sh` 7/7; the self-compile; the corpus class map; `CLOSEOUT OK`); confirm the fixed point MOVED.
- [ ] **Step 5: Rotate the seed** (`bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`) and commit (`fix(std): no spurious empty line for an exact-multiple long line (Plan B hardening Task 5a-F)`).

---

### Task 5: Closeout + next-plan pointer

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (bump once), `docs/sf/QUICK_REF.md`.

**Interfaces:**
- Consumes: Tasks 1-4 + 5a-I/5a-F.
- Produces: the Plan C hardening pointer.

- [ ] **Step 1: Run the full closeout** on the Task 5a-F seed-rotated compiler: the corpus count/classes, the runtime gate (all Plan B fixtures), `check_emit_support.sh`, the self-compile, `CLOSEOUT OK`.
- [ ] **Step 2: Bump `EXPECTED_FAIL.md`** once with a Plan B hardening section (the new fixtures, the golden convention, the new fixed point, the rotated seed).
- [ ] **Step 3: Update `QUICK_REF.md`** counts (the pinned dir count; the seed version/md5; the fixed point).
- [ ] **Step 4: Record the next-plan pointer:**

```markdown
## Next plan
Plan B hardening complete. NEXT: author `docs/superpowers/plans/2026-09-18-plan-C-test-hardening.md`
(L4/L5 goldens + stress tier), then execute `docs/superpowers/plans/2026-09-17-std-lib-plan-c-data-codecs.md`.
```

- [ ] **Step 5: Commit** (`chore(stdlib): Plan B hardening closeout (Plan B hardening Task 5)`).

---

## Self-Review

- **Spec coverage:** spec §2 (the runtime gate) → Tasks 1-2; §3 (the stress tier + expected-failure pins) → Tasks 3-4; the found exact-multiple long-line defect → Task 5a-I/5a-F (the operator-ruled I/F pair); §4 (the sequence) → the `Sequence:` line + Task 5 Step 4; §5 (the conventions) → the Global Constraints; the 3 carried Important items → Task 1 Steps 2-4.
- **Fixed point:** Tasks 1-4 + 5a-I leave it UNMOVED; Task 5a-F MOVES it (an `sf/src` fix) and rotates the seed; Task 5 re-verifies the rotated seed.
- **Placeholder scan:** every step names concrete files + the observable result.
- **Type consistency:** the `--capture` CLI, the `expected.txt`/`expected.rc` convention, and the `scripts/stdlib/*` paths are used identically across tasks.
