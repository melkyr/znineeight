# Z98 std-lib Plan D test hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the runtime gate to the Plan D (L3 `std_net` non-blocking + L6 `std_stream` network readers) modules, capture their runtime goldens, and add the Plan D network/async stress/adversarial and expected-failure tiers.

**Architecture:** One plan, five tasks, no `sf/src` change (fixed point UNMOVED at the Plan D baseline, no seed rotation — the hardening adds no std module, so the archive `lib/` payload is unchanged). Task 1 re-verifies the harness and records the Plan D baseline. Task 2 captures the Plan D runtime goldens (one per public function, once Plan D has landed). Task 3 adds the Plan D expected-failure probes (the `error.WouldBlock` path, the oversized frame prefix, the peer-close boundary). Task 4 adds the Plan D network/async stress tier. Task 5 is the closeout + the program-completion pointer.

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), bash, `gcc -m32`, git.

**Spec:** `docs/superpowers/specs/2026-09-18-std-lib-test-hardening-design.md`.

**Sequence:** PREVIOUS plan: [`2026-09-18-plan-C-test-hardening.md`](2026-09-18-plan-C-test-hardening.md) (L4 + L5 hardening). This plan executes **after** Plan D ([`2026-09-18-plan-D-network-async.md`](2026-09-18-plan-D-network-async.md), the network-async capstone) has **landed** (its modules + fixtures exist and the runtime gate is green). It is the **last** hardening plan; after it the std-lib extension program is complete.

## Global Constraints

