# Phase 1 M3 — X.509 / Trust Store / caconv — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Browser-grade certificate validation in std — `std_asn1` (DER) + `std_x509` (parse, chain verify, hostname match) + the pinned trust-store binary format with `trustStoreLoad` — plus the Z98 `caconv` converter tool and the first shipped `ca_store.bin` asset with a refresh recipe.

**Architecture:** Streaming DER reader (no alloc, slices into input); `Cert` is caller-struct with slices into the DER buffer; `x509VerifyChain` walks leaf→anchor (depth ≤ 8) verifying signatures with M2 primitives (ECDSA P-256/SHA-256, ECDSA P-384/SHA-384, RSA PKCS#1 v1.5 SHA-256/384/512, keys ≥ 2048), validity vs caller `now_unix`, `basicConstraints`, SAN dNSName-only hostname match. Store format and policy: spec §5.4/§5.5.

**Tech Stack:** Z98; `std_base64` (PEM decode in caconv); `std_crypto`/`std_ecc` (M2); existing stdlib harness.

**Spec:** `docs/superpowers/specs/2026-10-21-phase1-tls-wireguard-design.md` §5.4, §5.5, §3, §7

## Global Constraints

- Z98 subset; no heap (caller arenas); std reads no clock (`now_unix` parameter is the only time source).
- Validation policy is binding: SAN dNSName only (exact + single-leftmost-label `*.` wildcard, case-insensitive); NO CN fallback, no IP SANs, no OCSP/CRL, SHA-1 signatures non-goal (roots trusted by fiat).
- Error set exact: `error.{CertificateExpired, CertificateNotYetValid, UnknownIssuer, HostnameMismatch, BadSignature, ChainTooLong, Corrupt, UnsupportedAlgorithm}`.
- Store format (spec §5.5) pinned byte-for-byte; `caconv` output deterministic (PEM file order).
- Gates per task (hybrid): targeted fixtures for the touched module + direct consumers + affected `run_crosscheck.sh` modules + 3× determinism; bad-input fixtures must error, never crash. Full `verify_stdlib.sh` + full crosscheck is mandatory immediately after any change to existing module functions, shared harness/`expected_dirs.txt`, `std.zig`, or a cross-module contract, and at Task 3 closeout. Tasks 1–2 add new modules → targeted-only until closeout; Task 0 is an existing-module carry-over and uses the full std harness once. This is the std harness only: no compiler corpus/goldens/examples/pins/markers unless compiler source changes.
- Closeout rotates seed **v115** (44 lib files: +`std_asn1`, +`std_x509`); fixed point unchanged `45158dcede81125a39a2c2c58478e21e`.
- Commits `feat(std_asn1): …`, `feat(std_x509): …`, `feat(demo): caconv … (Phase1 M3)`, `docs(std_lib): … (M2-style)`, `chore(seed): rotate (M3)`, `docs(sdd): …`. STOP-present on contract change.

## Review Focus

1. A malformed DER blob that reads out of bounds or loops (fuzz/truncation fixtures mandatory).
2. A chain accepted with a broken signature (each verify path needs a negative KAT).
3. Hostname wildcard over-matching (`*.example.com` must NOT match `a.b.example.com` or `example.com`).
4. Expired/ not-yet-valid acceptance when `now_unix` is at boundary values (±1 s).
5. caconv non-determinism (same PEM in → byte-identical store out, 2 runs).

---

### Task 0: M2 carry-over — PSS salt-length hardening

**Files:**
- Modify: `sf/src/std_crypto.zig`
- Modify: `repro/mi_matrix/stdlib_rsa_verify_xmod/main.zig`
- Report: `.superpowers/sdd/2026-10-21-phase1-m3-x509-truststore-plan/task-0-report.md`

**Interfaces:**
- Consumes: existing M2 `rsaVerifyPss` (`error.BadSignature` on invalid input).
- Produces: overflow-safe PSS salt validation; no API change.

- [ ] **Step 1:** In `pssCheck`, reject unless `sl <= em.len` and `em.len >= hlen + sl + 2` (safe on 32-bit `usize`).
- [ ] **Step 2:** Add negative KATs to `stdlib_rsa_verify_xmod` with `salt_len = 0xFFFFFFFF` and `0x80000000`; both must return `error.BadSignature`, never trap.
- [ ] **Step 3:** Run targeted `stdlib_rsa_verify_xmod` 3×, then one full `verify_stdlib.sh` + `run_crosscheck.sh` (existing-module change). No compiler battery.
- [ ] **Step 4:** Commit `fix(std_crypto): reject oversized PSS salt_len (M2 carry-over)`; append report. Seed rotation stays Task 3 (v115).

### Task 1: `std_asn1` + `std_x509` parse

**Files:**
- Create: `sf/src/std_asn1.zig`, `sf/src/std_x509.zig`
- Test: `repro/mi_matrix/stdlib_asn1_xmod/{main.zig,expected.txt,expected.rc}`
- Test: `repro/mi_matrix/stdlib_x509_parse_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Consumes: M2 `std_crypto` SHA-256/384 (subject hashes if needed), `std_ecc` (nothing yet).
- Produces: `Asn1Reader` + `asn1ReadTlv` (spec §5.4; `error.Corrupt`); `Cert` fields per spec; `x509Parse(der: []const u8, out: *Cert) !void` (extracts subject/issuer/SPKI/sig/sig_alg/pk_alg/not_before/not_after/is_ca/san_dns; time = UTC/GeneralizedTime → `i64` unix). `Cert` owns a fixed SAN slice array (documented cap) and `san_dns` points into it; overflow returns `error.Corrupt` (no arena parameter).

- [ ] **Step 1:** Failing fixtures: a committed corpus of 6+ real certificates (generated once via host `openssl` under `repro/mi_matrix/stdlib_x509_parse_xmod/certs/*.der`; malformed DER under `repro/mi_matrix/stdlib_asn1_xmod/vectors/*.bin` — leaf ECDSA P-256, leaf ECDSA P-384, leaf RSA-2048, CA cert with basicConstraints, cert with SAN list incl. wildcard, expired cert) + malformed set (truncated TLV, indefinite length, nested overflow, bad OID) asserting `error.Corrupt`. Fixtures embed the bytes via committed generated `certs_data.zig`/literal arrays; the harness runs from a scratch CWD, so no runtime file reads.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement streaming TLV reader (explicit length only; reject indefinite); OID table for the sig/pk algs in use (ecdsa-with-SHA256/384, sha256/384/512WithRSAEncryption, RSA-PSS ids reserved); SAN dNSName extraction.
- [ ] **Step 4:** Run — PASS + targeted `std_asn1`/`std_x509` fixtures + 3× determinism. Full gate at Task 3 closeout.
- [ ] **Step 5:** Commit `feat(std_asn1,std_x509): DER + certificate parse (Phase1 M3)`.

### Task 2: `x509VerifyChain` + trust store

**Files:**
- Modify: `sf/src/std_x509.zig` (verify + store)
- Test: `repro/mi_matrix/stdlib_x509_verify_xmod/{main.zig,expected.txt,expected.rc}`
- Test: `repro/mi_matrix/stdlib_truststore_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Consumes: M2 `std_ecc.p256EcdsaVerify`/`p384EcdsaVerify`, `std_crypto.rsaVerifyPkcs1v15`; `std_arena`.
- Produces (spec §5.4): `TrustAnchor`, `TrustStore`, `trustStoreLoad(arena, bytes, out) !void` (format §5.5), `x509VerifyChain(arena, leaf_der, intermediates, store, hostname, now_unix) !void`.

- [ ] **Step 1:** Failing fixtures: valid 3-cert chain (ECDSA P-256 leaf → SHA-384 intermediate → P-384 root — the real google-shaped case), RSA chain (SHA-256 + SHA-512 links), and negatives each asserting the exact error: `BadSignature` (bit-flip in intermediate sig), `CertificateExpired`/`CertificateNotYetValid` (now_unix boundary ±1 s), `UnknownIssuer` (anchor missing), `HostnameMismatch` (exact/wildcard/multi-label cases incl. `*.example.com` vs `a.b.example.com`), `ChainTooLong` (9 deep), `UnsupportedAlgorithm` (SHA-1 link). TrustStore fixtures: round-trip a hand-built store (format bytes committed as vector) + `Corrupt` cases (bad magic, truncated entry, wrong total_len).
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement path build (raw subject/issuer DER equality, depth ≤ 8, intermediates pool), per-signature verify dispatch on `sig_alg`, validity vs `now_unix`, `is_ca` enforcement for non-leaf, RSA modulus ≥ 2048, ECDSA curve/hash pairing (P-256/SHA-256, P-384/SHA-384), SHA-1 → `UnsupportedAlgorithm`, SAN-only hostname matching per policy; trust anchors are trusted by fiat (no anchor self-signature check).
- [ ] **Step 4:** Run — PASS + targeted `std_x509` verify/truststore fixtures + affected `run_crosscheck.sh` modules + 3× determinism. Full gate at Task 3 closeout.
- [ ] **Step 5:** Commit `feat(std_x509): chain verification + trust store (Phase1 M3)`.

### Task 3: `caconv` tool + store asset + docs + closeout

**Files:**
- Create: `examples/z98/demo/tls_demo/caconv/main.zig` (Z98 program)
- Create: `examples/z98/demo/tls_demo/caconv/README.md` (refresh recipe)
- Create: `examples/z98/demo/tls_demo/ca_store.bin` (first asset)
- Create: `sf/docs/std_lib/asn1.md`, `sf/docs/std_lib/x509.md`
- Modify: `STD_README.MD`, `README.md`, `docs/sf/QUICK_REF.md` (42→44 counts/rows)
- Modify: `scripts/seed/archive_seed.sh`, `scripts/seed/build_from_seed.sh`
- Rotate: `release/seed/` → **v115** (44 files)

**Interfaces:**
- Consumes: `std_base64.decode`, `std_x509`.
- Produces: `caconv <cacert.pem> <ca_store.bin>` → `wrote N anchors`; asset format §5.5.

- [ ] **Step 1:** Implement caconv (PEM scan `BEGIN CERTIFICATE` blocks, base64 decode, `x509Parse` each, write format §5.5 in file order; deterministic). Fixtures: tool run on a committed mini-PEM (3 certs) → expected store bytes (byte-exact golden committed); re-run 2× identical.
- [ ] **Step 2:** Generate `ca_store.bin` from the current Mozilla `cacert.pem` snapshot (commit the binary + record snapshot date/source in the README); verify `trustStoreLoad` reads it (count = anchors parsed).
- [ ] **Step 3:** Docs: asn1.md + x509.md (API + validation policy + error table); caconv README (download `cacert.pem` from curl.se, run tool, snapshot-date note); truth-ups to 3 docs; seed scripts counts.
- [ ] **Step 4:** Rotate seed v115; verify manifest 44 / archive md5 / fixed point `45158dcede81125a39a2c2c58478e21e` / hop1==hop2 (std-only; compiler source unchanged); full gate green on rotated compiler.
- [ ] **Step 5:** Commits `feat(demo): caconv CA-store converter (Phase1 M3)`, `docs(std_lib): asn1/x509 docs (M3)`, `chore(seed): rotate (M3)`, `docs(sdd): M3 closeout report`.
