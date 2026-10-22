# Phase 1 M6 — WireGuard Protocol — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `std_wireguard` — the NoiseIK initiator, transport data path, timers, replay window, and cookie consumption — proven byte-exact against reference exchanges, sans-I/O, ready for the M7 demo driver.

**Architecture:** Spec §5.7. Handshake initiation/response per `projects_phase1.txt` §2.3 (initiator half only), KDF = HKDF-BLAKE2s (WireGuard paper §5.4), AEAD = ChaCha20-Poly1305 (M2 `std_cipher`), TAI64N timestamp from the **`wall_unix_ns` parameter** (never from `now_ms` — ruling 11), timers driven by `wgTick(now_ms)` polls. Fixed-size peer state; packet buffers caller-supplied `out` slices. Reference: `wireguard-lwip` (protocol logic) + the WireGuard whitepaper.

**Tech Stack:** Z98; M2 crypto (`x25519`, `chacha20Poly1305*`, `blake2s`, `hmacBlake2s`).

**Spec:** `docs/superpowers/specs/2026-10-21-phase1-tls-wireguard-design.md` §5.7, §10 ruling 11

## Global Constraints

- Sans-I/O: `wgTick`/`wgReceive`/`wgSend` signatures exactly as spec §5.7 (incl. `wall_unix_ns: u64` on `wgTick`/`wgSend`); errors `error.{Corrupt, AuthenticationFailed, NoSession, SessionExpired, OutputTooSmall}`.
- Initiator only (no responder/cookie-reply generation; cookie *consumption* with mac2 = keyed BLAKE2s-128 required). One peer in demos; peer table capacity caller-sized.
- Timers exact: `REKEY_AFTER_TIME` 120 s, `REJECT_AFTER_TIME` 180 s, `REKEY_TIMEOUT` 5 s + attempt backoff, `KEEPALIVE_TIMEOUT` 10 s. Counter/replay: sliding 2048-bit window; nonce reuse is a hard bug (fixture must pin counter monotonicity).
- All wire integers little-endian via explicit load/store helpers; no alignment assumptions.
- Gates per task (hybrid): targeted `std_wireguard` fixtures + affected `run_crosscheck.sh` modules + 3×; canned-exchange fixtures byte-compare against vectors derived from `wireguard-lwip` (vendored ref `scripts/stdlib/ref/std_wireguard/ref.c`, BSD attribution) run at capture time; `-osw` build + import gate. Full `verify_stdlib.sh` + full crosscheck is mandatory immediately after any change to existing module functions, shared harness/`expected_dirs.txt`, `std.zig`, or a cross-module contract, and at Task 3 closeout. `std_wireguard` is new → targeted-only until closeout.
- Closeout rotates seed **v118** (46 lib files: +`std_wireguard`); fixed point unchanged `45158dcede81125a39a2c2c58478e21e`.
- Commits `feat(std_wireguard): … (Phase1 M6)`, `docs(std_lib): …`, `chore(seed): rotate (M6)`, `docs(sdd): …`. STOP-present on contract change.

## Review Focus

1. KDF chaining error (ck/k evolution) — canned handshake vectors pin every derived key byte.
2. TAI64N source regression (someone derives it from `now_ms`) — fixture with wall≠monotonic inputs must pin the wire timestamp bytes.
3. Replay window off-by-one (accept/drop boundary at window edge) — negative fixtures.
4. Rekey timer state machine: after REJECT_AFTER_TIME, `wgSend` must fail `SessionExpired`, never encrypt.
5. mac2/cookie path untested → fixture with a CookieReply forcing mac2 inclusion.

---

### Task 1: NoiseIK initiator + handshake state

**Files:**
- Create: `sf/src/std_wireguard.zig`
- Test: `repro/mi_matrix/stdlib_wg_handshake_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Consumes: M2 (`x25519`/`x25519Base`, `chacha20Poly1305Seal/Open`, `blake2s`, `hmacBlake2s`).
- Produces (spec §5.7): `WgPeer`, `WgDevice`, `wgInit`, `wgAddPeer`; handshake initiation construction (ephemeral keygen from caller xoshiro via device rng field — seed explicit), response processing, chaining-key derivation, static/timestamp encryption, mac1/mac2.

- [ ] **Step 1:** Failing fixtures: canned handshake exchanges captured from the vendored `wireguard-lwip` ref build (initiation bytes, response bytes, derived transport keys) — byte-exact; negatives: wrong static key → `AuthenticationFailed`, truncated message → `Corrupt`, mac1 mismatch → `Corrupt`.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement NoiseIK initiator per the paper §2 + `projects_phase1.txt` §2.3 steps; TAI64N from `wall_unix_ns` (pin wire bytes); LE helpers.
- [ ] **Step 4:** Run — PASS + targeted `std_wireguard` fixtures + affected `run_crosscheck.sh` modules + 3×. Full gate at Task 3 closeout.
- [ ] **Step 5:** Commit `feat(std_wireguard): NoiseIK handshake (Phase1 M6)`.

### Task 2: Transport, timers, replay, cookies

**Files:**
- Modify: `sf/src/std_wireguard.zig`
- Test: `repro/mi_matrix/stdlib_wg_transport_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Produces: `wgTick(dev, now_ms, wall_unix_ns, out) !WgAction`, `wgReceive(dev, now_ms, udp_payload, out) !WgAction`, `wgSend(dev, now_ms, wall_unix_ns, inner_ip, out) !usize`; transport encrypt/decrypt with counter nonces; 2048-bit replay window; cookie store + mac2 on re-initiation; `WgAction` variants (send handshake / send keepalive / session up / inner packet available / dropped-replay).

- [ ] **Step 1:** Failing fixtures: transport round-trip byte-exact vs ref (padding to 16, counter 0/1/max-before-reject); replay negatives (duplicate, too-old, in-window-not-seen); timer sweep fixture (advance `now_ms` through rekey/keepalive/reject thresholds asserting `wgTick` outputs); CookieReply → subsequent initiation carries correct mac2.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement per spec §5.7; never `sleep` (pure time-parameterized).
- [ ] **Step 4:** Run — PASS + targeted `std_wireguard` fixtures + affected `run_crosscheck.sh` modules + 3× + `-osw` gate. Full gate at Task 3 closeout.
- [ ] **Step 5:** Commit `feat(std_wireguard): transport + timers (Phase1 M6)`.

### Task 3: M6 closeout — docs + seed rotation

**Files:**
- Create: `sf/docs/std_lib/wireguard.md`
- Modify: `STD_README.MD`, `README.md`, `docs/sf/QUICK_REF.md` (45→46 counts/rows)
- Modify: `scripts/seed/archive_seed.sh`, `scripts/seed/build_from_seed.sh`
- Rotate: `release/seed/` → **v118** (46 files)

- [ ] **Step 1:** wireguard.md (API §5.7, message flow diagram, timer table, replay/cookie semantics, `wall_unix_ns` vs `now_ms` warning).
- [ ] **Step 2:** Truth-ups; seed scripts; rotate v118; fixed point verify; full gate on rotated compiler.
- [ ] **Step 3:** Commits `docs(std_lib): wireguard docs (M6)`, `chore(seed): rotate (M6)`, `docs(sdd): M6 closeout report`.
