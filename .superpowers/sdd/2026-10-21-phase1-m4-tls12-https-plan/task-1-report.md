# M4 Task 1 report — record layer + `std_http` transport

Branch: `zig1_improvements` (base `6124dcf1`).
Scope: Task 1 only (record layer + `httpGetOver`); no handshake/demo/tier/docs/seed/battery.

## Environment

- Seed-built compiler: `/tmp/m2_t4_v114_build/zig1_5_clean`
  md5 `45158dcede81125a39a2c2c58478e21e`
- Seed sibling `lib/` initially 44 files (no `std_tls.zig`), `lib/std_http.zig`
  md5 `1c6657c16b99737cd686c501483b6a01` == repo pre-change.
- Targeted gate: `scripts/stdlib/run_fixtures.sh`.

## Step 1 — failing fixtures created

Created:
- `repro/mi_matrix/stdlib_tls_record_xmod/{main.zig,expected.txt,expected.rc}`
- `repro/mi_matrix/stdlib_http_transport_xmod/{main.zig,expected.txt,expected.rc}`
- pinned both dirs in `scripts/stdlib/expected_dirs.txt`.

Fixture contracts: deterministic stdout `tls record ok` / `http transport ok`, rc 0.

## Step 2 — targeted run FAIL (before implementation)

Command:

```
bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean repro/mi_matrix/stdlib_tls_record_xmod repro/mi_matrix/stdlib_http_transport_xmod
```

Observed:

```
FAIL repro/mi_matrix/stdlib_tls_record_xmod (DUMP-RC2)
    dump stderr:                  ^^^
FAIL repro/mi_matrix/stdlib_http_transport_xmod (DUMP-RC2)
    dump stderr:    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
----------------------------------------
run_fixtures: 0 PASS / 2 FAIL over 2 dirs
failed: repro/mi_matrix/stdlib_tls_record_xmod repro/mi_matrix/stdlib_http_transport_xmod
```

Direct compiler diagnostics (same seed):

```
$ /tmp/m2_t4_v114_build/zig1_5_clean -ffast -o /tmp/t1_fail_tls repro/mi_matrix/stdlib_tls_record_xmod/main.zig
error[3048]: could not resolve imported file 'std_tls.zig'
repro/mi_matrix/stdlib_tls_record_xmod/main.zig:60:14: error[20]: identifier 'tls' is not declared or imported in this module

$ /tmp/m2_t4_v114_build/zig1_5_clean -ffast -o /tmp/t1_fail_http repro/mi_matrix/stdlib_http_transport_xmod/main.zig
repro/mi_matrix/stdlib_http_transport_xmod/main.zig:94:4: error[3000]: cannot declare variable of type void
```

Expected FAIL confirmed (module/symbols do not exist yet).

## Step 3 — implementation

Created `sf/src/std_tls.zig` (record layer only):

- 5-byte header codec: `encodeRecord`, `parseRecordHeader`, `decodeRecord`;
  `TLS_MAX_RECORD = 16384`, declared/encoded over-cap -> `error.RecordTooLarge`.
- `RecordReader` incremental buffer (`start`/`len`, memmove compaction on append):
  fragmented header/payload, `readerMarkClosed` -> `error.Closed` at a record
  boundary, truncated close -> `error.Corrupt`.
- AEAD seam: `recordAad` (seq || type || version || plaintext_len),
  `recordNonce`, `sealFragment`/`openFragment` (raw AAD edge for KATs).
- Suites `ecdsa_aes_128_gcm_sha256` / `rsa_aes_128_gcm_sha256` (RFC 5288:
  fixed_iv[4] || explicit[8], explicit = seq on the wire, AAD as above) and
  `ecdsa_chacha20_poly1305_sha256` / `rsa_chacha20_poly1305_sha256`
  (RFC 7905: nonce = (0x00^4 || seq_be64) XOR fixed_iv[12], no explicit nonce).
- `protectRecord`/`unprotectRecord`; tag tamper -> `AuthenticationFailed`,
  malformed length -> `Corrupt`, plaintext > 16 KiB -> `RecordTooLarge`.

