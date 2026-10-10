# z9torr M4.1 — Real MSE/PE Handshake Debugging — Design

**Status:** Done (operator, 2026-10-10) — M4.1 complete; see
`docs/superpowers/plans/2026-10-10-z9torr-mse-real-handshake-plan.md` Task 5.
NEXT (done 2026-10-10): z9torr M4 polish relaxed the handshake to ignore
unknown reserved bits per BEP 3 (the `wire.reservedAccepted` predicate was
removed); then M5 (Win9x).
**Goal:** Make z9torr complete a **real** MSE/PE encrypted handshake and download, verified against real reference implementations, then against the live swarm.
**Driver:** the 2026-10-10 live run (`lin_bin/`): 50 tracker peers, 12/16 TCP timeouts (sandbox egress), 4 connected — 3 `mse-fail` (`PeerClosed`/`Timeout`), 1 `handshake-fail HandshakeFailed`; all plaintext fallbacks failed; 0 bytes. The compiler D5 fix is confirmed good (handshake now carries the real `-Z9T01-…` peer_id).
**Sequence:** after the compiler codegen-defect fixes (D1–D5). Before resuming “point 3” polish.

## §1 Problem

Against the live Debian swarm, z9torr's MSE handshake never completes: reachable peers either close during/after our `Ya`/handshake or never answer, and the plaintext fallback never succeeds either. It is unproven whether the fault is (a) a z9torr MSE byte-stream bug, (b) the encrypted-first policy vs plaintext-only peers, or (c) the fallback/non-blocking design. We cannot debug this against the public swarm alone (egress/NAT/timeouts are noisy and non-deterministic).

## §2 Scope

**In scope:** an MSE stage-level diagnostic; a **hermetic real-handshake test tier** driven by two independent reference peers — **aria2c** (a real BitTorrent client) and an **independent pure-Python MSE responder**; the non-blocking handshake; the fallback policy + fix; a best-effort live retest.

**Out of scope:** TLS/HTTPS trackers; IPv6; µTP; seeding/upload; DHT routing-table depth; compiler changes (frozen again after the D1–D5 plan).

## §3 Approach

1. **Diagnostics first.** Extend the env-gated log in `sf/src`-free example `examples/z98/z9torr/mse.zig` `mseConnect` to record the stage and bytes at each step (Yb received; `VC` sync found y/n; `crypto_provide`/`crypto_select`; the req1/req2xor send). Reproduce the live failure with a trace.
2. **Two independent reference peers** (operator ruling: both):
   - **aria2c** obtained reproducibly without root via a committed helper `examples/z98/z9torr/tests/get_aria2.sh` (writable apt cache → `--download-only` aria2 + deps → `dpkg-deb -x` overlay → `LD_LIBRARY_PATH`). Verified: `aria2 1.36.0`. Run as a **forced-encryption seeder** (`--bt-require-crypto=true --bt-min-crypto-level=arc4`) for a local torrent; `mock_tracker` advertises `127.0.0.1:<aria2 port>`; z9torr announces → connects → **real MSE handshake** → download.
   - **Pure-Python MSE responder** `examples/z98/z9torr/tests/mse_ref.py` (stdlib only: `hashlib` SHA1, hand-rolled RC4 + 768-bit DH) — a second, independent implementation of the exact MSE byte layout; likewise seeds a local torrent for z9torr.
3. **Non-blocking handshake.** Make the TCP connect + MSE probe coroutine-aware (yield on `WouldBlock`/during the bounded wait) so one slow peer cannot freeze the whole single-threaded scheduler (~3 s × 16) and mask reachable peers.
4. **Fallback policy + fix.** Decide encrypted-first-reconnect vs detect-first (plaintext, then MSE on immediate close) for mixed swarms, and fix the plaintext fallback (currently never succeeds).

## §4 Components / interfaces

- `examples/z98/z9torr/mse.zig` — stage diagnostics (env-gated), correctness fixes as the trace dictates.
- `examples/z98/z9torr/peer.zig` — non-blocking handshake integration; fallback path.
- `examples/z98/z9torr/tests/get_aria2.sh` — reproducible aria2c acquisition (no root).
- `examples/z98/z9torr/tests/mse_ref.py` — independent Python MSE responder + minimal seeder.
- `examples/z98/z9torr/tests/tier_refseed.sh` — real-seed tier (aria2c), loopback, byte-verified download; SKIP-with-reason if aria2 is unavailable.
- `examples/z98/z9torr/tests/tier_refseed_py.sh` — real-seed tier (Python responder).
- `tests/tier1..tier_pex` — must stay green.

## §5 Gates

- Existing z9torr tiers stay green (tier1/tier1_cli/tier2/tier1_unit/tier3_encrypted/tier_udp_tracker/tier_dht/tier_pex).
- New `tier_refseed.sh` (aria2c) and `tier_refseed_py.sh` (Python): z9torr completes an **encrypted** download from the reference peer, byte-verified.
- Live Debian retest is **best-effort** (report honestly, never silently skip).
- No compiler change (post-D1–D5 freeze); no seed rotation for this milestone.

## §6 Risks

1. **aria2c availability** — mitigated by the reproducible `get_aria2.sh`; if the environment blocks it, the Python reference carries the gate and the aria2 tier SKIPs with a reason.
2. **MSE root cause unknown** — the diagnostic must localize before any fix; STOP-present if the divergence is not identifiable.
3. **Non-blocking rework** touches the peer coroutine — D3/D4-style codegen hazards now fixed, but re-verify.
4. **Loopback-only proof** may still differ from the live swarm (NAT/egress); the live retest stays best-effort.

## §7 Out of scope
As §2. No compiler changes; no seed rotation.

## §8 Milestone index (updated)
`M4.1 real MSE handshake` → `docs/superpowers/plans/2026-10-10-z9torr-mse-real-handshake-plan.md`. NEXT after it: resume z9torr M4 polish and then M5 (Win9x).
