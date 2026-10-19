# z9torr M6 — Seed & Upload — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** make z9torr **seed** — accept inbound peers (plaintext + MSE/PE), serve verified pieces from disk, broadcast `have`, and announce as a completed seeder — so it is a full BitTorrent participant, not a leecher.

**Architecture:** add one inbound listener task (non-blocking `accept`, yields on `WouldBlock`) that spawns a seeder coroutine per inbound connection, reusing the existing `Peer`/`wire`/`mse`/scheduler code. The `Peer` coroutine gains an inbound branch: handshake responder (plaintext + MSE), then a serving loop (`bitfield` -> `interested`/`unchoke` -> `request`/`piece` -> `have`). Tracker gains completed-seeder semantics; `--max-up` bounds outgoing piece bytes.

**Tech Stack:** Z98 (`zig1` -> C89, `gcc -m32`), `std_crypto` (SHA-1/RC4/modpow), `std_net` (TCP/select), POSIX `sh` + Python 3.11 test tooling, `aria2c` (optional leecher reference).

**Spec:** `docs/superpowers/specs/2026-10-11-z9torr-m6-seed-upload-design.md` (binding).

**Sequence:** PREVIOUS: `docs/superpowers/plans/2026-10-08-z9torr-m5-win9x-plan.md`. NEXT (deferred arms): tit-for-tat choking; DHT `announce_peer` + PEX sending; Win9x inbound.

## Global Constraints

- **No compiler changes** (frozen); `sf/src/**` untouched. **No seed rotation** in this milestone.
- **Example-only edits** under `examples/z98/z9torr/`. Free functions; no generics/`anytype`/`@Type`; strict `@intCast`; every `switch` needs `else`; keep suspension discipline: no module-global across a suspension and no struct-return temp across a suspension. The compiler is seed v102 (old D1–D8 numbering retired; see `examples/torrent_example_defects.md`); if a new defect shape appears, STOP-present and record it. `edit`/`fastedit` only (re-read region before each edit; bottom-to-top; INSERT = replace anchor line with `[new content + original anchor line]`).
- Build: seed **v102** (archive md5 `702f34d87b7e6bf401dd206d2517dbee`, fixed point `b299b4b435e624d0ddbd2edde681cbc3`); rebuild `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9_m6_seed`; build the example `mkdir -p <out>; timeout 120 /tmp/z9_m6_seed/zig1_5_clean -fsafe -o <out> examples/z98/z9torr/main.zig; sh <out>/build_target.sh linux <out>/prog`.
- All **16 existing tiers** must stay green under `-fsafe` (`tier1`, `tier1_cli`, `tier1_unit`, `tier2`, `tier3_encrypted`, `tier_udp_tracker`, `tier_dht`, `tier_pex`, `tier_stall`, `tier_fallback`, `tier_refseed`, `tier_refseed_py`, `tier_mse_diag`, `tier_integrity`, `tier_safe`, `tier4_wine`).
- **NO push. No compression during the build session.** Reports under `.superpowers/sdd/2026-10-11-z9torr-m6-seed-upload-plan/` (commit via `git add -f`).
- **GIT HARD RULE:** no `git reset --hard/--keep`, `git checkout --`, `git restore`, `git clean`, `git stash drop/clear`, force-push, or history rewriting; only `git commit --amend` on your OWN just-created commit. STOP and report otherwise.
- **The plan is the only authority.** A -> do A; if X/Y better, STOP-present. STOP on any issue or unforeseen divergence.

---

### Task 0: Preflight — listen path + reusable inventory + baseline

**Files:** Report `task-0-report.md`

- [ ] **Step 1:** Confirm the client currently advertises port `6881` (handshake + tracker) **without** binding it (`main.zig`; no `bindListen`/`accept` in the example).
- [ ] **Step 2:** Inventory `wire.zig` encoders present vs needed by the seeder; confirm which `*Enc` (encrypted) writers exist and which must be added (expected missing: encrypted `bitfield`, `have`, `unchoke`, `piece`).
- [ ] **Step 3:** Confirm signatures: `std_net.bindListen`/`accept`/`select`, `disk.readPiece`, `tracker.announce` (`event`/`left`/`uploaded`), `Stats.uploaded`, `scheduler.firstInactiveSlot`-equivalent, `AnnounceEvent`.
- [ ] **Step 4:** Run the full 16-tier baseline under `-fsafe` (`ZIG=/tmp/z9_m6_seed/zig1_5_clean`) and record the counts + seed closure.

**Gate:** baseline all green; a concrete list of new encoders/handlers to add. No code change.

---

### Task 1: Inbound listener + accept coroutine + plaintext responder

**Files:** Modify `examples/z98/z9torr/peer.zig`, `examples/z98/z9torr/main.zig`, `examples/z98/z9torr/scheduler.zig` (if a slot helper is needed); Create `examples/z98/z9torr/tests/mock_leecher.zig`, `examples/z98/z9torr/tests/tier_seed.sh` (skeleton); Report `task-1-report.md`

**Interfaces:**
- Consumes: `std_net.bindListen`/`accept`; the scheduler slot machinery (`MAX_RUNTIME_PEERS`); `wire.readHandshake`/`writeHandshake`.
- Produces: a listener task bound to the (CLI-overridable) listen port; a non-blocking `accept` that yields on `WouldBlock`; a per-inbound seeder coroutine; the handshake advertises the **bound** port.