Modified `sf/src/std_http.zig` (`get()`/`parseUrl` http behavior unchanged):

- `HttpTransport { state, read_fn, write_fn, close_fn }`.
- `httpGetOver(arena, transport, url, out)`: GET, HTTP/1.1, `Host:` (port only
  when non-default), `Connection: close`; accepts `http://` and `https://` for
  the transport path (443 default); identity (Content-Length or close-delimited)
  and RFC 7230 §4.1 chunked decode (extensions + trailers), body cap 1 MiB;
  `close_fn` always called. Fixed 4 KiB transport read scratch + 8 KiB header
  cap.
- Pulled authority/path parsing into `parseAuthorityUrl` so `parseUrl` keeps
  rejecting non-http exactly as before.

Seed-built compiler resolves std modules from its sibling `lib/`; for targeted
and full runs only (seed rotation is Task 4) refreshed that test copy:

```
$ cp sf/src/std_tls.zig sf/src/std_http.zig /tmp/m2_t4_v114_build/lib/
$ ls /tmp/m2_t4_v114_build/lib | wc -l
45
```

## Step 4 — targeted PASS + 3x determinism

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean repro/mi_matrix/stdlib_tls_record_xmod repro/mi_matrix/stdlib_http_transport_xmod
PASS repro/mi_matrix/stdlib_tls_record_xmod
PASS repro/mi_matrix/stdlib_http_transport_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
exit=0
```

3x determinism (each invocation also runs every program 3x internally):

```
$ for i in 1 2 3; do echo "=== run $i ==="; bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean repro/mi_matrix/stdlib_tls_record_xmod repro/mi_matrix/stdlib_http_transport_xmod; echo "exit=$?"; done
=== run 1 ===
PASS repro/mi_matrix/stdlib_tls_record_xmod
PASS repro/mi_matrix/stdlib_http_transport_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
exit=0
=== run 2 ===
PASS repro/mi_matrix/stdlib_tls_record_xmod
PASS repro/mi_matrix/stdlib_http_transport_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
exit=0
=== run 3 ===
PASS repro/mi_matrix/stdlib_tls_record_xmod
PASS repro/mi_matrix/stdlib_http_transport_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
exit=0
```

Default-mode (`-fsafe`) smoke (no `-ffast`), same binding gcc flag set, 3 runs:

```
$ bash scripts/stdlib/run_crypto_safe.sh /tmp/m2_t4_v114_build/zig1_5_clean repro/mi_matrix/stdlib_tls_record_xmod repro/mi_matrix/stdlib_http_transport_xmod
PASS repro/mi_matrix/stdlib_tls_record_xmod (md5=f5db0513d91cdbce2e892baff92b16e4 rc=0)
PASS repro/mi_matrix/stdlib_http_transport_xmod (md5=82839ec3841621adf2f842b0925798cb rc=0)
----------------------------------------
run_crypto_safe: 2 PASS / 0 FAIL over 2 dirs
exit=0
```

## Step 4 — full std gate + full crosscheck (required: std_http edited)

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m2_t4_v114_build/zig1_5_clean
...
PASS repro/mi_matrix/stdlib_http_transport_xmod
...
PASS repro/mi_matrix/stdlib_tls_record_xmod
...
run_fixtures: 326 PASS / 0 FAIL over 326 dirs
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
exit=0
```

Full log: `/tmp/t1_full_gate2.log` (gate rc 0).

## Step 5 — commits

```
$ git rev-parse HEAD   # after feat(std_tls)
962f83289085f3d4903edf3311afd079eb1cbe19

$ git rev-parse HEAD   # after feat(std_http)
385f31a8015ecffa8ed27f136cebfdafb8177b22
```

- `962f8328` `feat(std_tls): record layer (Phase1 M4)`
  (std_tls.zig + record fixture + pin)
- `385f31a8` `feat(std_http): HttpTransport vtable (Phase1 M4)`
  (std_http.zig + transport fixture + pin)

No changes to `progress.md` or `run.err`. Seed rotation left to Task 4.
