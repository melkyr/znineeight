# z9torr M4 — Real-Swarm Compatibility — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the z9torr example download from real public swarms by adding BitTorrent Protocol Encryption (MSE/PE), a UDP tracker (BEP 15), and DHT (BEP 5) + PEX (BEP 11), and fixing the all-zero `peer_id`.

**Architecture:** A per-peer crypto/encryption layer wraps the existing `wire.zig` framing (RC4 after an MSE handshake); two new discovery sources (UDP tracker, DHT) feed the M3 scheduler; PEX adds peers learned from connected peers. The scheduler/verify path is unchanged.

**Tech Stack:** Z98 (`zig1` → C89, `gcc -m32`), `std_crypto` (SHA-1 + new RC4/modpow), `std_net` (TCP/UDP), `std_bencode`, POSIX `sh` gates.

**Spec:** `docs/superpowers/specs/2026-10-09-z9torr-m4-real-swarm-compat-design.md` (binding).

**Sequence:** PREVIOUS: `docs/superpowers/plans/2026-10-08-z9torr-m3-multi-peer-plan.md`. NEXT: `docs/superpowers/plans/2026-10-08-z9torr-m5-win9x-plan.md`.

## Global Constraints

- **Depends on M0–M3** (green). The compiler is otherwise frozen; **std changes are authorized** in M4 for `sf/src/std_crypto.zig` (and, if needed, `std_net.zig` UDP) — the compiler fixed point is still untouched and `scripts/stdlib/verify_stdlib.sh` MUST stay green with M0-style registration of any new fixture.
- **Engineering rules:** free functions only (no method syntax); no generics/`anytype`/`@Type`; strict `@intCast`; every `switch` needs `else`; string literals via `var s: []const u8`; D1 (no C-keyword `union(enum)` tag), D2 (slice `[]T` only over a primitive or *named* type — never a synthetic; use flat `[]u8`/`[N]T`), D3/D4 (no module-global struct address passed into a suspension; no struct-return temporaries across a suspension).
- **Per-peer state lives in `Peer`** (spec base §6) — no module-global coroutine scratch.
- **No push. No compression during the build session. `edit`/`fastedit` only.** Reports under `.superpowers/sdd/2026-10-09-z9torr-m4-real-swarm-compat-plan/`.
- **Real-swarm tests are best-effort**, not a hard gate; report their outcome honestly.

## File Structure

- Create: `sf/src/std_crypto.zig` additions (RC4 + modpow), `examples/z98/z9torr/{mse.zig,udp_tracker.zig,dht.zig,pex.zig}`
- Create: `examples/z98/z9torr/tools/{mock_mse_peer.zig,mock_udp_tracker.zig}` and `tests/{tier3_encrypted.sh,tier_udp_tracker.sh,tier_dht.sh,tier_pex.sh,tier_real.sh}`
- Modify: `examples/z98/z9torr/{wire.zig,peer.zig,scheduler.zig,tracker.zig,main.zig}`, `docs/sf/QUICK_REF.md`, `scripts/stdlib/expected_dirs.txt`, seed scripts (for new std fixtures)

---

### Task 0: Baseline + `peer_id` fix

**Files:** Modify `examples/z98/z9torr/{main.zig,scheduler.zig}`; Record `.superpowers/sdd/2026-10-09-z9torr-m4-real-swarm-compat-plan/task-0-report.md`

