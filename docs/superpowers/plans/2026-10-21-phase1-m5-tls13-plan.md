# Phase 1 M5 — TLS 1.3 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the TLS 1.3 path to `std_tls` — X25519, HKDF-Expand-Label key schedule, EncryptedExtensions/Certificate/CertificateVerify/Finished, RSA-PSS for RSA-cert servers — interoping with real TLS 1.3 servers.

**Architecture:** Same sans-I/O `TlsSession` (version-dispatched handshake), suites `TLS_AES_128_GCM_SHA256` + `TLS_CHACHA20_POLY1305_SHA256`, group x25519, no PSK/0-RTT/HRR (group mismatch → `error.UnsupportedGroup`). CertificateVerify accepts ECDSA (P-256/SHA-256, P-384/SHA-384) and **RSA-PSS** (RFC 8446 §4.4.3; `std_crypto.rsaVerifyPss`). Key schedule uses M2 `hkdfExtract`/`hkdfExpand` + the Expand-Label wrapper. Reference structure: picotls.

**Tech Stack:** Z98; `std_tls` from M4; M2 crypto.

**Spec:** `docs/superpowers/specs/2026-10-21-phase1-tls-wireguard-design.md` §5.6 (TLS 1.3 paragraph), §10 ruling 12

## Global Constraints

- Same sans-I/O API and error set as M4 (`TlsConfig.now_unix` feeds cert validity); `min_version`/`max_version` select 1.2/1.3; default offers both (version negotiation per RFC 8446 supported_versions).
- Cipher suites exactly the two above; hash = SHA-256 for the schedule; record layer = M4's (1.3 inner content-type).
- Certificate chain validation unchanged (M3, SAN-only, store-supplied); leaf auth: ECDSA or RSA-PSS only (PKCS#1 v1.5 MUST be rejected in CertificateVerify).
- Gates per task (hybrid): targeted fixtures for the touched module + direct consumers + affected `run_crosscheck.sh` modules + 3×; `tier_tls.sh` extended with TLS 1.3 cases (local `openssl s_server -tls1_3` + `Z98_NET=1` real servers incl. an RSA-cert host); `-osw` build + import gate. Full `verify_stdlib.sh` + full crosscheck is mandatory immediately after any change to existing module functions, shared harness/`expected_dirs.txt`, `std.zig`, or a cross-module contract. M5 extends existing `std_tls` → full gate per task and at closeout.
- Closeout rotates seed **v117** (45 files — no new module); fixed point unchanged `45158dcede81125a39a2c2c58478e21e`.
- Commits `feat(std_tls): TLS 1.3 (Phase1 M5)`, `docs(std_lib): …`, `chore(seed): rotate (M5)`, `docs(sdd): …`. STOP-present on contract change.

## Review Focus

1. Key-schedule label/secrets derivation errors (canned-transcript KATs must pin derived traffic secrets byte-exact).
2. RSA-PSS verification accepting PKCS#1 v1.5 CertificateVerify (must reject; negative fixture).
3. Transcript hash after CCS / message-order confusion in 1.3 (single hash over handshake messages in order).
4. Downgrade: server choosing 1.2 must still work through the same `tlsStep`; mixed fixture.
5. Interop silent-skip: `Z98_NET` unset → loud SKIP, never vacuous pass.

---

### Task 1: TLS 1.3 key schedule + handshake

**Files:**
- Modify: `sf/src/std_tls.zig`
- Test: `repro/mi_matrix/stdlib_tls13_handshake_xmod/{main.zig,expected.txt,expected.rc}`
- Test: `repro/mi_matrix/stdlib_tls13_auth_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Consumes: `std_crypto` (hkdf, sha256, rsaVerifyPss), `std_ecc` (x25519, p256/p384 verify), `std_cipher` (both AEADs), M3 verify.
- Produces: `tlsStep` 1.3 path (ClientHello+key_share → EncryptedExtensions → Certificate → CertificateVerify → Finished → `Established`); `tlsRead`/`tlsWrite` post-handshake (key update unsupported → `error.Closed` on receipt, documented).

- [ ] **Step 1:** Failing fixtures: canned 1.3 transcripts (ECDSA-cert AES-GCM; ECDSA-cert ChaCha20; RSA-cert with RSA-PSS CertificateVerify) asserting exact traffic-secret bytes, action sequence, app-data round-trip; negatives: PKCS#1 v1.5 CertificateVerify → `HandshakeFailed`; bad Finished → `HandshakeFailed`; unknown group in key_share → `UnsupportedGroup`.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement HKDF-Expand-Label, derived secrets chain (early/handshake/master + per-direction traffic secrets), 1.3 record protection, CertificateVerify dispatch (ECDSA/PSS), Finished with the 1.3 finished_key.
- [ ] **Step 4:** Run — PASS + full gate + 3×.
- [ ] **Step 5:** Commit `feat(std_tls): TLS 1.3 handshake (Phase1 M5)`.

### Task 2: Interop tier + closeout

**Files:**
- Modify: `tier_tls.sh` (1.3 cases: `openssl s_server -tls1_3` local; `Z98_NET=1` real-server smoke incl. an RSA-cert host)
- Modify: `examples/z98/demo/tls_demo/README.md` (1.3 notes)
- Create/Modify: `sf/docs/std_lib/tls.md` (1.3 section)
- Modify: `STD_README.MD`, `README.md`, `docs/sf/QUICK_REF.md` (45-file state, tls.md update)
- Modify: `scripts/seed/archive_seed.sh`, `scripts/seed/build_from_seed.sh`
- Rotate: `release/seed/` → **v117**

- [ ] **Step 1:** Extend tier: 1.3 happy paths both suites + RSA-PSS host; 1.2 fallback case still green; run 2× deterministic; `-osw` import gate.
- [ ] **Step 2:** Docs truth-ups (tls.md 1.3 section: suites, auth rules, key-update stance); counts/prose; seed scripts; rotate v117; fixed point verify; full gate.
- [ ] **Step 3:** Commits `docs(std_lib): tls 1.3 docs (M5)`, `chore(seed): rotate (M5)`, `docs(sdd): M5 closeout report`.
