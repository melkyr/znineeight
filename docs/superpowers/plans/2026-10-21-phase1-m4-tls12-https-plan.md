# Phase 1 M4 — TLS 1.2 + HTTPS Demo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `std_tls` record layer + TLS 1.2 handshake (browser-grade validation wired in), `std_http` transport vtable so HTTPS is a std capability, and `tls_demo` fetching real web content over HTTPS on Linux and as a `-osw` Win9x build.

**Architecture:** Sans-I/O `TlsSession`/`tlsStep` per spec §5.6; record layer AEADs per suite (RFC 5288/7905 nonce handling); handshake is the explicit state machine with ECDHE (secp256r1 + x25519), SNI, `std_crypto` SHA-256 transcript, PRF_SHA256 Finished; server cert chain validated via `std_x509.x509VerifyChain` against the shipped store with `now_unix` from config. `std_http.httpGetOver` drives any `HttpTransport`; the demo supplies one over `std_net` TCP + `std_tls`.

**Tech Stack:** Z98; M2/M3 modules; `openssl s_server` (host, test-only) + real internet targets for tiers.

**Spec:** `docs/superpowers/specs/2026-10-21-phase1-tls-wireguard-design.md` §5.6, §5.9, §6, §7, §10 ruling 11

## Global Constraints

- Sans-I/O: `tlsStep(sess, input, output) !TlsAction`; driver owns sockets/time. `now_unix: i64` on `TlsConfig` (wall clock; demo `clock_override_unix` support; clean `cert: time` failure otherwise).
- Suites exactly: `TLS_ECDHE_{ECDSA,RSA}_WITH_{AES_128_GCM_SHA256, CHACHA20_POLY1305_SHA256}`. SNI required. `TLS_MAX_RECORD = 16384`. No renegotiation/resumption/0-RTT/client-cert.
- Errors: `error.{Corrupt, HandshakeFailed, CertificateExpired, CertificateNotYetValid, UnknownIssuer, HostnameMismatch, UnsupportedSuite, UnsupportedGroup, RecordTooLarge, Closed, OutOfMemory, Time}`.
- Demo RAM 32 MB hard ceiling / 16 MB target (`ulimit -v 32768` + `/usr/bin/time -v` recorded); body print capped 4 KB; resource line `tls_demo ok status=200 bytes=N arena_peak=N rss_peak=N cpu_ms=N`.
- Gates per task (hybrid): targeted fixtures for the touched module + direct consumers + affected `run_crosscheck.sh` modules + 3× determinism; `tier_tls.sh` (local s_server + `Z98_NET=1` internet smoke); `-osw` build + import gate (KERNEL32+WINMM+WSOCK32, no msvcrt). Full `verify_stdlib.sh` + full crosscheck is mandatory immediately after any change to existing module functions, shared harness/`expected_dirs.txt`, `std.zig`, or a cross-module contract, and at Task 4 closeout. Task 1 edits existing `std_http` → full gate; Task 2 extends new `std_tls` → targeted; Task 3 demo/tier → targeted + tier.
- Closeout rotates seed **v115** (45 lib files: +`std_tls`); fixed point unchanged `45158dcede81125a39a2c2c58478e21e`.
- Commits `feat(std_tls): … (Phase1 M4)`, `feat(std_http): transport vtable …`, `example(z9play-style)`: `example(z9demo): tls_demo …`, `docs(std_lib): …`, `chore(seed): rotate (M4)`, `docs(sdd): …`. STOP-present on contract change.

## Review Focus

1. Handshake accepts a server whose Finished/transcript mismatches (transcript hash must cover every handshake message exactly once, record headers excluded).
2. Nonce/sequence reuse or wrong explicit-nonce layout (RFC 5288/7905) — canned-record KATs must pin the exact ciphertext bytes.
3. Cert validation bypassed on any error path (every `tlsStep` exit before `Established` must fail closed; negative tier: expired/wrong-host/no-anchor).
4. Big handshake messages fragmented across records (Certificate > 16 KB / multi-record) reassembled correctly.
5. The internet smoke silently skipped when offline — `Z98_NET` unset must SKIP loud with reason, never pass vacuously.

---

### Task 1: Record layer + `std_http` transport

