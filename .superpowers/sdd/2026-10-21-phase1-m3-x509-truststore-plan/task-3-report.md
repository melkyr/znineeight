# M3 Task 3 report — caconv + store asset + docs + closeout

Status: DONE

Branch: `zig1_improvements` (base `74e92e08`)

Plan authority: `docs/superpowers/plans/2026-10-21-phase1-m3-x509-truststore-plan.md`
Task 3; brief `task-3-brief.md`; context `task-3-context.md`.

## Step 1 — caconv implementation + byte-exact fixture

Created `examples/z98/demo/tls_demo/caconv/main.zig` (Z98 program):

- scans `-----BEGIN CERTIFICATE-----` / `-----END CERTIFICATE-----` blocks in
  file order, strips ASCII whitespace from the body, calls `std_base64.decode`,
  then `std_x509.x509Parse`;
- writes the pinned little-endian §5.5 store (`"Z98CA100"`, u32 count, u32
  total_len, per-anchor u16 subject/spki lengths + u32 validity + DER);
- rejects (nonzero, no store written) malformed PEM/base64/DER, more than 512
  anchors, u16-overflowing subject/SPKI, and validity outside u32;
- prints `wrote N anchors`.

Build (`-fsafe`, seed compiler; sibling `lib/` carries `std_base64`,
`std_asn1`, `std_x509`, `std_file`):

```
$ mkdir -p /tmp/caconv_build
$ /tmp/m2_t4_v114_build/zig1_5_clean -fsafe -o /tmp/caconv_build \
    examples/z98/demo/tls_demo/caconv/main.zig
dump_rc=0
$ sh /tmp/caconv_build/build_target.sh linux /tmp/caconv_build/caconv
build_rc=0
Built: /tmp/caconv_build/caconv
```

Fixture: `testdata/mini.pem` is the Task 2 ECDSA P-256 leaf/intermediate/root
chain converted to PEM (3 certificates, 1703 bytes) with host `openssl`;
`testdata/mini_store.bin` is the committed byte-exact golden. Three runs are
identical and the golden loads through `trustStoreLoad`:

```
$ /tmp/caconv_build/caconv testdata/mini.pem testdata/mini_store.bin
wrote 3 anchors
$ /tmp/caconv_build/caconv testdata/mini.pem /tmp/mini_store_run2.bin
wrote 3 anchors
$ /tmp/caconv_build/caconv testdata/mini.pem /tmp/mini_store_run3.bin
wrote 3 anchors
$ md5sum testdata/mini_store.bin /tmp/mini_store_run2.bin /tmp/mini_store_run3.bin
7a2a1d88d5bddbf00989f0a00a9af1c6  testdata/mini_store.bin
7a2a1d88d5bddbf00989f0a00a9af1c6  /tmp/mini_store_run2.bin
7a2a1d88d5bddbf00989f0a00a9af1c6  /tmp/mini_store_run3.bin
$ cmp testdata/mini_store.bin /tmp/mini_store_run2.bin && cmp testdata/mini_store.bin /tmp/mini_store_run3.bin
identical
$ /tmp/verify_store_out/v testdata/mini_store.bin
anchors=3
```

`test.sh` automates the same checks (build, 2 runs, golden compare,
`trustStoreLoad` count) and passes:

```
$ ./examples/z98/demo/tls_demo/caconv/test.sh /tmp/m2_t4_v114_build/zig1_5_clean
trustStoreLoad: 3 anchors
caconv test: PASS (deterministic, golden match, trustStoreLoad 3 anchors)
```

## Step 2 — first `ca_store.bin` asset

Downloaded the current Mozilla bundle and converted it with the tool above:

```
$ curl -fsSL https://curl.se/ca/cacert.pem -o /tmp/cacert.pem
$ ls -l /tmp/cacert.pem
-rw-r--r-- 1 node node 200116 Oct 22 19:45 /tmp/cacert.pem
$ sha256sum /tmp/cacert.pem
796f1389bfea13c0ed78f663b765baaff54a508e5483786bd6ece73c5e3e3cbe  /tmp/cacert.pem
$ grep -c "BEGIN CERTIFICATE" /tmp/cacert.pem
118
$ head -5 /tmp/cacert.pem
##
## Bundle of CA Root Certificates
##
## Certificate data from Mozilla as of: Tue Oct 20 13:32:40 2026 GMT
##
$ /tmp/caconv_build/caconv /tmp/cacert.pem examples/z98/demo/tls_demo/ca_store.bin
wrote 118 anchors
$ md5sum examples/z98/demo/tls_demo/ca_store.bin
604e08892c57e9c18b0742a7b3cc7304  examples/z98/demo/tls_demo/ca_store.bin
$ sha256sum examples/z98/demo/tls_demo/ca_store.bin
4a83ee354bef176781ed6e76ff95015d6f1ce96830df975b3d74d9df8b97a3a9  examples/z98/demo/tls_demo/ca_store.bin
$ /tmp/verify_store_out/v examples/z98/demo/tls_demo/ca_store.bin
anchors=118
```

