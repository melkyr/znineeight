# Z98 std-lib Plan C test hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the runtime gate to the Plan C (L4 + L5) modules, capture their runtime goldens, and add the L4/L5 stress/adversarial and expected-failure tiers.

**Architecture:** One plan, five tasks, no `sf/src` change (fixed point UNMOVED, no seed rotation). Task 1 re-verifies the harness (the three carried Important items landed with the Plan B hardening) and records the baseline. Task 2 captures the Plan C runtime goldens (one per public function, once Plan C has landed). Task 3 adds the Plan C expected-failure probes. Task 4 adds the Plan C stress tier. Task 5 is the closeout + the program-completion pointer.

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), bash, `gcc -m32`, git.

**Spec:** `docs/superpowers/specs/2026-09-18-std-lib-test-hardening-design.md`.

**Sequence:** PREVIOUS plan: [`2026-09-18-plan-B-test-hardening.md`](2026-09-18-plan-B-test-hardening.md) (L3 + L6 hardening). This plan executes **after** Plan C ([`2026-09-17-std-lib-plan-c-data-codecs.md`](2026-09-17-std-lib-plan-c-data-codecs.md), L4 + L5) has **landed** (its modules + fixtures exist and the runtime gate is green). It is the **last** hardening plan; after it the std-lib extension program is complete.

## Global Constraints

