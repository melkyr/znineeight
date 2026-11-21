# Task 4 report — M4 closeout (docs + seed v116)

Branch: `zig1_improvements` (base `17bbcfa1`). Task 4 only; no compiler source
changes, no compiler battery.

## Step 1 — docs

### Created `sf/docs/std_lib/tls.md`

- Follows `_template.md` structure: module overview, quick start, API, See also.
- Documents API §5.6: `TlsAction`, `TlsConfig`, `TlsSession`, `tlsInit`,
  `tlsStep`, `tlsRead`, `tlsWrite`; the explicit `SendClientHello … Established`
  state machine; SNI; P-256 + x25519; SHA-256 transcript; PRF_SHA256 12-byte
  Finished.
- Suite table: four `ECDHE-{ECDSA,RSA}-{AES128-GCM,ChaCha20-Poly1305}-SHA256`
  suites with wire IDs, server-auth signature, AEAD/key/fixed-IV sizes, and the
  RFC 5288 explicit-nonce vs RFC 7905 sequence-XOR constructions.
- Error table: the actual `TlsError` set from `sf/src/std_tls.zig`, including
  the `std_x509` certificate errors and the pre/post-`Established` AEAD-error
  mapping.
- Time/clock policy: `TlsConfig.now_unix` is the only time source; `std_tls`
  never reads a clock; the demo uses `std_time.wallClockUnix()` with
  `clock_override_unix` and a 2000–2100 plausibility window (`cert: time`).
- Buffer/record limits table: 16384 plaintext, 16408 wire, 5-byte header,
  16413 reader buffer, 65536 handshake reassembly, 8192 pending flight, 32768
  application buffer, 12-byte Finished.

Verified:

```text
$ wc -l sf/docs/std_lib/tls.md
674 sf/docs/std_lib/tls.md
$ grep -c '^### ' sf/docs/std_lib/tls.md
38
```

`TlsSession` size was measured with a throwaway program compiled by the rotated
seed compiler; it printed `124008` bytes (about 121 KiB). Both `tls.md` and the
demo README were updated from the earlier “about 110 KiB” estimate.

### Truth-ups

- `STD_README.MD`: seed v115 → **v116**; **44 → 45** std files (`std.zig` + 44
  `std_*.zig`); manifest md5 → `0c022fe049c808828704b702e6a2b2e7`; archive md5
  → `ca0c46dcd671d50fd4f22497f5bc525a`; L5 layer row adds `std_tls`; job table
  adds “TLS 1.2 client (sans-I/O records + handshake)”; domain-doc index adds
  `tls.md`; section tag M3 → M4.
- `README.md`: Current Status and Determinism blocks seed v115 → **v116** with
  the new archive/manifest md5s and 45 std files; M3 payload note → M4 TLS 1.2 /
  HTTPS; Standard Library block adds `std_tls` and the sans-I/O TLS 1.2
  description; section tag M3 → M4.
- `docs/sf/QUICK_REF.md`: seed block v115 → **v116** (archive md5
  `ca0c46dcd671d50fd4f22497f5bc525a`, manifest md5
  `0c022fe049c808828704b702e6a2b2e7`, 45 std files); std inventory **43 →
  44** `std_*.zig` and **44 → 45** total; all 45 installed by
  `build_from_seed.sh`; canonical cp command adds `std_tls.zig`; adds
  `std_tls` + M4 `std_http` transport notes; gate count 324/0 → **327/0** on
  seed v116 with the three M4 fixtures accounted for.
- `examples/z98/demo/tls_demo/README.md`: cross-checked against the M4 source
  and tier; corrected `TlsSession` size to 124008 bytes.

Docs checks:

```text
$ git diff --check
(no output; exit 0)
```

All links referenced from `tls.md` resolve (`cipher.md`, `crypto.md`, `ecc.md`,
`x509.md`, `examples/z98/demo/tls_demo/README.md`, `STD_README.MD`).

## Step 2 — seed scripts + v116 rotation

### Seed scripts

- `scripts/seed/archive_seed.sh`: added `std_tls.zig` to the header inventory,
  the copy list, and the `SEED_README.txt` lib inventory; 44 → 45 in the
  `lib/` prose, manifest prose, and std-install prose.
- `scripts/seed/build_from_seed.sh`: added `std_tls.zig` to the lib copy
  command; 44 → 45 in the header recipe comment.

### Rotation

Seed binary was taken from the committed v115 archive (md5
`45158dcede81125a39a2c2c58478e21e`), dumped from the repo root with the
relative path:

