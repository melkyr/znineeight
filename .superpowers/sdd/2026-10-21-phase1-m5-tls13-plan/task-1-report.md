# M5 Task 1 report — TLS 1.3 key schedule + handshake

Status: complete (Task 1 only; Task 2 interop/docs/seed pending).

## 1. Baseline / build environment

- Repo root `/workspace/znineeight`, branch `zig1_improvements`, base `5d08e17e`.
- Compiler `/tmp/m2_t4_v114_build/zig1_5_clean`
  (`md5sum` = `45158dcede81125a39a2c2c58478e21e`).
- Source under test synced only to `/tmp/m2_t4_v114_build/lib/std_tls.zig`
  (seed not rotated).

Existing TLS fixtures re-run after the std_tls changes:

```text
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean \
    repro/mi_matrix/stdlib_tls_record_xmod repro/mi_matrix/stdlib_tls12_handshake_xmod
PASS repro/mi_matrix/stdlib_tls_record_xmod
PASS repro/mi_matrix/stdlib_tls12_handshake_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
```

TLS 1.2 ClientHello wire image is preserved byte-for-byte (the 1.2-only
`sendClientHello` branch is the unchanged M4 body; the fixture's exact
`client_hello` comparison still passes).

## 2. Implementation (sf/src/std_tls.zig)

- Added `TLS_VERSION_13 = 0x0304`, 1.3 suites `0x1301`/`0x1303`,
  supported_versions / key_share / signature_algorithms extension IDs.
- Added TLS 1.3 record protection (`protectRecord13` / `unprotectRecord13`):
  per-record nonce = static IV XOR seq, AAD = 5-byte TLSCiphertext header,
  inner content type appended to plaintext.
- Added HKDF-Expand-Label, Derive-Secret, key/IV expansion, Finished HMAC and
  the no-PSK schedule: early secret = HKDF-Extract(0^32, 0^32), handshake
  secret, master secret, client/server handshake traffic secrets, then
  client/server application traffic secrets after the server Finished.
- 1.3 ClientHello offers x25519 key_share; 1.2 fallback still available when
  `min_version <= 1.2`; 1.3-only path uses only x25519.
- ServerHello parses supported_versions + key_share; non-x25519 key_share ->
  `error.UnsupportedGroup`.
- Certificate (1.3 framing with entry extensions), CertificateVerify
  (ECDSA P-256/SHA-256, ECDSA P-384/SHA-384, RSA-PSS SHA-256/SHA-384) and
  Finished (1.3 finished_key) implemented. PKCS#1 v1.5 CertificateVerify schemes
  are rejected with `error.HandshakeFailed`.
- Post-handshake 1.3 KeyUpdate is unsupported and returns `error.Closed`;
  NewSessionTicket is ignored. 1.3 middlebox-compat CCS is ignored.

## 3. Transcript capture from OpenSSL 3.0.22

TLS 1.3 capture tool: `/tmp/t3_cap/capture13.zig`, compiled by the seed
compiler and linked with the binding gcc flags. It connects to host
`openssl s_server` with `min_version = max_version = TLS_VERSION_13` and the
deterministic seed `0x0123456789ABCDEF`; `now_unix = 1800000000`.

TLS 1.2 fallback capture tool: `/tmp/t3_cap/capture_fallback.zig`, same client
but `min_version = TLS_VERSION_12`, `max_version = TLS_VERSION_13`. The
fallback transcript was captured from a real OpenSSL **TLS 1.2-only** server
(`-min_protocol TLSv1.2 -max_protocol TLSv1.2`), RSA certificate,
`ECDHE-RSA-AES128-GCM-SHA256`, forced handshake signature
`-sigalgs rsa_pss_rsae_sha256`. The captured ServerHello has no downgrade
sentinel (correct for a TLS 1.2-only peer), and its SKE uses
`rsa_pss_rsae_sha256` (0x0804), x25519 (0x001d). This same transcript backs
the positive fallback and the RSA-PSS SKE verifier test.

Server command (ECDSA cert / AES-128-GCM TLS 1.3 example):

```text
$ openssl s_server -accept 18451 -cert /tmp/t2_cap/leaf_ecdsa.pem \
    -key /tmp/t2_cap/leaf_ecdsa.key -CAfile /tmp/t2_cap/ca.pem -tls1_3 \
    -ciphersuites TLS_AES_128_GCM_SHA256 -groups X25519 -www \
    -keylogfile /tmp/t3_cap/rec_ecdsa_aes.keylog -naccept 1
$ /tmp/t3_cap/capture13 18451 /tmp/t2_cap/ca_store.bin \
    repro/mi_matrix/stdlib_tls13_handshake_xmod/ecdsa_aes_data.zig
captured tls13
```

OpenSSL key log (current `ecdsa_aes_data.zig` transcript):

