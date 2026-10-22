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
  `ecdsa_aes_data.zig`, `ecdsa_chacha_data.zig`, `rsa_pss_data.zig`
  - exact `client_hello` / `client_flight` bytes
  - two-send action sequence then `Established`
  - exact early/handshake/master + four traffic secrets
  - captured server application data
  - client `tlsWrite` round-trip decrypted with the client app key; short
    output -> `OutputTooSmall` with no sequence advance
  - whole flight in one chunk and one-byte-at-a-time replay
- `repro/mi_matrix/stdlib_tls13_auth_xmod`
  - RSA-PSS baseline establishes
  - PKCS#1 v1.5 CertificateVerify -> `HandshakeFailed`
  - tampered server Finished -> `HandshakeFailed`
  - key_share group changed to secp256r1 -> `UnsupportedGroup`

Both dirs pinned in `scripts/stdlib/expected_dirs.txt`.

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
PASS repro/mi_matrix/stdlib_tls13_handshake_xmod
PASS repro/mi_matrix/stdlib_tls_record_xmod
...
run_fixtures: 329 PASS / 0 FAIL over 329 dirs
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

The same full gate was run three times (exit 0 each); the final run after the
source-header comment update also reported `329 PASS / 0 FAIL` and
`9 PASS / 0 FAIL` (`STDLIB GATE OK`).

## 6. 3x determinism

The harness runs every fixture program three times and compares stdout bytes.
The two new TLS 1.3 fixtures were additionally invoked three times:

```text
$ for i in 1 2 3; do
    bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean \
      repro/mi_matrix/stdlib_tls13_handshake_xmod \
      repro/mi_matrix/stdlib_tls13_auth_xmod
  done
tls13 run1 rc=0 run_fixtures: 2 PASS / 0 FAIL over 2 dirs
tls13 run2 rc=0 run_fixtures: 2 PASS / 0 FAIL over 2 dirs
tls13 run3 rc=0 run_fixtures: 2 PASS / 0 FAIL over 2 dirs
```

## 7. Notes / follow-ups (outside Task 1)

- Capture harness `/tmp/t3_cap/capture13.zig` and OpenSSL key logs are
  transient under `/tmp`; committed fixture data pins every derived secret.
- TLS 1.3 KeyUpdate is detected and returns `error.Closed` (no rekey support),
  as required by the task contract; NewSessionTicket is ignored.
- Interop tier, docs, seed rotation, and closeout belong to Task 2.