- **Precondition:** Plan B hardening + Plan C complete.
- **Baseline (record at Task 1).** Record HEAD, the self-compile fixed point, the seed version/archive md5, the corpus count, the corpus `EXPECTED_FAIL.md` header, and the runtime gate count (dirs + PASS/FAIL). Expected at execution: the Plan C closeout baseline (to be filled in from the actual closeout).
- **No `sf/src` change.** The fixed point MUST stay at the Plan C baseline (recorded at Task 1). If it moves, STOP.
- **Build only via the seed model.** Never invoke `zig0`. Binding gcc flag-set (`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`); `timeout 120` on every binary.
- **Determinism (R6):** every fixture's stdout must be identical across 3 runs and equal to its committed `expected.txt`.
- **No silent skips:** every discovered std fixture MUST have a committed golden (`expected.txt` + `expected.rc`) and be in `scripts/stdlib/expected_dirs.txt`.
- **A found bug is not fixed in place:** STOP and report a separate I/F pair (as Plan A's Tasks 4b/6b and the Plan B Task 5a I/F pair did).
- **Fixture naming contract:** Plan C std fixtures are named `repro/mi_matrix/stdlib_<module>_<name>_xmod/` (the `_xmod` suffix); workflow fixtures live under `stdlib_test/`.
- **Crypto vectors:** the RFC/FIPS normative KATs (RFC 3174 SHA-1, FIPS 180-4 SHA-256, RFC 1321 MD5, IEEE 802.3 CRC-32) are pinned by Plan C's fixtures; this hardening re-verifies them through the runtime gate (they are already deterministic and golden-stable).
- **Edits only via `edit`/`fastedit`**; never stage `mnemoria/` or `.zig1_*.tmp`; declare every residual gap.

---

## File Structure

**Verify (harness — Task 1, the Plan B hardening already landed the three carried Important items):**
- `scripts/stdlib/run_fixtures.sh` — the `--capture` mode, the broadened discovery (`^repro/mi_matrix/stdlib_[^/]*/$` + the `stdlib_test/[^/]*/$` alternative), the always-on unpinned-stdlib-dir guard, and the gcc/link first-line diagnostics.
- `scripts/stdlib/verify_stdlib.sh`, `scripts/stdlib/expected_dirs.txt`.

**Create (the Plan C runtime goldens — Task 2):** `expected.txt` + `expected.rc` for every Plan C fixture:
- `stdlib_crypto_*_xmod/` (KATs; streaming-vs-one-shot equality; empty input).
- `stdlib_parse_*_xmod/` (valid/invalid tables; round-trips; overflow boundaries).
- `stdlib_map_*_xmod/` (collision stress; string-key lifetime; iteration-order determinism).
- `stdlib_sort_*_xmod/` (random, sorted, reverse-sorted, duplicates; search on each).
- `stdlib_heap_*_xmod/` (push/pop ordering; tie stability; empty pop).
- `stdlib_rle_*_xmod/` (random/constant/alternating/empty).
- `stdlib_base64_*_xmod/`, `stdlib_hex_*_xmod/` (RFC 4648 vectors; whitespace rejection; round-trips).
- `stdlib_utf8_*_xmod/` (valid multi-byte; invalid continuation; overlong rejection).

**Create (the Plan C expected-failure probes — Task 3):**
- `stdlib_parse_invalid_xmod/` — a malformed numeric input yields `null` (a single-failure-per-process probe with a declared `expected.rc`/`expected.txt`).
- `stdlib_base64_invalid_xmod/` — a non-alphabet input byte is rejected.
- `stdlib_utf8_invalid_xmod/` — an invalid continuation byte / overlong sequence is rejected.
- `stdlib_map_oom_xmod/`, `stdlib_heap_oom_xmod/` — an arena-exhaustion `OutOfMemory` with the arena untouched.

**Create (the Plan C stress tier — Task 4):**
- `stdlib_map_stress_xmod/`, `stdlib_sort_stress_xmod/`, `stdlib_heap_stress_xmod/`, `stdlib_rle_stress_xmod/`, `stdlib_crypto_stress_xmod/`, `stdlib_parse_stress_xmod/`, `stdlib_base64_stress_xmod/`, `stdlib_hex_stress_xmod/`, `stdlib_utf8_stress_xmod/` — hand-written tables, NO PRNG.

**Modify (closeout):** `repro/mi_matrix/EXPECTED_FAIL.md` (bump once), `docs/sf/QUICK_REF.md` (counts).

**Reference (read-only):** the Plan C plan + its spec, the hardening spec, `docs/sf/QUICK_REF.md`.

---

### Task 1: Re-verify the harness + record the baseline

**Files:**
- Verify: `scripts/stdlib/run_fixtures.sh`, `scripts/stdlib/verify_stdlib.sh`, `scripts/stdlib/expected_dirs.txt`.

**Interfaces:**
- Consumes: the Plan B hardening harness.
- Produces: the recorded baseline; confirmation the three carried Important items are in place.

- [ ] **Step 1: Record the baseline** (HEAD; the fixed point via a fresh seed build; the seed version/archive md5; the corpus count + `EXPECTED_FAIL.md` header; the runtime gate count).
- [ ] **Step 2: Confirm the harness carries the three carried Important items** — the `--capture` mode, the broadened discovery filter + the unpinned-stdlib-dir guard, and the gcc/link first-line diagnostics. If any is missing, STOP (do not re-implement).
- [ ] **Step 3: Run the full gate** on a fresh seed build; confirm every existing fixture PASSes and the pin set-equality holds.
- [ ] **Step 4: Confirm the fixed point is UNMOVED**; no commit (this task is a verification).

---

### Task 2: Capture the Plan C runtime goldens

**Files:**
- Create: `expected.txt` + `expected.rc` for every Plan C fixture (the `stdlib_<planC module>_*_xmod` dirs); modify `scripts/stdlib/expected_dirs.txt`.

**Interfaces:**
- Consumes: Task 1's harness + the golden convention.
- Produces: the Plan C runtime goldens.

**Status at Task 2 start:** Plan C has landed (its fixtures exist), so this is a **capture + review**, not an implementation. Use `run_fixtures.sh --capture` to write each fixture's observed stdout/rc, then **review every captured output against the fixture's documented GREEN contract before committing** (do not freeze an unexpected output).

- [ ] **Step 1: For each Plan C fixture**, confirm a committed `expected.txt`/`expected.rc` exists and its content matches the fixture's documented GREEN contract; capture any missing golden with `--capture` and review it.
- [ ] **Step 2: Confirm every Plan C dir is in `expected_dirs.txt`** (regenerate via the broadened discovery and diff).
- [ ] **Step 3: Run the full gate**; confirm every fixture PASSes.
- [ ] **Step 4: Confirm the fixed point is UNMOVED**; commit (`test(stdlib): capture the Plan C runtime goldens (Plan C hardening Task 2)`).

---

### Task 3: Plan C expected-failure probes

**Files:**
- Create: the Plan C probe fixtures + goldens; modify `scripts/stdlib/expected_dirs.txt`.

**Interfaces:**
- Consumes: the harness + the golden convention.
- Produces: the Plan C failure-path assertions.

- [ ] **Step 1: Add the probe fixtures** — `stdlib_parse_invalid_xmod` (malformed input → `null`), `stdlib_base64_invalid_xmod` (non-alphabet input rejected), `stdlib_utf8_invalid_xmod` (invalid continuation / overlong rejected), `stdlib_map_oom_xmod` + `stdlib_heap_oom_xmod` (arena exhaustion → `OutOfMemory`, the arena untouched). Each ships a declared `expected.txt`/`expected.rc` (a single-failure-per-process probe).
- [ ] **Step 2: Confirm each probe asserts its expected failure**; update `expected_dirs.txt`; run the full gate.
- [ ] **Step 3: Confirm the fixed point is UNMOVED**; commit (`test(stdlib): add the Plan C expected-failure probes (Plan C hardening Task 3)`).

---

### Task 4: Plan C stress / adversarial tier

**Files:**
- Create: `repro/mi_matrix/stdlib_{map,sort,heap,rle,crypto,parse,base64,hex,utf8}_stress_xmod/` + goldens; modify `scripts/stdlib/expected_dirs.txt`.

**Interfaces:**
- Consumes: the harness + the golden convention.
- Produces: the Plan C stress tier.

- [ ] **Step 1: `stdlib_map_stress_xmod`** — many puts across growth; heavy collisions; string-key lifetime; deterministic iteration order over a large key set.
- [ ] **Step 2: `stdlib_sort_stress_xmod`** — large random/sorted/reverse-sorted/duplicate arrays; `binarySearchU32` on each.
- [ ] **Step 3: `stdlib_heap_stress_xmod`** — many pushes/pops; tie stability; the empty-pop boundary.
- [ ] **Step 4: `stdlib_rle_stress_xmod`** — long runs, alternating bytes, the empty input, and `encodedLen`/`decodedLen` agreement.
- [ ] **Step 5: `stdlib_crypto_stress_xmod`** — the RFC/FIPS KATs plus streaming-vs-one-shot equality over many chunk splittings and the empty input.
- [ ] **Step 6: `stdlib_parse_stress_xmod`** — valid/invalid tables, round-trips, the i64/u64 overflow boundaries, `itoa`/`utoa`/`ftoa` buffer-end writes.
- [ ] **Step 7: `stdlib_base64_stress_xmod` + `stdlib_hex_stress_xmod`** — RFC 4648 vectors, whitespace rejection, encoder∘decoder round-trips over adversarial lengths.
- [ ] **Step 8: `stdlib_utf8_stress_xmod`** — valid multi-byte sequences, invalid continuations, overlong rejections, `countCodepoints` over a mixed input.
- [ ] **Step 9: Update `expected_dirs.txt`**; run the full gate; confirm PASS + 3× determinism.
- [ ] **Step 10: Confirm the fixed point is UNMOVED**; commit (`test(stdlib): add the Plan C stress/adversarial tier (Plan C hardening Task 4)`).

---

### Task 5: Closeout + program-completion pointer

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (bump once), `docs/sf/QUICK_REF.md`.

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: the program-completion pointer.

- [ ] **Step 1: Run the full closeout:** the corpus count/classes, the runtime gate (all Plan C fixtures), `check_emit_support.sh`, the self-compile, `CLOSEOUT OK`.
- [ ] **Step 2: Bump `EXPECTED_FAIL.md`** once with a Plan C hardening section (the new fixtures, the golden convention, the fixed point, the seed).
- [ ] **Step 3: Update `QUICK_REF.md`** counts (the pinned dir count).
- [ ] **Step 4: Record the program-completion pointer:**

```markdown
## Next plan
Plan C hardening complete. The std-lib extension program is COMPLETE.
No successor plan. Program spec: `docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md`.
```

- [ ] **Step 5: Commit** (`chore(stdlib): Plan C hardening closeout — L4/L5 goldens + stress tier; program complete`).

---

## Self-Review

- **Spec coverage:** spec §2 (the runtime gate) → Tasks 1-2; §3 (the stress tier + expected-failure pins) → Tasks 3-4; §4 (the sequence) → the `Sequence:` line + Task 5 Step 4; §5 (the conventions) → the Global Constraints; §6 (the risks) → the determinism/crypto constraints.
- **Placeholder scan:** every step names concrete files + the observable result. The baseline values are marked "to be filled in from the actual closeout" because this plan is written before Plan C executes.
- **Type consistency:** the `--capture` CLI, the `expected.txt`/`expected.rc` convention, the `scripts/stdlib/*` paths, and the `stdlib_<module>_<name>_xmod` naming are used identically across tasks and match the Plan B hardening plan.
