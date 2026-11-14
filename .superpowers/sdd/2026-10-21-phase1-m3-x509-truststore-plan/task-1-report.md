# M3 Task 1 report — `std_asn1` + `std_x509` parse

Status: DONE

Branch: `zig1_improvements` (base `c2a17452`)

## Step 1 — committed certificate corpus + malformed vectors

Generated the corpus once with host OpenSSL 3.0.22 (`openssl ca -selfsign`
with fixed `-startdate`/`-enddate`, then `openssl x509 -outform DER`):

```
$ bash /tmp/gen_m3_certs.sh
total 56
-rw-r--r-- 1 node node  352 Oct 22 19:20 ca_basic.der
-rw-r--r-- 1 node node  372 Oct 22 19:20 expired.der
-rw-r--r-- 1 node node  388 Oct 22 19:20 generalized.der
-rw-r--r-- 1 node node  392 Oct 22 19:20 leaf_p256.der
-rw-r--r-- 1 node node  453 Oct 22 19:20 leaf_p384.der
-rw-r--r-- 1 node node  792 Oct 22 19:20 leaf_rsa_sha256.der
-rw-r--r-- 1 node node  792 Oct 22 19:20 leaf_rsa_sha384.der
-rw-r--r-- 1 node node  792 Oct 22 19:20 leaf_rsa_sha512.der
-rw-r--r-- 1 node node  392 Oct 22 19:20 malformed_bad_oid.der
-rw-r--r-- 1 node node  392 Oct 22 19:20 malformed_indefinite.der
-rw-r--r-- 1 node node  392 Oct 22 19:20 malformed_nested.der
-rw-r--r-- 1 node node  100 Oct 22 19:20 malformed_truncated.der
-rw-r--r-- 1 node node 1273 Oct 22 19:20 overcap.der
-rw-r--r-- 1 node node  453 Oct 22 19:20 san_wildcard.der
```

Corpus coverage (verified with `openssl x509 -text`):

```
ca_basic.der         ECDSA P-256  ecdsa-with-SHA256     CA:TRUE  2020-01-01..2035-01-01
expired.der          ECDSA P-256  ecdsa-with-SHA256               2020-01-01..2020-12-31
generalized.der      ECDSA P-256  ecdsa-with-SHA256               2050-01-01..2060-01-01 (GeneralizedTime)
leaf_p256.der        ECDSA P-256  ecdsa-with-SHA256               CA:FALSE + SAN
leaf_p384.der        ECDSA P-384  ecdsa-with-SHA384               CA:FALSE + SAN
leaf_rsa_sha256.der  RSA-2048     sha256WithRSAEncryption         SAN
leaf_rsa_sha384.der  RSA-2048     sha384WithRSAEncryption         SAN
leaf_rsa_sha512.der  RSA-2048     sha512WithRSAEncryption         SAN
san_wildcard.der     ECDSA P-256  ecdsa-with-SHA256               3 DNS + email + URI
overcap.der          ECDSA P-256  ecdsa-with-SHA256               33 DNS SANs (> 32 cap)
```

Generic malformed DER under `repro/mi_matrix/stdlib_asn1_xmod/vectors/`
(truncated TLV, indefinite length, nested length overflow, malformed OID
continuation) and malformed certificate variants under `certs/` are committed.
`certs_data.zig` / `vectors_data.zig` embed every byte; fixtures do not read
files at runtime.

Expected unix timestamps used by the fixture:

```
2024-01-01T00:00:00Z -> 1704067200    2030-01-01T00:00:00Z -> 1893456000
2020-01-01T00:00:00Z -> 1577836800    2035-01-01T00:00:00Z -> 2051222400
2020-12-31T23:59:59Z -> 1609459199    2050-01-01T00:00:00Z -> 2524608000
2060-01-01T00:00:00Z -> 2840140800
```

## Step 2 — fixture run before implementation (expected FAIL)

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean repro/mi_matrix/stdlib_asn1_xmod repro/mi_matrix/stdlib_x509_parse_xmod
FAIL repro/mi_matrix/stdlib_asn1_xmod (DUMP-RC2)
    dump stderr:                                       ^^^^
FAIL repro/mi_matrix/stdlib_x509_parse_xmod (DUMP-RC2)
    dump stderr:                                                         ^^^^
