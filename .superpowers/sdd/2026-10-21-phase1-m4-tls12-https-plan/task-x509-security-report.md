# M3 security carry-over — X.509 path, key size, signature algorithm

Status: DONE (targeted + full gates green)
Branch: `zig1_improvements` (base `8ae40ffa`)

## 1. `sf/src/std_x509.zig`

- `x509VerifyChain` now builds the path with a bounded DFS over
  same-subject intermediates (`findPath`, fixed `[MAX_CHAIN]` path/used-index
  arrays, `MAX_CHAIN = 8`). Each anchor candidate is signature-checked before
  acceptance; a `BadSignature`/`UnsupportedAlgorithm` branch returns to the
  caller and the next same-subject intermediate is tried. Cycles are rejected by
  `usedContains` and raw `tbs` equality (`pathContains`).
- Failure precedence preserves the old distinctions: a path that reaches an
  anchor but fails signature verification returns `BadSignature` (or
  `UnsupportedAlgorithm`), a chain that needs another level past `MAX_CHAIN`
  returns `ChainTooLong`, and no usable candidate returns `UnknownIssuer`.
- The leaf's own RSA SPKI is checked before path building; modulus < 2048 bits
  returns `UnsupportedAlgorithm` (issuer RSA keys were already checked in
  `verifySignature`).
- `x509Parse` compares the TBS inner `signature` AlgorithmIdentifier OID with the
  outer `signatureAlgorithm` OID using raw OID bytes; mismatch returns
  `error.Corrupt`.

## 2. Fixtures

Generated once with host OpenSSL 3.0.22, fixed validity
`20240101000000Z..20300101000000Z`.

`repro/mi_matrix/stdlib_x509_verify_xmod/certs/`:

- `security_root.der` — RSA-2048 self-signed CA (SHA-256).
- `security_int_wrong.der`, `security_int_correct.der` — two ECDSA P-256 CA
  intermediates with the same raw subject `CN=security_int`; both are issued by
  `security_root`.
- `backtrack_leaf.der` — ECDSA P-256 leaf, issuer `CN=security_int`, signed only
  by `security_int_correct`; SAN `backtrack.example.test`.
- `rsa1024_leaf_rsa2048root.der` — RSA-1024 leaf key signed by the RSA-2048
  `security_root`; SAN `rsa1024-leaf.example.test`.

`repro/mi_matrix/stdlib_x509_verify_xmod/vectors/store_security.bin` — one-anchor
§5.5 store holding `security_root`.

`repro/mi_matrix/stdlib_x509_parse_xmod/certs/malformed_sigalg_mismatch.der` —
`leaf_p256.der` with only the TBS inner signature OID changed from
ecdsa-with-SHA256 to ecdsa-with-SHA384 (same 8-byte OID length); outer remains
ecdsa-with-SHA256.

Embedded fixture arrays were appended to both `certs_data.zig` files and
`vectors_data.zig`; no runtime file reads were added.

New assertions in `stdlib_x509_verify_xmod/main.zig`:

- `expectOkStore(backtrack_leaf, [security_int_wrong, security_int_correct],
  security store, "backtrack.example.test", 2025-01-01)` — first same-subject
  intermediate fails, later one succeeds.
- `expectErr(backtrack_leaf, [security_int_wrong], ..., BadSignature)` — only the
  wrong same-subject intermediate.
- `expectErr(rsa1024_leaf_rsa2048root, [], security store, ...,
  UnsupportedAlgorithm)` — RSA-1024 leaf key under a valid RSA-2048 root.

New assertion in `stdlib_x509_parse_xmod/main.zig`:

- `expectCorrupt(malformed_sigalg_mismatch, "sigalg mismatch cert")`.

## 3. Targeted x509 gate — 3x

Refresh of the seed sibling lib only under `/tmp` (seed itself unchanged):

```
$ cp sf/src/std_x509.zig /tmp/m2_t4_v114_build/lib/std_x509.zig
```

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

## 4. Full stdlib gate + crosscheck

Full `verify_stdlib.sh` (its own crosscheck phase included) over the pinned
fixture set:

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m2_t4_v114_build/zig1_5_clean
...
PASS repro/mi_matrix/stdlib_x509_parse_xmod
PASS repro/mi_matrix/stdlib_x509_verify_xmod
PASS repro/mi_matrix/stdlib_truststore_xmod
...
----------------------------------------
run_fixtures: 327 PASS / 0 FAIL over 327 dirs
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

Explicit crosscheck once more:

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
```

## 5. Commit

Code/fixtures: `9c849209959aafcc43af34eff5a38a6b73687f96`
(`fix(std_x509): path backtracking + leaf key size + sigalg equality`).

Report: this file, separate `docs(sdd): M3 x509 security report` commit.

## Concerns

- Backtracking is limited to signature-verification failures. Once a path
  reaches an anchor and verifies, validity / hostname failures do not trigger an
  alternate same-subject path (unchanged from the previous greedy behavior).
- The new positive/negative cases use a dedicated self-signed `security_root`
  and one-anchor store vector rather than extending the existing six-anchor
  hand-built store, so existing store bytes/pins are untouched.
- No TLS/demo/seed/compiler-battery changes were made.
