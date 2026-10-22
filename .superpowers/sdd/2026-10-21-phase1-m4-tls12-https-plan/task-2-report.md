# M4 Task 2 report — TLS 1.2 handshake

Branch: `zig1_improvements` (base `4151bf96`).
Scope: Task 2 only (TLS 1.2 handshake + fixture); no demo/tier/docs/seed rotation/full gate.

## Environment

- Repo root `/workspace/znineeight`.
- Seed-built compiler `/tmp/m2_t4_v114_build/zig1_5_clean`
  md5 `45158dcede81125a39a2c2c58478e21e`.
- Host `openssl 3.0.22`; local `openssl s_server` used to capture transcripts.
- Targeted gate: `bash scripts/stdlib/run_fixtures.sh <zig1> <dir>` (each
  invocation runs every program 3× internally).

## Step 1 — fixture scaffold + canned transcripts

Created `repro/mi_matrix/stdlib_tls12_handshake_xmod/` with the driver, two
generated transcript data files, and golden `expected.txt` / `expected.rc`.

Fixture covers:

- ECDHE-ECDSA / AES-128-GCM-SHA256
- ECDHE-RSA / CHACHA20-POLY1305-SHA256
- ECDHE-ECDSA replay fed one byte at a time (fragmented Certificate record /
  fragmented TCP input), asserting the meaningful action sequence
  `ClientHello send → client-flight send → established`
- negatives: tampered server Finished `→ HandshakeFailed`; `now_unix = 2100`
  `→ CertificateExpired`; hostname with no SAN match `→ HostnameMismatch`

The fixture pins the exact deterministic `ClientHello` and client flight
(`ClientKeyExchange + ChangeCipherSpec + Finished`) bytes, so a transcript or
Finished/key-schedule regression is a byte mismatch, not a silent pass. No
runtime file reads: trust-store bytes and full server transcripts are embedded.

### Transcript capture (host openssl)

Certificates / trust store:

```
cd /tmp/t2_cap
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.pem \
  -days 3650 -subj "/CN=Z98 Test CA" -sha256
openssl ecparam -name prime256v1 -genkey -noout -out leaf_ecdsa.key
openssl req -new -key leaf_ecdsa.key -subj "/CN=localhost" -out leaf_ecdsa.csr
openssl x509 -req -in leaf_ecdsa.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -days 3650 -sha256 -extfile ext.cnf -out leaf_ecdsa.pem
openssl genrsa -out leaf_rsa.key 2048
openssl req -new -key leaf_rsa.key -subj "/CN=localhost" -out leaf_rsa.csr
openssl x509 -req -in leaf_rsa.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -days 3650 -sha256 -extfile ext.cnf -out leaf_rsa.pem
```

Observed (ext.cnf has `subjectAltName=DNS:localhost`,
`basicConstraints=CA:FALSE`, `keyUsage=digitalSignature`,
`extendedKeyUsage=serverAuth`):

```
notBefore=Oct 22 20:27:37 2026 GMT
notAfter=Oct 19 20:27:37 2036 GMT
X509v3 Subject Alternative Name: DNS:localhost
```

Trust store via the existing `caconv` (seed compiler + sibling lib):

```
$ /tmp/t2_cap/caconv_out/caconv /tmp/t2_cap/ca.pem /tmp/t2_cap/ca_store.bin
wrote 1 anchors
```

Deterministic capture harness (`/tmp/t2_cap/capture.zig`, not committed) uses
`TlsSession`/`tlsStep` with fixed seed `0x0123456789abcdef`, hostname
`localhost`, `now_unix = 1800000000`, dumps every received server byte, the two
client sends, and the decrypted application plaintext.

```
$ nohup openssl s_server -accept 24443 -tls1_2 \
    -cipher ECDHE-ECDSA-AES128-GCM-SHA256 \
    -cert leaf_ecdsa.pem -key leaf_ecdsa.key -groups P-256 -www -quiet -naccept 1 &
$ ./capout/capture 24443 ca_store.bin ecdsa_aes_data.zig
captured

$ nohup openssl s_server -accept 24444 -tls1_2 \
    -cipher ECDHE-RSA-CHACHA20-POLY1305 \
    -cert leaf_rsa.pem -key leaf_rsa.key -groups P-256 -www -quiet -naccept 1 &
$ ./capout/capture 24444 ca_store.bin rsa_chacha_data.zig
captured
```

Resulting embedded files:

```
ecdsa_aes_data.zig   31906 bytes  finished_record_end = 950
rsa_chacha_data.zig  34022 bytes  finished_record_end = 1329
```

## Step 2 — initial targeted FAIL

Before the handshake symbols existed, the seed compiler rejected the fixture
(the names resolved as `void`, so every `try tlsStep`/`tlsRead` was invalid).

```
$ /tmp/m2_t4_v114_build/zig1_5_clean -ffast -o /tmp/t2_fail \
    repro/mi_matrix/stdlib_tls12_handshake_xmod/main.zig
repro/.../main.zig:79:4: error[3000]: cannot declare variable of type void
    var cfg = tls.TlsConfig{
...
repro/.../main.zig:92:18: error[3075]: expected error union type, found 'void'
    const first = try tls.tlsStep(&g_session, "", out[0..]);
...
rc=2
```

