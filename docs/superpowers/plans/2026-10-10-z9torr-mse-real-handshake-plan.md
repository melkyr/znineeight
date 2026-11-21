# z9torr M4.1 — Real MSE/PE Handshake Debugging — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** DONE (2026-10-10) — all tasks complete. Compiler/seed unchanged (seed
v96, closure `46e3e7af98af3b5ff2a960c7c96025e3`). Closeout commit
`example(z9torr): M4.1 real-handshake closeout`. NEXT: resume z9torr M4 polish
(relax unknown reserved bits per BEP 3), then M5 (Win9x).

**Goal:** make z9torr complete a real MSE/PE encrypted handshake and download, proven against two independent reference peers (aria2c + a pure-Python MSE responder) and then best-effort against the live swarm.

**Architecture:** Stage diagnostics → stand up the two reference peers locally (loopback) → localize the MSE divergence → fix → make the connect+MSE probe non-blocking → fix the plaintext fallback → retest.

**Tech Stack:** Z98 (`zig1` → C89, `gcc -m32`), `std_crypto` (SHA-1/RC4/modpow), POSIX `sh` + Python 3.11 (stdlib) test tooling, Debian `.deb` extraction for aria2c (no root).

**Spec:** `docs/superpowers/specs/2026-10-10-z9torr-mse-real-handshake-design.md` (binding).

**Sequence:** PREVIOUS: `docs/superpowers/plans/2026-10-09-zig1-codegen-defects-plan.md`. NEXT: resume z9torr M4 polish, then M5 Win9x.

## Global Constraints

- **No compiler changes** (post-D1–D5 freeze); `sf/src/**` untouched. **No seed rotation** in this milestone.
- **Example-only edits** under `examples/z98/z9torr/`. Free functions, no generics/`anytype`/`@Type`, strict `@intCast`, every `switch` needs `else`, D1/D2/D3/D4 rules. `edit`/`fastedit` only (re-read region before each edit; bottom-to-top; INSERT = replace anchor line with `[new content + original anchor line]`).
- Build recipe: `mkdir -p <out>; timeout 120 /tmp/z9_m41_seed/zig1_5_clean -ffast -o <out> examples/z98/z9torr/main.zig; sh <out>/build_target.sh linux <out>/prog` (compiler = the post-D1–D5 + F6 seed closure `46e3e7af98af3b5ff2a960c7c96025e3`, i.e. seed v96; rebuild with `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9_m41_seed` if absent). F6 changed only `-fsafe` output; z9torr builds `-ffast`, so the example is unaffected.)
- Existing tiers must stay green: `tests/tier1.sh`, `tier1_cli.sh`, `tier2.sh`, `tier1_unit.sh`, `tier3_encrypted.sh`, `tier_udp_tracker.sh`, `tier_dht.sh`, `tier_pex.sh`.
- **NO push. No compression during the build session.** Reports under `.superpowers/sdd/2026-10-10-z9torr-mse-real-handshake-plan/` (commit via `git add -f`).
- **GIT HARD RULE:** no `git reset --hard/--keep`, `git checkout --`, `git restore`, `git clean`, `git stash drop/clear`, force-push, or history rewriting; only `git commit --amend` on your OWN just-created commit. STOP and report otherwise.
- **The plan is the only authority.** A → do A; if X/Y better, STOP-present. STOP on any issue or unforeseen divergence.

---

### Task 0: Stage the reference peers + baseline

**Files:** Create `examples/z98/z9torr/tests/get_aria2.sh`, `examples/z98/z9torr/tests/mse_ref.py` (skeleton); Report `task-0-report.md`

- [x] **Step 1: aria2 acquisition helper.** `tests/get_aria2.sh`: create a writable apt state/cache under `$TMP`, `apt-get update` + `apt-get install --download-only --no-install-recommends -y aria2` (with `Dir::State::status` redirected, no root), `dpkg-deb -x` all debs into a prefix, print the `aria2c` path + required `LD_LIBRARY_PATH`. Gate: `aria2c --version` prints `aria2 version 1.36.0` (or newer) via the helper.
- [x] **Step 2: Python MSE reference skeleton.** `tests/mse_ref.py` — stdlib-only: SHA1 (`hashlib`), RC4, 768-bit DH (`pow`), and the MSE responder byte layout (`Yb`, `HASH('req1'|S)`, req2xor check, `ENCRYPT_B(VC‖crypto_select‖padD)`, `ENCRYPT_B(payload)`). Also a `--selftest` that round-trips against itself.
- [x] **Step 3: Baseline.** Build z9torr with the fixed compiler; run the existing 8 tiers; record the counts + the compiler closure md5. Stage the extracted aria2 under a stable `$TMP` path.

**Gate:** `get_aria2.sh` yields a runnable `aria2c`; `mse_ref.py --selftest` passes; baseline tiers green.

---

### Task 1: MSE stage diagnostics + localize

