# z9torr M4 — Real-Swarm Compatibility — Design

**Status:** Approved (operator, 2026-10-09); **M4 polished 2026-10-10** — the peer handshake now ignores unknown reserved bits per BEP 3 (the strict `wire.reservedAccepted` predicate is removed), closing the last real-peer compatibility gap after M4.1.
**Goal:** Make the z9torr example able to connect to and download from **real public BitTorrent swarms** — by adding BitTorrent Protocol Encryption (MSE/PE), UDP trackers (BEP 15), and DHT (BEP 5) + PEX (BEP 11) peer discovery — on top of M0–M3.
**Blueprint:** `examples/ztorr_blp.txt`
**Base spec of record:** `docs/superpowers/specs/2026-10-08-z9torr-bittorrent-client-design.md`
**Sequence:** PREVIOUS: M3 (`docs/superpowers/plans/2026-10-08-z9torr-m3-multi-peer-plan.md`). NEXT: M5 (`docs/superpowers/plans/2026-10-08-z9torr-m5-win9x-plan.md`).

## §1 Evidence / motivation

The M3 diagnostic (`lin_bin/`, commit `f7f4cd5b`) ran z9torr against a real single-file torrent (Debian 13.7.0 amd64 netinst, HTTP tracker `http://bttracker.debian.org:6969/announce`):

- The tracker returned **50 compact IPv4 peers** (no IPv6).
- Of 7 peers that completed TCP connect, **all failed at handshake stage `pstrlen` with 0 bytes received** (6× `PeerClosed`, 1× `Timeout`): the peers closed the connection without sending anything.
- The other 9 slots were `connect-fail err=timeout` (sandbox egress).
- z9torr's plaintext handshake (19-byte pstr + 8 zero reserved + info_hash + peer_id) is **correct** — it passes `tests/tier2.sh` (17/0) against the mocks.

Conclusion: reachable public peers **require BitTorrent Protocol Encryption (MSE/PE)** and drop unencrypted connections. Public swarms also rely on UDP trackers and DHT. z9torr today is HTTP-tracker + plaintext only, so it cannot download from real swarms.

Separately, a latent bug was found: z9torr sends an **all-zero peer_id** — `scheduler.addPeer` never copies `makePeerId`'s `peer_id` into `Peer.peer_id`.

## §2 Scope and boundaries

**In scope:** outbound MSE/PE (encrypted handshake + RC4 stream); UDP tracker protocol (BEP 15); DHT (BEP 5) bootstrap + `get_peers`/`announce_peer` for peer discovery; PEX (BEP 11) via the extension protocol (BEP 10); the `peer_id` fix.

**Out of scope:** inbound/seeding/upload; µTP/uTP; IPv6; multi-file torrents; webseeds; HTTPS/TLS trackers; magnet links; full long-running DHT routing-table maintenance (bootstrap-grade is enough).

## §3 Architecture

- A new **crypto layer** wraps the existing wire: after TCP connect, if the peer requires encryption (or unconditionally, encrypted-first with a plaintext fallback), perform the MSE handshake to derive RC4 keys, then run the existing `readMessage`/`write*` framing through an RC4 transform.
- **Peer discovery** gains two independent sources beyond HTTP: a UDP tracker client (BEP 15) and a DHT node (BEP 5). PEX (BEP 11) adds peers learned from connected peers via BEP 10 extension messages.
- The scheduler/M3 pipeline is unchanged: peers feed the same `onBlock`/verify path; only the transport (encryption) and the discovery sources are new.

## §4 Components

### §4.1 Std-lib additions (hybrid rule: primitives go in std)
- `std_crypto`: add **RC4** (keystream init + in-place apply) and a **modular exponentiation** helper (`modpow(base, exp, modulus)` over a fixed big-integer width sufficient for the MSE 768-bit prime). SHA-1 (`sha1Init/Update/Final`) already exists.
- Register any new std module exactly as M0 did (both seed copy lists, `docs/sf/QUICK_REF.md`, `scripts/stdlib/expected_dirs.txt`) and keep `scripts/stdlib/verify_stdlib.sh` green (M0 baseline 280; currently 281 with the mtime fixture). The **compiler fixed point must stay untouched**.

### §4.2 MSE / PE (encrypted handshake)
- Outbound MSE (BitTorrent Protocol Encryption): Diffie-Hellman exchange `Ya = g^Xa mod P`, `Yb`, derive `S = Yb^Xa mod P`, RC4 keys `HASH('keyA'|S|SKEY)`, `HASH('keyB'|S|SKEY)` where `SKEY = info_hash` (corrected 2026-10-09 per operator ruling: canonical MSE/PE includes SKEY in the RC4 key derivation); send/verify `HASH('req1'|S)`, `HASH('req2'|info_hash)`, `HASH('req3'|S)`; then the normal handshake and messages are RC4-encrypted.
- Policy: **encrypted-first**, with a bounded plaintext fallback for peers that accept it (keeps the mock/diagnostic path working).
- Support the common MSE crypto options negotiated in the `HASH('req1')` block (plaintext and RC4; reject unknown methods with a clean error).