Expected FAIL confirmed.

## Step 3 — implementation

Extended `sf/src/std_tls.zig` (record layer unchanged):

- Public §5.6 surface: `TlsAction`, `TlsConfig` (`now_unix`), `TlsSession`,
  `tlsInit`, `tlsStep`, `tlsRead`, `tlsWrite`; explicit states
  `SendClientHello … Established`; 12-byte Finished verify_data.
- ClientHello: SNI required, TLS 1.2, all four ECDHE-{ECDSA,RSA}-
  {AES_128_GCM,CHACHA20_POLY1305} suites, groups secp256r1 + x25519,
  signature_algorithms ECDSA-SHA256 + RSA-PKCS1-SHA256.
- Server flight: ServerHello, Certificate, ServerKeyExchange, ServerHelloDone;
  Certificate chain validated with `std_x509.x509VerifyChain` against the
  supplied `TrustStore` using `cfg.hostname` / `cfg.now_unix`.
- ServerKeyExchange signature: ECDSA P-256 (DER r/s) or RSA PKCS#1 v1.5 over
  `client_random || server_random || ServerECDHParams`.
- ECDHE: P-256 (`p256Generate`/`p256Ecdh`) and x25519 (`x25519Base`/`x25519`);
  ClientKeyExchange + client CCS + encrypted client Finished.
- Transcript: SHA-256 over every handshake message (record headers excluded);
  PRF_SHA256 master secret + key expansion; AES-GCM and ChaCha20-Poly1305 key /
  fixed-IV lengths; CCS then Finished in both directions.
- `tlsRead` buffers decrypted application data; `tlsWrite` fragments below the
  16384-byte protected-record cap (max 16360 plaintext).
- Pre-Established failures fail closed; Finished unprotect/verify failures map
  to `error.HandshakeFailed`.

Fixture transcript data was captured after the state machine existed, then
embedded; the fixture still pinned the same deterministic seed/bytes.

## Step 4 — targeted gates

Direct fixture run (echoes harness result):

```
$ .../prog
tls handshake ok
rc=0
```

Targeted fixtures, 3×:

```
$ for i in 1 2 3; do
    bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean \
      repro/mi_matrix/stdlib_tls12_handshake_xmod \
      repro/mi_matrix/stdlib_tls_record_xmod \
      repro/mi_matrix/stdlib_x509_verify_xmod \
      repro/mi_matrix/stdlib_x509_parse_xmod \
      repro/mi_matrix/stdlib_x25519_xmod \
      repro/mi_matrix/stdlib_crypto_prf_xmod \
      repro/mi_matrix/stdlib_crypto_sha256_xmod \
      repro/mi_matrix/stdlib_ecc_verify_xmod
  done
```

Observed each run:

```
PASS repro/mi_matrix/stdlib_tls12_handshake_xmod
PASS repro/mi_matrix/stdlib_tls_record_xmod
PASS repro/mi_matrix/stdlib_x509_verify_xmod
PASS repro/mi_matrix/stdlib_x509_parse_xmod
PASS repro/mi_matrix/stdlib_x25519_xmod
PASS repro/mi_matrix/stdlib_crypto_prf_xmod
PASS repro/mi_matrix/stdlib_crypto_sha256_xmod
PASS repro/mi_matrix/stdlib_ecc_verify_xmod
----------------------------------------
run_fixtures: 8 PASS / 0 FAIL over 8 dirs
exit=0
```

Default `-fsafe` smoke (3 runs), same binding gcc flags:

```
$ bash scripts/stdlib/run_crypto_safe.sh /tmp/m2_t4_v114_build/zig1_5_clean \
    repro/mi_matrix/stdlib_tls12_handshake_xmod
PASS repro/mi_matrix/stdlib_tls12_handshake_xmod (md5=d890c5ae4ad2c1d040aeec5a86b4375b rc=0)
run_crypto_safe: 1 PASS / 0 FAIL over 1 dirs
exit=0
```

Affected crosscheck module (`std_rand` is the only crosscheck-covered import):

```
$ bash scripts/stdlib/run_crosscheck.sh /tmp/m2_t4_v114_build/zig1_5_clean std_rand
PASS std_rand (2 vectors)
run_crosscheck: 1 PASS / 0 FAIL over 1 modules
exit=0
```

Full stdlib gate deliberately deferred to Task 4 closeout.

## Step 5 — commits

- Code/fixtures commit: `3b98ebb3d35b1ab609668db72f616da22034f3e3`
  `feat(std_tls): TLS 1.2 handshake (Phase1 M4)`
- Report commit: this commit
  `docs(sdd): M4 T2 report`

No changes to `progress.md` or `run.err`.

## Concerns

- Canned transcripts use P-256 ECDHE; the x25519 code path is implemented but
  not covered by a committed transcript (brief specifies the two suites +
  fragmented Certificate, not a third x25519 capture).
- Only ECDSA-SHA256 / RSA-PKCS1-SHA256 server-key-exchange signatures are
  offered/accepted (matching the four SHA-256 suites); SHA-384 signature
  variants are out of scope for this task.
- Full stdlib gate and seed rotation remain Task 4.