```text
$ timeout 120 /tmp/m4_t4_seed/v115/zig1-seed/zig1 -ffast --dump-c89 \
    --output-dir /tmp/m4_t4_seed/gen sf/src/main.zig
rc=0
```

The dumped module C/H matched the v115 archive `gen/` byte-for-byte (only an
extra `build_target.sh` helper was present in the dump dir).

```text
$ bash scripts/seed/archive_seed.sh /tmp/m4_t4_seed/v115/zig1-seed/zig1 \
    /tmp/m4_t4_seed/gen release/seed/zig1-seed.tgz --update-changelog
[archive] gcc-only rebuild of archive C md5 (fixed point): 45158dcede81125a39a2c2c58478e21e
[archive] wrote release/seed/zig1-seed.tgz (archive md5 ca0c46dcd671d50fd4f22497f5bc525a)
[archive] prepended entry to /workspace/znineeight/release/seed/CHANGELOG.md
```

New CHANGELOG entry:

```text
## 2026-10-22 — seed v116 (HEAD 17bbcfa1)
| seed binary md5 | `45158dcede81125a39a2c2c58478e21e` |
| fixed point | `45158dcede81125a39a2c2c58478e21e` |
| lib manifest | `lib/manifest.md5` (45 std files; md5 `0c022fe049c808828704b702e6a2b2e7`) |
| archive md5 | `ca0c46dcd671d50fd4f22497f5bc525a` |
```

Archive checks:

```text
$ tar -tzf release/seed/zig1-seed.tgz | grep -E 'lib/std.*zig$' | wc -l
45
$ tar -tzf release/seed/zig1-seed.tgz | grep -E 'lib/std_tls.zig$'
zig1-seed/lib/std_tls.zig
$ md5sum release/seed/zig1-seed.tgz
ca0c46dcd671d50fd4f22497f5bc525a  release/seed/zig1-seed.tgz
$ tar -xOf release/seed/zig1-seed.tgz zig1-seed/lib/manifest.md5 | wc -l
45
$ tar -xOf release/seed/zig1-seed.tgz zig1-seed/lib/manifest.md5 | grep std_tls
eea2f32f6ecd8ceab6e25e63353a2a60  std_tls.zig
```

### Rebuild / fixed point (std-only; compiler source unchanged)

```text
$ FIXED_POINT_MD5=45158dcede81125a39a2c2c58478e21e \
    bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz \
    /tmp/m4_t4_seed/v116_build
[seed] hop1 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] hop2 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] two-hop closure OK: hop1 == hop2 == 45158dcede81125a39a2c2c58478e21e
[seed] recorded fixed point OK: 45158dcede81125a39a2c2c58478e21e
=== [seed] Done: /tmp/m4_t4_seed/v116_build ===
$ ls /tmp/m4_t4_seed/v116_build/lib/*.zig | wc -l
45
```

## Step 3 — full gate on the rotated compiler

```text
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m4_t4_seed/v116_build/zig1_5_clean
...
run_fixtures: 327 PASS / 0 FAIL over 327 dirs
== std-lib crosscheck gate ==
run_crosscheck: 9 PASS / 0 FAIL over 9 modules
STDLIB GATE OK
rc=0
```

```text
$ bash scripts/stdlib/run_crosscheck.sh /tmp/m4_t4_seed/v116_build/zig1_5_clean
PASS smoke (3 vectors)
PASS std_hpa (8 vectors)
PASS std_lz4 (20 vectors)
PASS std_noise (1 vectors)
PASS std_num (1 vectors)
PASS std_pathfind (2 vectors)
PASS std_physics (1 vectors)
PASS std_rand (2 vectors)
PASS std_zstd (30 vectors)
run_crosscheck: 9 PASS / 0 FAIL over 9 modules
rc=0
```

(`verify_stdlib.sh` already runs `run_crosscheck.sh`; the separate invocation
is recorded for the explicit Task 4 requirement.)

## Commits

- `f363eddd` — `docs(std_lib): tls docs (M4)`
- `b6682127` — `chore(seed): rotate (M4)`
- report commit follows as `docs(sdd): M4 closeout report`

## Notes

- The archive was generated at base HEAD `17bbcfa1`, matching the established
  rotation pattern (the seed commit follows the docs commit). Its
  `SEED_README.txt`/CHANGELOG pin `HEAD 17bbcfa1`.
- Compiler source was not modified; fixed point stayed
  `45158dcede81125a39a2c2c58478e21e` and hop1 == hop2.
- `progress.md` and `run.err` were not touched.