Snapshot recorded in `examples/z98/demo/tls_demo/caconv/README.md`: downloaded
`2026-10-22`, Mozilla data as of `Tue Oct 20 13:32:40 2026 GMT`, source
`https://curl.se/ca/cacert.pem`, `cacert.pem` SHA-256 above, 118 anchors,
55,710-byte store.

## Step 3 — docs + truth-ups

Created:

- `sf/docs/std_lib/asn1.md` — `Asn1Reader`/`Tlv`/`TagClass`,
  `asn1Init`/`asn1Remaining`/`asn1ReadTlv`, DER definite-length/minimal-encoding
  rules, no-copy lifetime, and the `error.Corrupt` table.
- `sf/docs/std_lib/x509.md` — `Cert`, `x509Parse`, `SigAlg`/`PkAlg`,
  `TrustAnchor`/`TrustStore`/`trustStoreLoad`, `x509VerifyChain`, the pinned
  §5.5 store layout, the full validation policy, and the exact error table.

Truth-ups:

- `STD_README.MD` — seed v115 / 44 files / archive + manifest md5; L5 row adds
  `std_asn1`/`std_x509`; which-module rows for DER and X.509; domain-doc index
  links; section dates to M3.
- `README.md` — v115 / 44-file seed; higher-layer list adds `std_asn1` and
  `std_x509`; standard-library M3 text; section date to M3.
- `docs/sf/QUICK_REF.md` — current-seed block v115 (archive md5
  `484ae9797545591e113f002e595a26d2`, manifest md5
  `576cffb600863a648f518748edad81c6`, 44 files); inventory 43 `std_*.zig` +
  `std.zig` = 44; install recipe adds both modules; M3 bullets for
  `std_asn1`/`std_x509`; gate count 324/0 and discovery pin 324 (314 + 10).
- `scripts/seed/archive_seed.sh` / `scripts/seed/build_from_seed.sh` — copy
  lists add `std_asn1.zig` + `std_x509.zig`; counts 42 → 44; the archive
  CHANGELOG entry now uses the computed `$LIB_COUNT` instead of a hardcoded 42.

Copy-list check against the actual `sf/src` set:

```
$ a=$(grep "for f in std.zig std_io.zig" scripts/seed/archive_seed.sh); \
  printf '%s\n' "$a" | grep -o 'std[0-9a-z_]*\.zig' | sort | uniq > /tmp/list_archive.txt
$ b=$(grep 'cp "\$ROOT"/sf/src/std.zig' scripts/seed/build_from_seed.sh); \
  printf '%s\n' "$b" | grep -o 'std[0-9a-z_]*\.zig' | sort | uniq > /tmp/list_build.txt
$ ls sf/src/std*.zig | xargs -n1 basename | sort > /tmp/list_actual.txt
$ echo "actual=$(wc -l < /tmp/list_actual.txt) archive=$(wc -l < /tmp/list_archive.txt) build=$(wc -l < /tmp/list_build.txt)"
actual=44 archive=44 build=44
$ diff /tmp/list_actual.txt /tmp/list_archive.txt && echo archive_matches
archive_matches
$ diff /tmp/list_actual.txt /tmp/list_build.txt && echo build_matches
build_matches
$ grep -E 'std_(asn1|x509)\.zig' /tmp/list_archive.txt /tmp/list_build.txt
/tmp/list_archive.txt:std_asn1.zig
/tmp/list_archive.txt:std_x509.zig
/tmp/list_build.txt:std_asn1.zig
/tmp/list_build.txt:std_x509.zig
```

## Step 4 — seed v115 + full gate

Rotated from the unchanged compiler fixed point (M3 adds std payload only;
`sf/src` compiler sources untouched):

```
$ bash scripts/seed/archive_seed.sh \
    /tmp/m2_t4_v114_build/zig1_5_clean /tmp/m2_t4_v114_build/hop2 \
    release/seed/zig1-seed.tgz --update-changelog
[archive] gcc-only rebuild of archive C md5 (fixed point): 45158dcede81125a39a2c2c58478e21e
[archive] wrote release/seed/zig1-seed.tgz (archive md5 484ae9797545591e113f002e595a26d2)
--- CHANGELOG entry ---
## 2026-10-22 — seed v115 (HEAD 741658d2)
| seed binary md5 | `45158dcede81125a39a2c2c58478e21e` |
| self-emission C | 47 `.c` + 48 `.h` (10691275 bytes) |
| fixed point | `45158dcede81125a39a2c2c58478e21e` |
| lib manifest | `lib/manifest.md5` (44 std files; md5 `576cffb600863a648f518748edad81c6`) |
| archive md5 | `484ae9797545591e113f002e595a26d2` |
```