```text
SERVER_HANDSHAKE_TRAFFIC_SECRET ... 71802ba6afa17f108b8bbc60e8a880aed89749a0b11e0759c8a3c15f553e9969
CLIENT_HANDSHAKE_TRAFFIC_SECRET ... 64eeaba67caf9bc6c4e909f8cdf1b7a7a20c9e2b6ea48d0490b1e58365d58a02
SERVER_TRAFFIC_SECRET_0         ... 81280317aa2d2e76fbcf6e16620f6d420d90d74b59f2ad8946523cdaf4d6d648
CLIENT_TRAFFIC_SECRET_0         ... f010480d54e2b833218d4dbdc14703793f63d98aebf631d955ef615176616d94
```

Independent comparison (capture output vs key log) for all four current TLS 1.3
transcripts:

```text
ecdsa_aes_data.zig     True server 6171 ch 143 flight 58 pkcs1 6171 badfin 6171 fend 1744
ecdsa_chacha_data.zig  True server 6196 ch 143 flight 58 pkcs1 6196 badfin 6196 fend 1745
rsa_pss_data.zig       True server 6551 ch 143 flight 58 pkcs1 6551 badfin 6551 sha1 6551 fend 2133
p384_data.zig          True server 6179 ch 143 flight 58 pkcs1 6179 badfin 6179 fend 1759
```

`True` means all four derived traffic secrets (client/server handshake and
client/server application) equal the OpenSSL key-log bytes. The captured
arrays also pin `early_secret`, `handshake_secret`, `master_secret`.

Current fallback transcript sizes: `server_raw 4068`, `client_hello 163`,
`client_flight 93`, `app_plain 1947`.

## 4. Targeted fixtures

New fixture dirs:

- `repro/mi_matrix/stdlib_tls13_handshake_xmod`
  `ecdsa_aes_data.zig`, `ecdsa_chacha_data.zig`, `rsa_pss_data.zig`,
  `p384_data.zig`
  - exact `client_hello` / `client_flight` bytes
  - two-send action sequence then `Established`
  - exact early/handshake/master + four traffic secrets
  - captured server application data
  - client `tlsWrite` round-trip decrypted with the client app key; short
    output -> `OutputTooSmall` with no sequence advance
  - exact-max 1.3 AEAD record (16384 content + inner type = 16385 plaintext)
    fed through `tlsStep`/`tlsRead`
  - true whole-flight single-chunk replay and one-byte-at-a-time replay
- `repro/mi_matrix/stdlib_tls13_auth_xmod`
  - RSA-PSS baseline establishes
  - PKCS#1 v1.5 CertificateVerify (0x0201 SHA-1 and 0x0401 SHA-256) ->
    `HandshakeFailed`
  - tampered server Finished tag -> `HandshakeFailed`
  - re-sealed Finished with valid AEAD tag but wrong 32-byte verify_data ->
    `HandshakeFailed` (exercises `verifyFinished13`)
  - key_share group changed to secp256r1 -> `UnsupportedGroup`
- `repro/mi_matrix/stdlib_tls13_fallback_xmod`
  - combined 1.3+1.2 ClientHello replayed against a real TLS 1.2-only server
    transcript with NO downgrade sentinel: allowed by RFC 8446, completes the
    fallback (`Established`, TLS 1.2, ECDHE-RSA-AES128-GCM-SHA256, app data)
  - asserts the SKE is x25519 and `rsa_pss_rsae_sha256` (0x0804), positively
    exercising the new TLS 1.2 RSA-PSS SKE verifier branch
  - writing `DOWNGRD\x01` into ServerHello.random -> `HandshakeFailed` at
    ServerHello (RFC 8446 abort semantics)
  - direct `hasDowngradeSentinel` true/false/mismatch checks

All three dirs pinned in `scripts/stdlib/expected_dirs.txt`.

```text
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean \
    repro/mi_matrix/stdlib_tls13_handshake_xmod \
    repro/mi_matrix/stdlib_tls13_auth_xmod \
    repro/mi_matrix/stdlib_tls13_fallback_xmod
PASS repro/mi_matrix/stdlib_tls13_handshake_xmod
PASS repro/mi_matrix/stdlib_tls13_auth_xmod
PASS repro/mi_matrix/stdlib_tls13_fallback_xmod
----------------------------------------
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
```

## 5. Full stdlib gate + crosscheck

```text
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m2_t4_v114_build/zig1_5_clean
...
PASS repro/mi_matrix/stdlib_tls12_handshake_xmod
PASS repro/mi_matrix/stdlib_tls13_auth_xmod
PASS repro/mi_matrix/stdlib_tls13_fallback_xmod
PASS repro/mi_matrix/stdlib_tls13_handshake_xmod
PASS repro/mi_matrix/stdlib_tls_record_xmod
...
run_fixtures: 330 PASS / 0 FAIL over 330 dirs
== std-lib crosscheck gate ==
PASS smoke (3 vectors)
PASS std_hpa (8 vectors)
PASS std_lz4 (20 vectors)
PASS std_noise (1 vectors)
PASS std_num (1 vectors)
PASS std_pathfind (2 vectors)
PASS std_physics (1 vectors)
PASS std_rand (2 vectors)
PASS std_zstd (30 vectors)
----------------------------------------
run_crosscheck: 9 PASS / 0 FAIL over 9 modules
STDLIB GATE OK
```