**Interfaces:**
- Produces: a correct per-peer `peer_id` (the client's real `makePeerId` value, not all zeros) present in every outgoing handshake.

- [ ] **Step 1: Baseline.** Confirm HEAD builds and `tier1.sh`/`tier1_cli.sh`/`tier2.sh`/`tier1_unit.sh` are green with the seed compiler; record the head SHA and `--dump-c89` md5.
- [ ] **Step 2: Fix.** Ensure `makePeerId`'s value reaches every `Peer.peer_id` (copy it into `Peer` when the slot is created/added, or set it in `main.zig` after `addPeer`; do not leave zeros). Re-run all gates; the handshake now carries the real peer id.
- [ ] **Step 3: Commit + report.** `git commit -m "fix(z9torr): carry the real peer_id into every peer slot"`.

---

### Task 1: Std crypto primitives (RC4 + modular exponentiation)

**Files:** Modify `sf/src/std_crypto.zig`; Create `repro/mi_matrix/stdlib_crypto_rc4_xmod/**` + `stdlib_crypto_modpow_xmod/**`; Modify `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh`, `docs/sf/QUICK_REF.md`, `scripts/stdlib/expected_dirs.txt`; Record `task-1-report.md`

**Interfaces:**
- Produces: `pub fn rc4Init(key: []const u8, out: *Rc4) void`; `pub fn rc4Apply(ctx: *Rc4, buf: []u8) void` (in place); `pub const Rc4 = struct { s: [256]u8, i: u8, j: u8 }`; `pub fn modpow(base: []const u8, exp: []const u8, modulus: []const u8, out: []u8) void` over fixed big-endian limbs (width sized for the MSE 768-bit prime).
- Consumes: existing `sf/src/std_crypto.zig` SHA-1.

- [ ] **Step 1 (INVESTIGATE, read-only):** confirm the exact MSE DH width/byte order and choose a limb representation; STOP-present if the width/perf is infeasible under Z98/C89 (spec §7 risk 1).
- [ ] **Step 2:** Implement RC4 (RFC 6229 vectors) and `modpow`; add fixtures with committed goldens; register both fixtures M0-style; keep `verify_stdlib.sh` green.
- [ ] **Step 3: Commit + report.** `git commit -m "feat(std_crypto): add RC4 + modular exponentiation (M4)"`.

---

### Task 2: MSE / PE encrypted handshake

**Files:** Create `examples/z98/z9torr/mse.zig`, `tools/mock_mse_peer.zig`, `tests/tier3_encrypted.sh`; Modify `wire.zig`, `peer.zig`, `tests/tier2.sh` (operator ruling 2026-10-09, option C: the encrypted-first reconnect + plaintext fallback may require tier2 harness changes to reflect the client's real behavior; `tools/mock_peer.zig` stays one-shot); Record `task-2-report.md`

**Interfaces:**
- Consumes: `std_crypto` RC4 + SHA-1 (Task 1); the existing plaintext `wire.readHandshakeAsync`/`writeHandshake`/message framing.
- Produces: `pub fn mseConnect(sock, info_hash, seed) MseError!Rc4Pair` (outbound encrypted handshake → two RC4 contexts); a transparent encrypted transport used by `peerRun`, with a bounded plaintext fallback.
- Produces: `mock_mse_peer.zig` (a Z98 peer that requires MSE) for the gate.

- [ ] **Step 1 (INVESTIGATE):** pin the MSE byte layout (Ya/Yb, `HASH('req1'|S)`, `HASH('req2'|info_hash)`, `HASH('req3'|S)`, method negotiation) with at least one external reference vector.
- [ ] **Step 2:** Implement `mse.zig`; wire `peer.zig` to encrypt-first with a bounded plaintext fallback; keep the RC4 transform inside the existing framing (no message-path rewrite). RC4 keys are `SHA1('keyA'||S||info_hash)` / `SHA1('keyB'||S||info_hash)` (SKEY = the torrent info_hash; corrected 2026-10-09 per operator ruling — the canonical MSE/PE derivation includes SKEY).
- [ ] **Step 3:** `tests/tier3_encrypted.sh` runs the client against `mock_mse_peer` and confirms a completed download; all prior gates stay green.
- [ ] **Step 4: Commit + report.** `git commit -m "feat(z9torr): MSE/PE encrypted peer handshake (M4)"`.

---

### Task 3: UDP tracker (BEP 15)

**Files:** Create `examples/z98/z9torr/udp_tracker.zig`, `tools/mock_udp_tracker.zig`, `tests/tier_udp_tracker.sh`; Modify `tracker.zig`, `main.zig`; Record `task-3-report.md`

**Interfaces:**
- Consumes: `std_net` UDP (`udpBind`/`udpSendTo`/`udpRecvFrom`/`udpSetTimeout`), `std_bencode`.
- Produces: `pub fn announceUdp(arena, tracker_url, info_hash, peer_id, port, event: tracker.AnnounceEvent, stats) TrackerError!AnnounceResult` implementing connect/announce; `main.zig` prefers UDP trackers when the torrent lists them, else HTTP, and passes `started`/`completed` over UDP exactly as it does over HTTP. BEP 15 event codes are `1=completed, 2=started, 3=stopped` — the OPPOSITE of the HTTP/`AnnounceEvent` numbering — so convert with an explicit map (started→2, completed→1), never a raw enum cast. (Corrected 2026-10-09 per operator ruling A.)

- [ ] **Step 1:** Implement the BEP 15 connect/announce with transaction ids, retries, and timeout; parse compact peers.
- [ ] **Step 2:** `tests/tier_udp_tracker.sh` runs against `mock_udp_tracker`; a torrent with a `udp://` announce downloads via the scheduler.
- [ ] **Step 3: Commit + report.** `git commit -m "feat(z9torr): UDP tracker support (BEP 15) (M4)"`.

---

### Task 4: DHT (BEP 5) + PEX (BEP 11)

**Files:** Create `examples/z98/z9torr/{dht.zig,pex.zig}`, `tests/{tier_dht.sh,tier_pex.sh}`; Modify `main.zig`, `peer.zig`, `wire.zig`; Record `task-4-report.md`

**Interfaces:**
- Consumes: `std_bencode`, `std_net` UDP, the scheduler's `addPeer`.
- Produces: `dht.zig` KRPC `ping`/`find_node`/`get_peers`/`announce_peer` + a bootstrap-grade routing table; `pex.zig` BEP 10 extension handshake + `ut_pex` add/drop handling feeding `addPeer`.

- [ ] **Step 1 (INVESTIGATE):** pin KRPC message shapes and the BEP 10/11 extension ids; define the minimal routing table.
- [ ] **Step 2:** Implement `dht.zig`; `tests/tier_dht.sh` runs two in-process nodes and confirms `get_peers` discovery.
- [ ] **Step 3:** Implement `pex.zig`; `tests/tier_pex.sh` confirms peers from a `ut_pex` message reach the scheduler.
- [ ] **Step 4: Commit + report.** `git commit -m "feat(z9torr): DHT (BEP 5) + PEX (BEP 11) discovery (M4)"`.

---

### Task 5: Real-swarm tier + closeout

**Files:** Create `examples/z98/z9torr/tests/tier_real.sh`; Modify `demo/README.md`, `NOTES.md`, `README.md`; Record `task-5-report.md`

- [ ] **Step 1:** Add `tests/tier_real.sh` (best-effort): attempt a real single-file torrent with MSE + UDP tracker, assert measurable progress when the network allows, and report (never silently skip) when it cannot.
- [ ] **Step 2: Gate (example-only).** Run `tier1.sh`/`tier1_cli.sh`/`tier2.sh`/`tier1_unit.sh`/`tier3_encrypted.sh`/`tier_udp_tracker.sh`/`tier_dht.sh`/`tier_pex.sh` — all PASS; `verify_stdlib.sh` green (new std fixtures registered); compiler fixed point untouched.
- [ ] **Step 3: Docs + commit + report.** Update docs; `git commit -m "example(z9torr): M4 real-swarm compatibility closeout"`.
- [ ] **Step 4: Next plan.** State that M5 (`2026-10-08-z9torr-m5-win9x-plan.md`) is next.

## Self-Review

- **Spec coverage:** spec §4.1 → Task 1; §4.2 → Task 2; §4.3 → Task 3; §4.4 → Task 4; §1 peer_id → Task 0; §6 real tier → Task 5.
- **Placeholder scan:** Task 1/2/4 open with explicit INVESTIGATE steps (the plan does not presuppose the big-int/MSE layout answers); no TBD elsewhere.
- **Type consistency:** `Rc4`/`rc4Init`/`rc4Apply`/`modpow`, `mseConnect`/`Rc4Pair`, `announceUdp`, DHT/PEX entry points are named consistently with the spec.