Archive checks:

```
$ md5sum release/seed/zig1-seed.tgz
484ae9797545591e113f002e595a26d2  release/seed/zig1-seed.tgz
$ tar tzf release/seed/zig1-seed.tgz | grep -E '^zig1-seed/lib/std_(asn1|x509)\.zig$'
zig1-seed/lib/std_x509.zig
zig1-seed/lib/std_asn1.zig
$ tar xOf release/seed/zig1-seed.tgz zig1-seed/lib/manifest.md5 | wc -l
44
$ tar xOf release/seed/zig1-seed.tgz zig1-seed/lib/manifest.md5 | md5sum
576cffb600863a648f518748edad81c6  -
$ tar xOf release/seed/zig1-seed.tgz zig1-seed/zig1 | md5sum
45158dcede81125a39a2c2c58478e21e  -
$ tar xOf release/seed/zig1-seed.tgz zig1-seed/lib/manifest.md5 | grep -E 'std_(asn1|x509)\.zig'
b8cfced3c874b79d3ecd5ff12c3bf84d  std_asn1.zig
30f547b1420cf7946036c50522e04e45  std_x509.zig
```

Fresh rebuild of the committed archive (two-hop closure) and gcc-only
reconstruction:

```
$ FIXED_POINT_MD5=45158dcede81125a39a2c2c58478e21e \
    bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m3_t3_seed
[seed] hop1 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] hop2 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] two-hop closure OK: hop1 == hop2 == 45158dcede81125a39a2c2c58478e21e
[seed] recorded fixed point OK: 45158dcede81125a39a2c2c58478e21e
=== [seed] Done: /tmp/m3_t3_seed ===
$ md5sum /tmp/m3_t3_seed/zig1_5_clean
45158dcede81125a39a2c2c58478e21e  /tmp/m3_t3_seed/zig1_5_clean
$ ls /tmp/m3_t3_seed/lib/std*.zig | wc -l
44

$ bash scripts/seed/build_from_seed.sh --reconstruct-only \
    release/seed/zig1-seed.tgz /tmp/m3_t3_recon
[seed] reconstructed binary md5: 45158dcede81125a39a2c2c58478e21e
=== [seed] Done: /tmp/m3_t3_recon ===
$ md5sum /tmp/m3_t3_recon/zig1_5_clean
45158dcede81125a39a2c2c58478e21e  /tmp/m3_t3_recon/zig1_5_clean
```

Full std gate on the rotated compiler:

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m3_t3_seed/zig1_5_clean
...
run_fixtures: 324 PASS / 0 FAIL over 324 dirs
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

caconv fixture on the rotated compiler:

```
$ ./examples/z98/demo/tls_demo/caconv/test.sh /tmp/m3_t3_seed/zig1_5_clean
trustStoreLoad: 3 anchors
caconv test: PASS (deterministic, golden match, trustStoreLoad 3 anchors)
```

## Step 5 — commits

| # | subject | sha |
|---|---|---|
| 1 | `feat(demo): caconv CA-store converter (Phase1 M3)` | `741658d26cc16b32ec4898ce75cacee094e58f4f` |
| 2 | `docs(std_lib): asn1/x509 docs (M3)` | `5315ef64adbde042fa1e126f8c3236af32258080` |
| 3 | `chore(seed): rotate (M3)` | `b02eaa7bb7877bc7d307f5d502f92154bc973317` |
| 4 | `docs(sdd): M3 closeout report` | this report commit |

No `sf/src` compiler or std source changes were made in Task 3. No existing
fixture, pin, or harness was changed. `run.err` remains untracked;
`progress.md` untouched.

## Concerns

1. The v115 archive was assembled at feat-commit HEAD `741658d2` (before the
   docs commit), so `release/seed/CHANGELOG.md` records `741658d2`; this is the
   true assembly HEAD. No compiler source changed in M3.
2. `caconv` has a committed self-test (`test.sh` + mini-PEM golden) but is not
   wired into `scripts/stdlib/expected_dirs.txt` / `verify_stdlib.sh`; the task
   specified no new std fixture directory. The full gate is unaffected.
3. `ca_store.bin` reflects the 2026-10-22 download (Mozilla data
   `2026-10-20`): **118** anchors, 55,710 bytes — fewer than the ~150 anchors
   the spec uses as a resident-cost example.
4. `x509VerifyChain`'s `arena` parameter remains unused (`_ = arena;`) in the
   Task 2 implementation; this task did not change it. The x509 doc states
   that explicitly.