The full gate was rerun after the fix round and reported
`330 PASS / 0 FAIL` and `9 PASS / 0 FAIL` (`STDLIB GATE OK`).

## 6. 3x determinism

The harness runs every fixture program three times and compares stdout bytes.
All five TLS fixtures were additionally invoked three times:

```text
$ for i in 1 2 3; do
    bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean \
      repro/mi_matrix/stdlib_tls_record_xmod \
      repro/mi_matrix/stdlib_tls12_handshake_xmod \
      repro/mi_matrix/stdlib_tls13_handshake_xmod \
      repro/mi_matrix/stdlib_tls13_auth_xmod \
      repro/mi_matrix/stdlib_tls13_fallback_xmod
  done
run1 rc=0 run_fixtures: 5 PASS / 0 FAIL over 5 dirs
run2 rc=0 run_fixtures: 5 PASS / 0 FAIL over 5 dirs
run3 rc=0 run_fixtures: 5 PASS / 0 FAIL over 5 dirs
```

## 7. Fix round 1 (review findings)

1. Max-size 1.3 record: `handleRecord` now decrypts into
   `[TLS_MAX_PLAINTEXT_RECORD + 1]u8` (16385) for the 1.3 inner plaintext.
   `stdlib_tls13_handshake_xmod` adds an exact-max test: a record carrying
   16384 content bytes plus inner type is protected, fed through `tlsStep`,
   and read back byte-for-byte.
2. Downgrade sentinel predicate: `hasDowngradeSentinel` checks
   `ServerHello.random[24..32] == "DOWNGRD\x01"`. Final call-site semantics
   were corrected in round 2 (abort when present; absence is normal).
3. Combined fallback signature schemes: `verifyServerKeyExchange` now handles
   the full advertised set: ECDSA SHA-256/SHA-384 and RSA PKCS#1 SHA-256 plus
   RSA-PSS SHA-256/SHA-384 (salt = digest length), using the existing
   `std_ecc` P-384 and `std_crypto.rsaVerifyPss` primitives.
4. `rsa_pkcs1_sha1` 0x0201 now maps to `HandshakeFailed`; the auth fixture
   replays a re-sealed CV with 0x0201 as well as 0x0401.
5. Bad Finished: the auth fixture keeps the tag-flip negative and adds a
   pre-sealed record with a valid AEAD tag but wrong 32-byte verify_data, so
   `verifyFinished13` itself rejects it.
6. One-chunk claim: the handshake fixture now truly replays the whole server
   flight in one chunk (in addition to the one-byte-at-a-time run).
7. `tlsWrite` 1.2 ChaCha20 overhead restored to 16 bytes (17 only for 1.3).
   The TLS 1.2 handshake fixture adds an exact-fit 17042-byte write test.
8. CertificateVerify accepts only the advertised PSS schemes (0x0804/0x0805)
   and requires an empty 1.3 Certificate request context.
9. `std_tls.zig` header comment now states 1.2 Finished = 12 bytes, 1.3
   Finished = 32 bytes, and that the ClientHello offers the 1.3 suites.
10. P-384: added `p384_data.zig` (ECDSA P-384 certificate, RSA/ECDSA key
    exchange x25519) and a fourth handshake scenario exercising
    `ecdsa_secp384r1_sha384` CertificateVerify. Its traffic secrets match the
    OpenSSL key log.

## 7.1 Fix round 2

- Corrected the downgrade check to RFC 8446 §4.1.3 semantics: when a 1.3
  client receives a 1.2 ServerHello, abort only if
  `random[24..32] == "DOWNGRD\x01"`; absence is normal and accepted.
- Rewrote `stdlib_tls13_fallback_xmod` as a positive fallback fixture:
  combined 1.3+1.2 ClientHello + real TLS 1.2-only server flight without the
  sentinel completes (`Established`, TLS 1.2, ECDHE-RSA-AES128-GCM-SHA256,
  captured application data). A sentinel-injected copy aborts at ServerHello.
- Fixture provenance: OpenSSL TLS 1.2-only server, RSA certificate,
  `-cipher ECDHE-RSA-AES128-GCM-SHA256 -sigalgs rsa_pss_rsae_sha256
  -groups X25519`, `capture_fallback.zig` (`min=TLS1.2, max=TLS1.3`).
  The fixture asserts the SKE group is x25519 and the signature algorithm is
  `rsa_pss_rsae_sha256` (0x0804), so at least one new TLS 1.2 SKE branch
  (RSA-PSS) is positively exercised at runtime.
- Stale report key-log/length figures replaced with current values:
  6171 / 6196 / 6551 / 6179 for server_raw; fallback 4068/163/93/1947.

## 8. Notes / follow-ups (outside Task 1)

- Capture harness `/tmp/t3_cap/capture13.zig` and OpenSSL key logs are
  transient under `/tmp`; committed fixture data pins every derived secret.
- TLS 1.3 KeyUpdate is detected and returns `error.Closed` (no rekey support),
  as required by the task contract; NewSessionTicket is ignored.
- Interop tier, docs, seed rotation, and closeout belong to Task 2.