----------------------------------------
run_fixtures: 0 PASS / 2 FAIL over 2 dirs
failed: repro/mi_matrix/stdlib_asn1_xmod repro/mi_matrix/stdlib_x509_parse_xmod
exit=1
```

## Step 3 — implementation

Created `sf/src/std_asn1.zig`:

- `Asn1Reader { data, pos }` + `asn1Init` + `asn1ReadTlv`.
- Definite lengths only; indefinite `0x80`, non-minimal long-form lengths,
  truncated headers/bodies and non-minimal high-tag encodings => `error.Corrupt`.
- Returned `Tlv { cls, constructed, tag, data, full }` slices into the input.
- Universal OID contents are validated (non-empty, minimal base-128, final
  octet has the continuation bit clear), so malformed OIDs are `Corrupt` at the
  reader boundary.
- `asn1Remaining` helper for bounded sub-readers.

Created `sf/src/std_x509.zig`:

- `Cert` with `subject`, `issuer`, `spki`, `sig`, `sig_alg`, `pk_alg`,
  `not_before`, `not_after`, `is_ca`, `san_dns`, plus the documented fixed
  `san_storage: [SAN_MAX][]const u8` (`SAN_MAX = 32`) and `san_count`.
- `x509Parse(der, out)` parses Certificate -> tbsCertificate / sig alg /
  signature BIT STRING, then TBSCertificate fields, extensions, SPKI.
- OID table: ecdsa-with-SHA256/384, sha256/384/512WithRSAEncryption,
  RSA-PSS (reserved), id-ecPublicKey + prime256v1/secp384r1, rsaEncryption.
- `basicConstraints` cA flag, SAN dNSName-only extraction in DER order;
  > 32 DNS SANs => `error.Corrupt`.
- UTCTime (1950..2049) and GeneralizedTime -> i64 Unix seconds via a
  civil-date conversion; strict digit/date/range validation.
- Signature/public-key BIT STRINGs must be octet-aligned (unused bits == 0).

The compiler resolves std modules from its sibling `lib/`. For targeted runs
only (seed rotation is Task 3), refreshed that test copy:

```
$ cp sf/src/std_asn1.zig sf/src/std_x509.zig /tmp/m2_t4_v114_build/lib/
$ ls -l /tmp/m2_t4_v114_build/lib/std_asn1.zig /tmp/m2_t4_v114_build/lib/std_x509.zig
-rw-r--r-- 1 node node  4068 Oct 22 19:22 /tmp/m2_t4_v114_build/lib/std_asn1.zig
-rw-r--r-- 1 node node 13845 Oct 22 19:22 /tmp/m2_t4_v114_build/lib/std_x509.zig
```

First run exposed a bad-vector bug (the OID vector `2A 86 48` was actually a
valid OID); replaced it with a trailing-continuation vector `2A 86 C8`:

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean repro/mi_matrix/stdlib_asn1_xmod repro/mi_matrix/stdlib_x509_parse_xmod
scripts/stdlib/run_fixtures.sh: line 167: 730118 Trace/breakpoint trap   ( cd "$run_cwd" && timeout 120 "$tmp/prog" ) > "$tmp/.run1.out" 2> "$tmp/.run1.err"
FAIL repro/mi_matrix/stdlib_asn1_xmod (STDOUT-MISMATCH)
PASS repro/mi_matrix/stdlib_x509_parse_xmod
run_fixtures: 1 PASS / 1 FAIL over 2 dirs
exit=1
```

## Step 4 — targeted fixtures PASS + 3x determinism

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean repro/mi_matrix/stdlib_asn1_xmod repro/mi_matrix/stdlib_x509_parse_xmod
PASS repro/mi_matrix/stdlib_asn1_xmod
PASS repro/mi_matrix/stdlib_x509_parse_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
exit=0

$ for i in 1 2 3; do echo "=== run $i ==="; bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean repro/mi_matrix/stdlib_asn1_xmod repro/mi_matrix/stdlib_x509_parse_xmod; echo "exit=$?"; done
=== run 1 ===
PASS repro/mi_matrix/stdlib_asn1_xmod
PASS repro/mi_matrix/stdlib_x509_parse_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
exit=0
=== run 2 ===
PASS repro/mi_matrix/stdlib_asn1_xmod
PASS repro/mi_matrix/stdlib_x509_parse_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
exit=0
=== run 3 ===
PASS repro/mi_matrix/stdlib_asn1_xmod
PASS repro/mi_matrix/stdlib_x509_parse_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
exit=0
```

The harness itself runs each program 3x per invocation and compares stdout
byte-for-byte; the outer loop is the required 3x determinism check over the
targeted set. Malformed-input checks are inside the fixtures and assert
`error.Corrupt` (no trap); the only observed traps were the transient fixture
bug above.

Default-mode (`-fsafe`) smoke check: both fixtures were emitted without
`-ffast`, compiled with the binding gcc flag set, and run from a scratch CWD:
`SAFE PASS repro/mi_matrix/stdlib_asn1_xmod`, `SAFE PASS
repro/mi_matrix/stdlib_x509_parse_xmod` (rc 0, stdout identical to the golden).

Full std harness/crosscheck and seed rotation are deferred to Task 3 closeout
per the task brief (targeted-only for Task 1).

## Step 5 — commit

```
$ git commit -m "feat(std_asn1,std_x509): DER + certificate parse (Phase1 M3)"
[zig1_improvements 4858de78] feat(std_asn1,std_x509): DER + certificate parse (Phase1 M3)
 29 files changed, 1480 insertions(+)
```

Code/fixture commit: `4858de788b1d068f749442687295b59326b4d5f9`.