- **Precondition:** Plan C hardening + Plan D complete.
- **Baseline (record at Task 1).** Record HEAD, the self-compile fixed point, the seed version/archive md5, the corpus count, the corpus `EXPECTED_FAIL.md` header, and the runtime gate count (dirs + PASS/FAIL). Expected at execution: the Plan D closeout baseline (to be filled in from the actual closeout). Plan D's authorized `net_prelude.h` prelude change is a compiler-graph change, so the Plan D baseline fixed point is **MOVED** from the Plan C value `fc9198f6c1a24c92ec136e741c81c975` and the seed is **rotated past v39** — record the new values.
- **No `sf/src` change.** The fixed point MUST stay at the Plan D baseline (recorded at Task 1). If it moves, STOP.
- **Build only via the seed model.** Never invoke `zig0`. Binding gcc flag-set (`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`); `timeout 120` on every binary.
- **Model C (the `answerT4` ruling, binding).** Z98 is cooperative-yield: the caller drives `tick`; there is no executor and no `poll` loop. A `*Async` reader yields on `error.WouldBlock` and is re-driven next tick. The hardening fixtures must not introduce an executor or a background wakeup.
- **Network determinism (R6, binding).** Every network fixture uses **loopback only** and binds a fixed port declared in its per-dir `ports.txt`; the `WouldBlock` path is exercised deterministically (a bounded `select`/drain loop or a bounded resume count), never by wall-clock sleep. No fixture may depend on addresses, the wall clock, or the PID; the 3× gate enforces this.
- **No silent skips:** every discovered std fixture MUST have a committed golden (`expected.txt` + `expected.rc`) and be in `scripts/stdlib/expected_dirs.txt`.
- **A found bug is not fixed in place:** STOP and report a separate I/F pair (as Plan A's Tasks 4b/6b, the Plan B Task 5a I/F pair, and the Plan C Task 1b/2b/3b/4b I/F pairs did).
- **Fixture naming contract:** Plan D std fixtures are named `repro/mi_matrix/stdlib_<module>_<name>_xmod/` (the `_xmod` suffix); workflow fixtures live under `stdlib_test/`.
- **Plan D Task 4 (revised).** Plan D Task 4 is `std.async.suspendUntil(pred: fn() bool) void` (operator-revised; the original `wait(handle)` was ruled not justified under Model C). This plan covers it: the Task 4 fixture `stdlib_async_suspenduntil_xmod` (already landed with Task 4) plus a `suspendUntil` probe and stress fixture.
- **Edits only via `edit`/`fastedit`**; never stage `mnemoria/` or `.zig1_*.tmp`; declare every residual gap.

---

## File Structure

**Verify (harness — Task 1, the Plan B hardening already landed the hardening):**
- `scripts/stdlib/run_fixtures.sh` — the `--capture` mode, the broadened discovery (`^repro/mi_matrix/stdlib_[^/]*/$` + the `stdlib_test/[^/]*/$` alternative), the always-on unpinned-stdlib-dir guard, the `ports.txt` port guard, and the gcc/link first-line diagnostics.
- `scripts/stdlib/verify_stdlib.sh`, `scripts/stdlib/expected_dirs.txt`.

**Create (the Plan D runtime goldens — Task 2):** `expected.txt` + `expected.rc` for every Plan D fixture:
- `stdlib_net_setnonblocking_xmod/` — `setNonBlocking` toggles the flag; a subsequent blocking-sensitive call observes the mode.
- `stdlib_net_recvnonblocking_xmod/` — loopback: `recvNonBlocking` returns `error.WouldBlock` on an empty socket, then the byte count once data arrives, then `0` at peer close.
- `stdlib_net_sendnonblocking_xmod/` — loopback: `sendNonBlocking` delivers the bytes and reports the count.
- `stdlib_stream_socketlinereader_xmod/` — a loopback line stream; a partial line across ticks (≥2 suspends per call); the sync + async readers.
- `stdlib_stream_msgreader_xmod/` — a length-prefix frame over loopback; partial frames across ticks; back-to-back frames; the sync + async readers.
- `stdlib_test/net_stream_usage/` — the R7b workflow program composing `std_net` + `std_stream` + `std.async`.
- `stdlib_async_suspenduntil_xmod/` — the Plan D Task 4 fixture (landed with Task 4).

**Create (the Plan D expected-failure probes — Task 3):**
- `stdlib_net_recvnonblocking_wouldblock_xmod/` — `recvNonBlocking` on an idle loopback socket yields `error.WouldBlock` (asserted, declared `expected.rc`/`expected.txt`).
- `stdlib_net_recvnonblocking_close_xmod/` — `recvNonBlocking` returns `0` at peer close (the EOF boundary).
- `stdlib_stream_msgreader_oversize_xmod/` — a length prefix exceeding the reader buffer is rejected (declared `expected.rc`/`expected.txt`).
- `stdlib_async_suspenduntil_false_xmod/` — a predicate that stays false (bounded ticks): the coroutine suspends every tick and never resumes past the suspension point; the timing contract is asserted.

**Create (the Plan D stress tier — Task 4):**
- `stdlib_net_nonblocking_stress_xmod/` — a loopback drain loop over many `recvNonBlocking` calls: would-block/partial/EOF interleavings, zero-length send, maximum datagram/stream chunk.
- `stdlib_stream_socketlinereader_stress_xmod/` — a long line stream, no trailing newline, empty source, a line spanning many ticks, interleaved readers.
- `stdlib_stream_msgreader_stress_xmod/` — many back-to-back frames, a frame split across ticks, a zero-length frame, the maximum frame the buffer allows.
- `stdlib_async_suspenduntil_stress_xmod/` — many coroutines yielding on `suspendUntil`; predicate flips at varied ticks.

**Modify (closeout):** `repro/mi_matrix/EXPECTED_FAIL.md` (bump once), `docs/sf/QUICK_REF.md` (counts).

**Reference (read-only):** the Plan D plan + its spec, the hardening spec, `docs/sf/QUICK_REF.md`.

---

### Task 1: Re-verify the harness + record the Plan D baseline

**Files:**
- Verify: `scripts/stdlib/run_fixtures.sh`, `scripts/stdlib/verify_stdlib.sh`, `scripts/stdlib/expected_dirs.txt`.

**Interfaces:**
- Consumes: the Plan B hardening harness.
- Produces: the recorded Plan D baseline; confirmation the harness carries the hardening (capture mode, broadened discovery + unpinned-dir guard, `ports.txt` port guard, gcc/link diagnostics); the Plan D Task 4 (`suspendUntil`) landed status.

- [ ] **Step 1: Record the baseline** (HEAD; the fixed point via a fresh seed build; the seed version/archive md5; the corpus count + `EXPECTED_FAIL.md` header; the runtime gate count). The fixed point is MOVED from the Plan C value by Plan D's `net_prelude.h` change — record the new value.
- [ ] **Step 2: Confirm the harness carries the hardening** — `--capture`, the broadened discovery filter + the unpinned-stdlib-dir guard, the `ports.txt` port guard, and the gcc/link first-line diagnostics. If any is missing, STOP (do not re-implement).
- [ ] **Step 3: Confirm the Plan D Task 4 status** — Plan D landed `std.async.suspendUntil` (revised scope); record it; it gates the conditional fixtures in Tasks 2-4.
- [ ] **Step 4: Run the full gate** on a fresh seed build; confirm every existing fixture PASSes and the pin set-equality holds.
- [ ] **Step 5: Confirm the fixed point is UNMOVED** at the Plan D baseline; no commit (this task is a verification).

---

### Task 2: Capture the Plan D runtime goldens

**Files:**
- Create: `expected.txt` + `expected.rc` for every Plan D fixture (the `stdlib_net_{set,recv,send}nonblocking_xmod`, `stdlib_stream_{socketlinereader,msgreader}_xmod`, and `stdlib_test/net_stream_usage` dirs; plus `stdlib_async_suspenduntil_xmod`); modify `scripts/stdlib/expected_dirs.txt`.

**Interfaces:**
- Consumes: Task 1's harness + the golden convention.
- Produces: the Plan D runtime goldens.

**Status at Task 2 start:** Plan D has landed (its fixtures exist), so this is a **capture + review**, not an implementation. Use `run_fixtures.sh --capture` to write each fixture's observed stdout/rc, then **review every captured output against the fixture's documented GREEN contract before committing** (do not freeze an unexpected output).

- [ ] **Step 1: For each Plan D fixture**, confirm a committed `expected.txt`/`expected.rc` exists and its content matches the fixture's documented GREEN contract; capture any missing golden with `--capture` and review it.
- [ ] **Step 2: Confirm each Plan D network fixture ships a `ports.txt`** declaring its fixed loopback port, and that the port is not left in a LISTEN state between runs.
- [ ] **Step 3: Confirm every Plan D dir is in `expected_dirs.txt`** (regenerate via the broadened discovery and diff).
- [ ] **Step 4: Run the full gate**; confirm every fixture PASSes (3× determinism).
- [ ] **Step 5: Confirm the fixed point is UNMOVED**; commit (`test(stdlib): capture the Plan D runtime goldens (Plan D hardening Task 2)`).

---

### Task 3: Plan D expected-failure probes

**Files:**
- Create: the Plan D probe fixtures + goldens; modify `scripts/stdlib/expected_dirs.txt`.

**Interfaces:**
- Consumes: the harness + the golden convention.
- Produces: the Plan D failure-path assertions.

- [ ] **Step 1: Add the probes** — `stdlib_net_recvnonblocking_wouldblock_xmod` (an idle loopback socket → `error.WouldBlock`), `stdlib_net_recvnonblocking_close_xmod` (peer close → `0`), `stdlib_stream_msgreader_oversize_xmod` (a length prefix larger than the reader buffer is rejected), each with a declared `expected.txt`/`expected.rc` (a single-failure-per-process probe where the process traps; otherwise a deterministic rc-0 assertion line).
- [ ] **Step 2: Add the `suspendUntil` probe** — `stdlib_async_suspenduntil_false_xmod` (a predicate that stays false over a bounded tick count → the coroutine remains suspended; assert the observed resume count).
- [ ] **Step 3: Confirm each probe asserts its expected failure**; update `expected_dirs.txt`; run the full gate.
- [ ] **Step 4: Confirm the fixed point is UNMOVED**; commit (`test(stdlib): add the Plan D expected-failure probes (Plan D hardening Task 3)`).

---

### Task 4: Plan D network/async stress tier

**Files:**
- Create: `repro/mi_matrix/stdlib_{net_nonblocking,stream_socketlinereader,stream_msgreader,async_suspenduntil}_stress_xmod/` (+ goldens); modify `scripts/stdlib/expected_dirs.txt`.

**Interfaces:**
- Consumes: the harness + the golden convention.
- Produces: the Plan D stress tier.

- [ ] **Step 1: `stdlib_net_nonblocking_stress_xmod`** — a loopback drain loop over many `recvNonBlocking` calls: the would-block / partial / EOF interleavings, a zero-length send, and the maximum chunk; deterministic (bounded loop, no sleep).
- [ ] **Step 2: `stdlib_stream_socketlinereader_stress_xmod`** — a long line stream, no trailing newline, an empty source, a line spanning many ticks (≥2 suspends), and interleaved readers.
- [ ] **Step 3: `stdlib_stream_msgreader_stress_xmod`** — many back-to-back frames, a frame split across ticks, a zero-length frame, and the maximum frame the buffer allows; assert frame boundaries.
- [ ] **Step 4: `stdlib_async_suspenduntil_stress_xmod`** — many coroutines yielding on `suspendUntil`; predicate flips at varied ticks.
- [ ] **Step 5: Update `expected_dirs.txt`**; run the full gate; confirm PASS + 3× determinism.
- [ ] **Step 6: Confirm the fixed point is UNMOVED**; commit (`test(stdlib): add the Plan D stress/adversarial tier (Plan D hardening Task 4)`).

---

### Task 5: Closeout + program-completion pointer

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (bump once), `docs/sf/QUICK_REF.md`.

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: the program-completion pointer.

- [ ] **Step 1: Run the full closeout:** the corpus count/classes, the runtime gate (all Plan D fixtures), `check_emit_support.sh`, the self-compile, `CLOSEOUT OK`.
- [ ] **Step 2: Bump `EXPECTED_FAIL.md`** once with a Plan D hardening section (the new fixtures, the golden convention, the fixed point, the seed).
- [ ] **Step 3: Update `QUICK_REF.md`** counts (the pinned dir count).
- [ ] **Step 4: Record the program-completion pointer:**

```markdown
## Next plan
Plan D hardening complete. The std-lib extension program is COMPLETE.
No successor plan. Program spec: `docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md`.
```

- [ ] **Step 5: Commit** (`chore(stdlib): Plan D hardening closeout — network/async goldens + stress tier; program complete`).

---

## Self-Review

- **Spec coverage:** spec §2 (the runtime gate) → Tasks 1-2; §3 (the stress tier + expected-failure pins) → Tasks 3-4; §4 (the sequence) → the `Sequence:` line + Task 5 Step 4; §5 (the conventions) → the Global Constraints; §6 (the risks) → the network-determinism constraint + the `ports.txt` handling.
- **Placeholder scan:** every step names concrete files + the observable result. The baseline values are marked "to be filled in from the actual closeout" because this plan is written before Plan D executes.
- **Type consistency:** the `--capture` CLI, the `expected.txt`/`expected.rc` convention, the `ports.txt` port guard, the `scripts/stdlib/*` paths, and the `stdlib_<module>_<name>_xmod` naming are used identically across tasks and match the Plan C hardening plan.
