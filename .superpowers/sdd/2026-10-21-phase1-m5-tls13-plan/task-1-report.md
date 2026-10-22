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

Capture tool: `/tmp/t3_cap/capture13.zig`, compiled by the seed compiler and
linked with the binding gcc flags. It connects to host `openssl s_server`
with `min_version = max_version = TLS_VERSION_13` and the deterministic seed
`0x0123456789ABCDEF`; `now_unix = 1800000000`.

Server command (ECDSA cert / AES-128-GCM example):

```text
$ openssl s_server -accept 18448 -cert /tmp/t2_cap/leaf_ecdsa.pem \
    -key /tmp/t2_cap/leaf_ecdsa.key -CAfile /tmp/t2_cap/ca.pem -tls1_3 \
    -ciphersuites TLS_AES_128_GCM_SHA256 -groups X25519 -www \
    -keylogfile /tmp/t3_cap/run6.keylog -naccept 1
$ /tmp/t3_cap/capture13 18448 /tmp/t2_cap/ca_store.bin \
    /tmp/t3_cap/out6.zig
captured tls13
```

OpenSSL key log (exact traffic secrets):

```text
SERVER_HANDSHAKE_TRAFFIC_SECRET ... dfafc4c5c44cd85988e0307c32a5d0297910db418b9b60b8d7d87b204bcb1108
CLIENT_HANDSHAKE_TRAFFIC_SECRET ... ccb639ce46ff68174a46bbd746150a10a53c612734256ac6d033ffacfbc70a02
SERVER_TRAFFIC_SECRET_0         ... 048320a29f89262b4da90fe22d01b67097f1dea747b4e75ed1c59de0ae754079
CLIENT_TRAFFIC_SECRET_0         ... b944df3da72dd71faaf873b44eef484100d9dbbdf84534abcfe6a83b70c2191b
```

Independent comparison (capture output vs key log) for all three transcripts:

```text
$ python3 - <<'PY'   # parse data arrays + keylog lines
... compares client_hs/server_hs/client_app/server_app ...
PY
ecdsa_aes_data.zig    True server 6163 pkcs1 6163 fend 1745
ecdsa_chacha_data.zig True server 6193 pkcs1 6193 fend 1746
rsa_pss_data.zig      True server 6546 pkcs1 6546 fend 2133
```

`True` means all four derived traffic secrets equal the OpenSSL key-log bytes.
The captured arrays also pin `early_secret`, `handshake_secret`, `master_secret`.

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
  - combined 1.3+1.2 ClientHello replayed against a real TLS 1.2 server
    transcript without the downgrade sentinel -> `HandshakeFailed` at
    ServerHello
  - patched ServerHello.random with the sentinel progresses past ServerHello
    to the ServerKeyExchange signature check (proves the positive sentinel
    branch is reached)
  - direct `hasDowngradeSentinel` true/false/mismatch checks

All three dirs pinned in `scripts/stdlib/expected_dirs.txt`.

```text
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean \
    repro/mi_matrix/stdlib_tls13_handshake_xmod repro/mi_matrix/stdlib_tls13_auth_xmod
PASS repro/mi_matrix/stdlib_tls13_handshake_xmod
PASS repro/mi_matrix/stdlib_tls13_auth_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
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
2. Downgrade sentinel: `hasDowngradeSentinel` checks
   `ServerHello.random[24..32] == "DOWNGRD\x01"` whenever the client offered
   1.3 and the server negotiated 1.2; absent -> `HandshakeFailed`.
   `stdlib_tls13_fallback_xmod` replays a real combined-ClientHello/TLS-1.2
   server flight without the sentinel (fails closed at ServerHello), then a
   sentinel-patched copy that reaches the ServerKeyExchange signature check.
   Direct helper checks cover true/false/mismatch.
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

Fallback-fixture limitation: a stock 1.3-capable OpenSSL server always
negotiates 1.3 when the client offers it; `-max_protocol TLSv1.2` disables the
sentinel. The fixture therefore uses a real TLS 1.2-only server response for
the absent-sentinel rejection and a sentinel-patched copy to prove the positive
branch reaches SKE. A full positive 1.2 handshake would require re-signing a
captured ServerKeyExchange and re-sealing Finished, which is outside Task 1.

## 8. Notes / follow-ups (outside Task 1)

- Capture harness `/tmp/t3_cap/capture13.zig` and OpenSSL key logs are
  transient under `/tmp`; committed fixture data pins every derived secret.
- TLS 1.3 KeyUpdate is detected and returns `error.Closed` (no rekey support),
  as required by the task contract; NewSessionTicket is ignored.
- Interop tier, docs, seed rotation, and closeout belong to Task 2.