**Files:**
- Create: `sf/src/std_tls.zig` (record layer portion)
- Modify: `sf/src/std_http.zig` (add `HttpTransport`, `httpGetOver`; `get()` unchanged)
- Test: `repro/mi_matrix/stdlib_tls_record_xmod/{main.zig,expected.txt,expected.rc}`
- Test: `repro/mi_matrix/stdlib_http_transport_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Consumes: M2 `std_cipher` (AEADs), `std_arena`.
- Produces: record encode/decode (5-byte header, 16384 max, `RecordTooLarge`), per-suite AEAD record protect/unprotect with RFC 5288 (AES-GCM explicit nonce) + RFC 7905 (ChaCha20 seq-XOR nonce), `error.Closed` on clean close; `HttpTransport` vtable + `httpGetOver` (GET, HTTP/1.1, `identity` + `chunked` decode, fixed caller buffer).

- [ ] **Step 1:** Failing fixtures: canned record vectors (exact ciphertext bytes for both AEAD suites, seq 0 and 7, with/without AAD) + tamper→`Corrupt`/`AuthenticationFailed`; `RecordTooLarge`; fragmented-header-mid-buffer reads. HTTP transport fixture: a mock transport serving chunked + identity responses through `httpGetOver` (byte-exact `Response`).
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement; input buffering with `memmove` (circular later); HTTP GET with `Host:`/`Connection: close`, chunked decoder per RFC 7230 §4.1.
- [ ] **Step 4:** Run — PASS + full gate + 3×.
- [ ] **Step 5:** Commit `feat(std_tls): record layer (Phase1 M4)` + `feat(std_http): HttpTransport vtable (Phase1 M4)` (two commits).

### Task 2: TLS 1.2 handshake

**Files:**
- Modify: `sf/src/std_tls.zig` (state machine + key schedule)
- Test: `repro/mi_matrix/stdlib_tls12_handshake_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Consumes: M2 ECC (X25519, P-256 ECDH), M3 `x509VerifyChain`/`TrustStore`, `std_crypto` SHA-256/HMAC (PRF_SHA256).
- Produces (spec §5.6): `TlsAction`, `TlsConfig` (with `now_unix`), `TlsSession`, `tlsInit`, `tlsStep`, `tlsRead`, `tlsWrite`. States `SendClientHello … Established`; Finished verify_data 12 bytes.

- [ ] **Step 1:** Failing fixture: canned full-handshake transcripts captured from `openssl s_server` (one ECDHE-ECDSA/AES-GCM, one ECDHE-RSA/ChaCha20, one with a fragmented Certificate record) — driver feeds bytes through `tlsStep`, asserts action sequence + `tlsRead` application bytes + transcript/Finished verification; negatives: bad Finished → `HandshakeFailed`, expired leaf → `CertificateExpired`, no SNI match → `HostnameMismatch`.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement the state machine (spec §5.6 + `projects_phase1.txt` §1.4 order); ServerKeyExchange signature check (ECDSA/RSA per leaf key); key block derivation (PRF_SHA256); CCS + Finished both directions.
- [ ] **Step 4:** Run — PASS + targeted `std_tls` fixtures + affected `run_crosscheck.sh` modules + 3×. Full gate at Task 4 closeout.
- [ ] **Step 5:** Commit `feat(std_tls): TLS 1.2 handshake (Phase1 M4)`.

### Task 3: `tls_demo` + `tier_tls.sh`

**Files:**
- Create: `examples/z98/demo/tls_demo/main.zig`
- Create: `examples/z98/demo/tls_demo/README.md` (build/run Linux + Win9x `-osw`, config, expected output, troubleshooting)
- Create: `scripts/stdlib/tier_tls.sh` (or `examples/z98/demo/tls_demo/tests/tier_tls.sh` per house placement of tiers)
- Wire: `ca_store.bin` from M3 next to the demo

**Interfaces:**
- Consumes: `std_tls` handshake, `std_http.httpGetOver`, `std_net`, `std_x509` store, `std_time` (driver clock), `std_arena` + `/proc/self/status`-style peak (Linux) for the resource line.
- Produces: `tls_demo [url] [store] [clock_override_unix]` printing `status=…` + body ≤4 KB + resource line; non-zero exit with `cert: …`/`tls: …` reason.

- [ ] **Step 1:** Implement demo; default URL `https://www.google.com/`; parse `clock_override_unix` optional arg.
- [ ] **Step 2:** `tier_tls.sh`: (a) local `openssl s_server` with committed test cert/key — happy path fetch exact body; negative cases: expired cert, wrong-host cert, untrusted anchor → exact error text; (b) `Z98_NET=1` internet smoke: google.com + example.com status 200 + `bytes>0`; unset `Z98_NET` → loud SKIP line; (c) RAM: `ulimit -v 32768` wrapper + `/usr/bin/time -v` peak recorded in tier output; (d) `-osw` emit/build + `check_win9x_imports.sh 9x` gate.
- [ ] **Step 3:** Run `tier_tls.sh` green (2× deterministic) + targeted demo/transport checks + 3×. Full gate at Task 4 closeout.
- [ ] **Step 4:** Commit `example(z9demo): tls_demo HTTPS fetch (Phase1 M4)` + `test(tier): tier_tls (Phase1 M4)`.

### Task 4: M4 closeout — docs + seed rotation

**Files:**
- Create: `sf/docs/std_lib/tls.md`
- Modify: `STD_README.MD`, `README.md`, `docs/sf/QUICK_REF.md` (44→45 counts/rows)
- Modify: `scripts/seed/archive_seed.sh`, `scripts/seed/build_from_seed.sh`
- Rotate: `release/seed/` → **v115** (45 files)

- [ ] **Step 1:** tls.md (API §5.6, suite table, error table, time/clock policy, buffer sizes); demo README already written in T3 — cross-check.
- [ ] **Step 2:** Truth-ups + seed scripts; rotate v115; verify manifest/archive/fixed point `45158dcede81125a39a2c2c58478e21e`/hop1==hop2 (std-only; compiler source unchanged); full gate on rotated compiler.
- [ ] **Step 3:** Commits `docs(std_lib): tls docs (M4)`, `chore(seed): rotate (M4)`, `docs(sdd): M4 closeout report`.