### §4.3 UDP tracker (BEP 15)
- Over `std_net` UDP: `connect` (get 64-bit `connection_id`), `announce`, parse compact peer list; retry/timeout policy; falls back to the HTTP tracker (M0) when absent. The UDP announce carries the same `started`/`completed` events as HTTP, converted to BEP 15 codes (`1=completed, 2=started, 3=stopped`) via an explicit map — NOT a raw `AnnounceEvent` cast (the two numberings are opposite). (Corrected 2026-10-09 per operator ruling A.)

### §4.4 DHT (BEP 5) + PEX (BEP 11)
- DHT: a bootstrap node list; `ping`, `find_node`, `get_peers`, `announce_peer` over KRPC (bencoded, `std_bencode`); a minimal routing table; feed discovered peers into the scheduler. Bootstrap-grade only.
- PEX: BEP 10 extension handshake, then periodic `ut_pex` message exchange carrying added/dropped peer lists.

## §5 Data structures

- `Encryption` (MSE state: keys, RC4 contexts, active flag) held per `Peer` (per-peer coroutine state; no module-global scratch — M3 spec §6).
- `UdpTracker` (connection_id, transaction ids, sockets), `DhtNode` (nodes, transactions, socket), `PexState` (extension ids, last-sent peer set).
- All new modules obey the engineering rules: free functions, no generics, strict `@intCast`, every `switch` has `else`, D1 (no C-keyword union tags), D2 (no slice of a synthetic type), D3/D4 (no module-global struct passed into a suspension; no struct-return temporaries across a suspension).

## §6 Gates and tests

- **Compiler untouched**; std changes (if any) keep `scripts/stdlib/verify_stdlib.sh` green.
- Example gates: existing `tier1.sh`/`tier1_cli.sh`/`tier2.sh`/`tier1_unit.sh` stay green; add `tests/tier3_encrypted.sh` (mock MSE peer), `tests/tier_udp_tracker.sh` (mock UDP tracker), `tests/tier_dht.sh` (two in-process DHT nodes), `tests/tier_pex.sh` (mock PEX peer).
- **Real-swarm tier (best-effort, not a hard gate):** `tests/tier_real.sh` attempts a real torrent over the public internet (encrypted + UDP tracker), asserts progress if reachable. Internet-dependent runs are reported, never silently skipped.
- Determinism: `Z9TORR_SEED` still seeds `peer_id`; MSE uses a seeded ephemeral key under the test env for reproducible mocks.

## §7 Risks

1. **Big-integer modular exponentiation in Z98/C89** (768-bit DH) is the largest risk: no bignum library; must be hand-written with `u32`/`u64` limbs and constant-size arrays. Budget an investigation task first; if the width/perf is infeasible on Win9x, STOP-present.
2. **RC4 + SHA-1 keystream correctness** across the exact MSE byte order (big-endian DH, `HASH('keyA'|S)` semantics) — pin with RFC-style test vectors and a mock peer.
3. **Z98 codegen constraints** (D3/D4) around per-peer encryption state and coroutine suspensions.
4. **DHT/PEX scope creep** — cap at bootstrap-grade discovery; no persistent routing table.
5. **Real-swarm reachability** in the test environment (egress, NAT) — the real tier is best-effort and its limitations must be reported, not hidden.

## §8 Out of scope
As §2. In particular: no seeding/upload, no uTP, no IPv6, no multi-file, no HTTPS/TLS trackers.

## §9 Milestone index (updated)
| Milestone | Plan | Deliverable |
|---|---|---|
| M0 std prerequisites | `...-m0-std-prerequisites-plan.md` | `std_net` primitives + `std_bencode` + `std_http`. |
| M1 core | `...-m1-core-plan.md` | skeleton + CLI + torrent parse + tier1. |
| M2 single-peer + resume | `...-m2-single-peer-download-plan.md` | protocol + mock + tier2. |
| M3 multi-peer | `...-m3-multi-peer-plan.md` | rarest-first scheduler, rate limits, stats. |
| **M4 real-swarm compatibility** | `...-m4-real-swarm-compat-plan.md` | **MSE/PE, UDP tracker, DHT/PEX, peer_id fix; real-swarm best-effort.** |
| M5 Win9x cross | `...-m5-win9x-plan.md` | mingw/Wine smoke + manual Win98 procedure (was M4). |

Sequence: M0 → M1 → M2 → M3 → M4 → M5.
