# M3 Task 2 report — `x509VerifyChain` + trust store

Status: DONE

Branch: `zig1_improvements` (base `cbf48f9b`)

## Step 1 — failing fixtures

Added two pinned fixture dirs:

- `repro/mi_matrix/stdlib_x509_verify_xmod/` — committed DER chains + hand-built
  §5.5 store vectors (certificate bytes embedded through generated
  `certs_data.zig` / `vectors_data.zig`; no runtime file reads).
  - ECDSA P-256 leaf -> P-384 intermediate -> P-384 root, SHA-384 links.
  - RSA-2048 chain: SHA-256 root self-signature, SHA-384 intermediate link,
    SHA-512 leaf link.
  - ECDSA P-256 / SHA-256 chain.
  - Wildcard SAN leaf (`*.example.com`).
  - SHA-1 chain (`sha1WithRSAEncryption`) and RSA-1024 issuer.
  - 9-intermediate chain (leaf + 9 CAs + root) for `ChainTooLong`.
  - Bit-flipped ECDSA intermediate signature vector.
- `repro/mi_matrix/stdlib_truststore_xmod/` — hand-built 6-anchor store
  (`store_roundtrip.bin`) plus corrupt vectors: bad magic, truncated entry
  (correct `total_len`, last entry body short), and wrong `total_len`.

`scripts/stdlib/expected_dirs.txt` now pins both dirs.

Generation used host OpenSSL 3.0.22 once; the committed `.der`/`.bin` files are
the fixture source of truth (bytes embedded by the generated `.zig` arrays).

## Step 2 — run before implementation (expected FAIL)

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean repro/mi_matrix/stdlib_x509_verify_xmod repro/mi_matrix/stdlib_truststore_xmod
FAIL repro/mi_matrix/stdlib_x509_verify_xmod (DUMP-RC2)
    dump stderr:                                                                    ^^^^^^^^^^^^^^^
FAIL repro/mi_matrix/stdlib_truststore_xmod (DUMP-RC2)
    dump stderr:        ^^^^^
----------------------------------------
run_fixtures: 0 PASS / 2 FAIL over 2 dirs
failed: repro/mi_matrix/stdlib_x509_verify_xmod repro/mi_matrix/stdlib_truststore_xmod
exit=1
```

## Step 3 — implementation

`sf/src/std_x509.zig`:

- `X509VerifyError` = the exact §5.4 set; `TrustStoreError = {Corrupt, OutOfMemory}`.
- `TrustAnchor`, `TrustStore`, and `trustStoreLoad(arena, bytes, out)` implementing
  the pinned little-endian §5.5 format (`"Z98CA100"`, count, self-check
  `total_len`, per-entry header, arena-owned subject/SPKI copies).
- `x509VerifyChain(arena, leaf_der, intermediates, store, hostname, now_unix)`:
  - raw DER subject/issuer equality path build, intermediates pool, depth ≤ 8;
  - per-signature dispatch on `sig_alg`: ECDSA P-256/SHA-256, P-384/SHA-384,
    RSA PKCS#1 v1.5 SHA-256/384/512 with modulus ≥ 2048;
  - SHA-1 / RSA-PSS / unknown OIDs -> `UnsupportedAlgorithm`;
  - validity vs `now_unix` (`not_before`/`not_after` inclusive), `is_ca` for
    non-leaf issuers, anchors trusted by fiat (no self-signature check);
  - SAN dNSName-only hostname match: case-insensitive exact or one-leftmost-label
    `*.` wildcard; no CN/IP fallback.
- `Cert` gained an additive `tbs` slice (full TBSCertificate DER) so signatures
  can be checked over the exact signed bytes; the Task 1 SAN storage contract is
  unchanged.

Implementation notes found while running the fixtures:

- DER INTEGER → fixed-width conversion must treat a leading `0x00` as the
  positive sign octet (not reject a following high bit); RSA modulus parsing had
  the same bug. Fixed before the passing run.
- Z98 codegen for `[MAX_CHAIN]Cert = undefined` emitted an invalid initializer
  for `san_storage` (array of slices). The path now uses a compact `PathNode`
  (no nested array) and keeps the leaf `Cert` separately.
- A local string literal indexed in a loop generated invalid C; the store magic
  is checked with direct byte comparisons.

## Step 4 — targeted fixtures PASS + 3x determinism

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean repro/mi_matrix/stdlib_x509_verify_xmod repro/mi_matrix/stdlib_truststore_xmod
PASS repro/mi_matrix/stdlib_x509_verify_xmod
PASS repro/mi_matrix/stdlib_truststore_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
exit=0
```

Exact error assertions exercised by `stdlib_x509_verify_xmod` (each is checked
with `catch |e| ck(e == error.<Name>)`):

- `BadSignature` — bit flip in the ECDSA intermediate signature.
- `CertificateExpired` — `now_unix = not_after + 1`.
- `CertificateNotYetValid` — `now_unix = not_before - 1`.
- Valid at both boundaries (`not_before` / `not_after` inclusive).
- `UnknownIssuer` — ECDSA chain against an RSA-only store.
- `HostnameMismatch` — exact mismatch; `*.example.com` vs `a.b.example.com`;
  `*.example.com` vs `example.com`.
- `ChainTooLong` — 9-intermediate chain.
- `UnsupportedAlgorithm` — SHA-1 link and RSA-1024 issuer.
- `Corrupt` — empty leaf DER.