**Files:** Modify `examples/z98/z9torr/mse.zig` (env-gated stage logging); Create `examples/z98/z9torr/tests/tier_mse_diag.sh`; Report `task-1-report.md`

- [x] **Step 1: Stage logging.** Add env-gated (`Z9TORR_LOG`) records in `mseConnect`: `Ya` sent (96B), bytes read for `Yb`, whether the `VC` sync matched, the received `crypto_select`, the `padD` length, and the exact failing stage/error.
- [x] **Step 2: Observe against BOTH references** (and the mock): run z9torr against `mock_mse_peer` (must succeed — control), then against the aria2c seeder and the Python responder; capture the stage trace at the divergence.
- [x] **Step 3: Localize.** Determine the first divergent step (our bytes vs the reference's expectation). Compare our initiator stream (`Ya`, `req1`, `req2xor`, encrypted `VC‖provide`) against the Python reference byte-for-byte.
- [x] **Step 4: Report + commit.** `git commit -m "test(z9torr): MSE stage diagnostics + reference peers (diag harness)"`.

**Gate:** a captured trace localizes the first divergence (or proves z9torr’s stream matches the reference and the fault is elsewhere). No fix yet.

---

### Task 2: Real-seed tiers

**Files:** Create `examples/z98/z9torr/tests/tier_refseed.sh` (aria2c), `examples/z98/z9torr/tests/tier_refseed_py.sh` (Python); Report `task-2-report.md`

- [x] **Step 1: aria2c tier.** Start `aria2c` as a forced-encryption seeder for a local single-file torrent; start `mock_tracker` advertising `127.0.0.1:<aria2 port>`; run z9torr; assert a byte-verified completed download. SKIP-with-reason if `get_aria2.sh` cannot produce a runnable `aria2c`.
- [x] **Step 2: Python tier.** Same with `mse_ref.py` as the seeder/responder.
- [x] **Step 3: Commit** `test(z9torr): hermetic real-seed tiers (aria2c + python MSE responder)`.

**Gate:** both tiers drive a real encrypted download (or aria2 tier SKIPs with a reason); non-vacuous.

---

### Task 3: Fix the MSE handshake (per Task 1 findings)

**Files:** Modify `examples/z98/z9torr/mse.zig` (and `wire.zig`/`peer.zig` if the divergence is there); Report `task-3-report.md`

- [x] **Step 1: Red** — the reference-seed tier(s) fail against the un-fixed client. **Step 2: Fix** the localized divergence (byte layout / DH / req / RC4 key / VC sync / crypto negotiation — per Task 1). **Step 3: Green** — both reference tiers complete an encrypted download; the `mock_mse_peer` tier still green.
- [x] **Step 4: Battery** — all existing tiers green; `--dump-c89` md5 recorded (example-only change; the compiler is unchanged).
- [x] **Step 5: Commit** `fix(z9torr): correct the MSE handshake against reference peers`.

**Gate:** reference tiers green; all prior tiers green.

---

### Task 4: Non-blocking connect + MSE probe

**Files:** Modify `examples/z98/z9torr/peer.zig` (and `mse.zig` if needed); Report `task-4-report.md`

- [x] **Step 1:** Make the TCP connect + MSE probe coroutine-aware (yield on `WouldBlock`; bounded deadline) so one slow peer cannot freeze the scheduler.
- [x] **Step 2:** Verify with a many-peers scenario (mocks + one dead peer) that other peers make progress while one is stalled; keep the D3/D4 discipline.
- [x] **Step 3: Battery** (all tiers) + **Step 4: Commit** `perf(z9torr): non-blocking connect + MSE probe`.

**Gate:** no tier regression; a stalled peer no longer serializes the swarm.

---

### Task 5: Fallback policy + fix + live retest + closeout

**Files:** Modify `examples/z98/z9torr/peer.zig` (+ spec/plan/docs); Report `task-5-report.md`

- [x] **Step 1:** Decide + implement encrypted-first-reconnect vs detect-first for mixed swarms (operator-ruled); make the plaintext fallback actually succeed against a plaintext-only peer.
- [x] **Step 2:** Rebuild `lin_bin/` and run a **best-effort** live Debian retest; report the outcome honestly (peers, connects, handshakes, bytes).
- [x] **Step 3:** All tiers green; update `NOTES.md`/`README.md`/spec/plan status.
- [x] **Step 4: Commit** `example(z9torr): M4.1 real-handshake closeout`; state next = resume M4 polish then M5.

**Gate:** reference + mock tiers green; live retest reported; docs consistent.

## Self-Review
- **Spec coverage:** §3.1→T1, §3.2→T0/T2, §3.3→T4, §3.4→T5; both references (§3.2) covered by T2/T0.
- **No placeholders:** acquisition method, reference layout, gate commands and file paths are concrete; the only open item (TODO: fix locus) is T1’s explicit deliverable.
- **Order:** diagnostics (T1) before fix (T3); reference peers (T0/T2) before the fix gate.