- [ ] **Step 1: Red.** A plaintext leecher mock cannot connect to z9torr today (no listener). Write `tests/mock_leecher.zig` (outbound plaintext peer that connects to a given `host:port`, does the handshake, and requests pieces) and a `tier_seed.sh` skeleton asserting it can connect.
- [ ] **Step 2: Implement.** Bind a listen socket; add a non-blocking accept loop (yield on `WouldBlock`); claim a free slot and spawn a seeder coroutine per connection; add the plaintext handshake-responder branch (read/validate 68 bytes + send ours); advertise the bound port in handshake + tracker `port=`.
- [ ] **Step 3: Green.** The leecher connects and the plaintext handshake completes (both directions).
- [ ] **Step 4: Battery.** All 16 tiers green; commit.

**Gate:** inbound plaintext handshake completes; no tier regression.

---

### Task 2: MSE inbound (responder role) + encrypted seeder encoders

**Files:** Modify `examples/z98/z9torr/mse.zig`, `examples/z98/z9torr/wire.zig`, `examples/z98/z9torr/peer.zig`; Report `task-2-report.md`

**Interfaces:**
- Consumes: `std_crypto` DH/RC4/SHA-1; the server-side references `tools/mock_mse_peer.zig` and `tests/mse_ref.py`.
- Produces: `mseAccept(...)` (responder: `Ya`->`Yb`, `S`, `keyA`/`keyB`, verify `req1`, `req2xor`, `ENCRYPT_B(VC|select|padD)`); encrypted outbound encoders `writeBitfieldEnc`/`writeHaveEnc`/`writeUnchokeEnc`/`writePieceEnc`.

- [ ] **Step 1: Red.** An MSE leecher mock can complete a handshake but z9torr cannot respond (no responder).
- [ ] **Step 2: Implement** the MSE responder (mirror `mseConnect`) and the missing encrypted encoders.
- [ ] **Step 3: Green.** The MSE leecher mock completes the encrypted handshake with z9torr; the existing `tier3_encrypted`/`tier_mse_diag` stay green.
- [ ] **Step 4: Battery**; commit.

**Gate:** inbound MSE handshake completes; mock/diagnostic tiers green.

---

### Task 3: Seeder peer loop (serve pieces, `have`, minimal choke)

**Files:** Modify `examples/z98/z9torr/peer.zig`, `examples/z98/z9torr/piece.zig`, `examples/z98/z9torr/scheduler.zig`; Modify `tests/tier_seed.sh`; Report `task-3-report.md`

**Interfaces:**
- Consumes: `disk.readPiece`; `wire.writeBitfield`/`writeUnchoke`/`writePiece`/`writeHave` (+ `*Enc`); `Stats.uploaded`.
- Produces: on connect send `bitfield`; `interested`->`unchoke`; `request`->read block from disk->`writePiece` (+ upload stat + rate limit); broadcast `have` as pieces verify; minimal choke set (unchoke all / first K); keep-alive.

- [ ] **Step 1: Red.** The leecher connects/handshakes but receives no pieces (no serving loop).
- [ ] **Step 2: Implement** the seeder serving loop (plaintext and encrypted paths).
- [ ] **Step 3: Green.** The leecher downloads a **byte-verified** payload from z9torr and `Stats.uploaded` increases; suspension discipline held.
- [ ] **Step 4: Battery**; commit.

**Gate:** verifiable upload to a leecher (plaintext + MSE).

---

### Task 4: Tracker-as-seeder + upload rate limit

**Files:** Modify `examples/z98/z9torr/tracker.zig`, `examples/z98/z9torr/udp_tracker.zig`, `examples/z98/z9torr/main.zig`; Report `task-4-report.md`

**Interfaces:**
- Produces: `AnnounceEvent.stopped` + BEP 15 code map (`1=completed, 2=started, 3=stopped`); announce `event=completed`/`left=0` when complete; periodic re-announce at `interval`; `event=stopped` on exit (best-effort); `--max-up` bounds outgoing piece bytes.

- [ ] **Step 1:** Extend `AnnounceEvent` + the BEP 15 map; wire completed/`left=0` and `stopped`.
- [ ] **Step 2:** Route outgoing piece bytes through the `--max-up` token bucket.
- [ ] **Step 3: Battery** (verify a throttled upload still completes within budget); commit.

**Gate:** announces `completed`/`left=0`; `stopped` best-effort; `--max-up` throttles upload.

---

### Task 5: Tests + docs + closeout

**Files:** Modify `examples/z98/z9torr/tests/tier_seed.sh`, `examples/z98/z9torr/tools/mock_leecher.zig`, `examples/z98/z9torr/NOTES.md`, `examples/z98/z9torr/README.md`, the M6 spec/plan; Report `task-5-report.md`

- [ ] **Step 1:** Finalize `tests/tier_seed.sh`: inbound leecher (plaintext + MSE) downloads a byte-verified payload from a z9torr seeder; assert the leecher SHA-1 and `Stats.uploaded > 0`. Optionally an `aria2c`-as-leecher loopback run (best-effort, SKIP-with-reason offline).
- [ ] **Step 2:** All 16 existing tiers green; record `--dump-c89` md5.
- [ ] **Step 3:** Update `NOTES.md`/`README.md`/spec/plan status to M6 done; state NEXT = deferred arms.
- [ ] **Step 4: Commit** `example(z9torr): M6 seed & upload closeout`.

**Gate:** seed tier green (plaintext + MSE); all tiers green; docs consistent.

## Self-Review
- **Spec coverage:** §4.1->T1, §4.2->T1/T2, §4.3->T3, §4.4->T4, §4.5->T1/T3, §5->T5, §6 risks mirrored by gates.
- **Order:** listener (T1) before MSE-inbound (T2) before the serving loop (T3); tracker/rate (T4); tests/closeout (T5).
- **No placeholders:** the reusable encoders/functions, file paths, build recipe and gates are concrete; the only open item is the listening-socket integration detail resolved in T1.