Trust-store assertions (`stdlib_truststore_xmod`): load the committed 6-anchor
vector, compare anchor 0/1 subject + SPKI bytes against the parsed root
certificates, check validity timestamps, and assert `Corrupt` for bad magic,
truncated entry, and wrong `total_len`.

3x determinism (existing parse fixture included because `Cert` gained a field):

```
$ for i in 1 2 3; do echo "=== run $i ==="; bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean repro/mi_matrix/stdlib_x509_parse_xmod repro/mi_matrix/stdlib_x509_verify_xmod repro/mi_matrix/stdlib_truststore_xmod; echo "exit=$?"; done
=== run 1 ===
PASS repro/mi_matrix/stdlib_x509_parse_xmod
PASS repro/mi_matrix/stdlib_x509_verify_xmod
PASS repro/mi_matrix/stdlib_truststore_xmod
----------------------------------------
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
exit=0
=== run 2 ===
PASS repro/mi_matrix/stdlib_x509_parse_xmod
PASS repro/mi_matrix/stdlib_x509_verify_xmod
PASS repro/mi_matrix/stdlib_truststore_xmod
----------------------------------------
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
exit=0
=== run 3 ===
PASS repro/mi_matrix/stdlib_x509_parse_xmod
PASS repro/mi_matrix/stdlib_x509_verify_xmod
PASS repro/mi_matrix/stdlib_truststore_xmod
----------------------------------------
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
exit=0
```

Crosscheck: no `run_crosscheck.sh` module imports `std_x509` (checked with
`grep -rln "std_x509\|x509" scripts/stdlib/ref scripts/stdlib/vectors
repro/mi_matrix/*cross_xmod`). Ran the full crosscheck set as the affected
baseline (no failures):

```
$ bash scripts/stdlib/run_crosscheck.sh /tmp/m2_t4_v114_build/zig1_5_clean
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
exit=0
```

Full stdlib gate, seed rotation, caconv, docs and compiler battery are deferred
to Task 3 per the brief.

## Round-1 review fix — truncated-entry vector

Review found that the original `corrupt_truncated_entry.bin` still carried
`total_len = 1275` while the file was 1274 bytes, so `trustStoreLoad` returned
`Corrupt` at the total-length self-check before reaching the entry-length check.
The fixture now keeps `total_len == file length` and truncates the last entry
body instead; the separate wrong-`total_len` vector is unchanged.

Byte-level check (entry 5 header declares 187 body bytes, only 186 remain):

```
$ python3 -c 'import struct; from pathlib import Path; b=Path("repro/mi_matrix/stdlib_truststore_xmod/vectors/corrupt_truncated_entry.bin").read_bytes(); print("len", len(b), "total_len", struct.unpack("<I", b[12:16])[0]); off=16; cnt=struct.unpack("<I",b[8:12])[0]
for i in range(cnt):
 sl,kl=struct.unpack("<HH",b[off:off+4]); rem=len(b)-(off+12); print("entry",i,"body",sl+kl,"remaining",rem,"OK" if sl+kl<=rem else "TRUNCATED"); off+=12+sl+kl'
len 1274 total_len 1274
entry 0 body 143 remaining 1246 OK
entry 1 body 315 remaining 1091 OK
entry 2 body 113 remaining 764 OK
entry 3 body 113 remaining 639 OK
entry 4 body 316 remaining 514 OK
entry 5 body 187 remaining 186 TRUNCATED
```

Re-ran the targeted parse/verify/truststore set 3x after regenerating
`vectors_data.zig`:

```
$ for i in 1 2 3; do echo "=== run $i ==="; bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean repro/mi_matrix/stdlib_x509_parse_xmod repro/mi_matrix/stdlib_x509_verify_xmod repro/mi_matrix/stdlib_truststore_xmod; echo "exit=$?"; done
=== run 1 ===
PASS repro/mi_matrix/stdlib_x509_parse_xmod
PASS repro/mi_matrix/stdlib_x509_verify_xmod
PASS repro/mi_matrix/stdlib_truststore_xmod
----------------------------------------
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
exit=0
=== run 2 ===
PASS repro/mi_matrix/stdlib_x509_parse_xmod
PASS repro/mi_matrix/stdlib_x509_verify_xmod
PASS repro/mi_matrix/stdlib_truststore_xmod
----------------------------------------
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
exit=0
=== run 3 ===
PASS repro/mi_matrix/stdlib_x509_parse_xmod
PASS repro/mi_matrix/stdlib_x509_verify_xmod
PASS repro/mi_matrix/stdlib_truststore_xmod
----------------------------------------
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
exit=0
```

## Step 5 — commit

Code/fixtures: `a911b286a04f6cf3e0a07e44b723150dc7bf7294` (initial);
`c39ece75c5461cad60c58ad636b808e5e3c8fd19` (round-1 truncated-entry fixture fix).

Report: this file (`df1741f1` initial report; this update is the separate
`docs(sdd)` commit).

## Concerns

- Path build picks the first CA intermediate whose raw subject matches the
  current issuer; it does not backtrack across multiple same-subject
  intermediates. Fixtures cover the specified pool shape, but browser-grade
  alternate-chain selection is not implemented.
- Trust-anchor validity is checked against `now_unix` (anchor signatures are not,
  per fiat). If the intended policy is to ignore anchor validity windows, this
  needs a spec ruling.
- `expected_dirs.txt` now contains the two new dirs; seed copy-lists are
  intentionally untouched until Task 3 (v115).
