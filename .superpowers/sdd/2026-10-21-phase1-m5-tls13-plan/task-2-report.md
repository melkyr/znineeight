# M5 Task 2 report — interop tier + closeout

Status: complete (Task 2 only; no `sf/src` changes).

Commits: `a16dd0d6` docs, `48a3b8b5` seed rotation, final `docs(sdd)` report.

## 1. Environment

- Repo root `/workspace/znineeight`; branch `zig1_improvements`; base
  `6215fb75`.
- Compiler `/tmp/m2_t4_v114_build/zig1_5_clean`
  (`md5sum` = `45158dcede81125a39a2c2c58478e21e`).
- All 45 sibling `lib/*.zig` files in that build already match the current
  `sf/src` sources.
- Host `openssl` 3.0.22, mingw, Wine available.

## 2. Tier changes

`examples/z98/demo/tls_demo/tests/tier_tls.sh` now covers:

- local TLS 1.2 fallback (`openssl s_server -tls1_2`) with the client offering
  both 1.3 and 1.2;
- local TLS 1.3 happy paths for `TLS_AES_128_GCM_SHA256` and
  `TLS_CHACHA20_POLY1305_SHA256` (`openssl s_server -tls1_3 -ciphersuites …`);
- a second run of each 1.3 suite and byte comparison of status/body/bytes;
- `Z98_NET=1` smoke: google.com, example.com, and
  `www.microsoft.com/en-us/` (RSA-2048 cert, RSA-PSS CertificateVerify);
- unchanged expired/wrong-host/untrusted negatives, clock-overflow guard,
  RAM ceiling, `-osw` build and Win9x import gate.

`examples/z98/demo/tls_demo/main.zig` now configures
`min_version = TLS_VERSION_12`, `max_version = TLS_VERSION_13` so the same
demo exercises TLS 1.3 and still falls back to TLS 1.2. This is an example
change (not `sf/src`); it is required for the 1.3 interop tier.

## 3. Tier verification

Command (loud-SKIP path):

```text
$ OUT=/tmp/tier_tls_m5a bash examples/z98/demo/tls_demo/tests/tier_tls.sh
```

Observed:

```text
ok   - local TLS 1.2 fallback fetch: status=200, exact body, bytes=14
ok   - expired leaf -> cert: CertificateExpired
ok   - wrong host -> cert: HostnameMismatch
ok   - untrusted anchor -> cert: UnknownIssuer
ok   - clock override overflow -> tls: BadArgs
ok   - happy status/body/bytes identical 2x
ok   - local TLS 1.3 AES-128-GCM fetch: status=200, exact body, bytes=14
ok   - local TLS 1.3 ChaCha20-Poly1305 fetch: status=200, exact body, bytes=14
ok   - TLS 1.3 AES-128-GCM status/body/bytes identical 2x
ok   - TLS 1.3 ChaCha20-Poly1305 status/body/bytes identical 2x
SKIP - Z98_NET unset: internet smoke SKIPPED (set Z98_NET=1 to run google.com + example.com + microsoft.com)
ok   - RAM ceiling ok: /usr/bin/time peak RSS=2780 kB (ulimit -v 32768)
ok   - -osw emit + mingw build produced tls_demo.exe
ok   - file: PE32 i386
ok   - check_win9x_imports.sh 9x whitelist PASS
== tier_tls summary: 15 passed, 0 failed, 1 skipped ==
TIER_TLS PASS
```

Command (network, run 1):

```text
$ OUT=/tmp/tier_tls_m5b Z98_NET=1 bash examples/z98/demo/tls_demo/tests/tier_tls.sh
```

Observed:

```text
ok   - internet www.google.com/ status=200 bytes=91735
ok   - internet example.com/ status=200 bytes=577
ok   - internet www.microsoft.com/en-us/ status=200 bytes=201253
== tier_tls summary: 18 passed, 0 failed, 0 skipped ==
TIER_TLS PASS
```

Command (network, run 2):

```text
$ OUT=/tmp/tier_tls_m5c Z98_NET=1 bash examples/z98/demo/tls_demo/tests/tier_tls.sh
```

Observed:

```text
ok   - internet www.google.com/ status=200 bytes=90747
ok   - internet example.com/ status=200 bytes=577
ok   - internet www.microsoft.com/en-us/ status=200 bytes=201253
== tier_tls summary: 18 passed, 0 failed, 0 skipped ==
TIER_TLS PASS
```

Both network runs kept the local 1.2 fallback and both 1.3 suites green; the
local status/body/bytes comparisons were byte-identical within each run. The
`-osw` import gate reported only `KERNEL32.DLL` and `WSOCK32.DLL`.

## 4. Docs commit

Commit `a16dd0d6` — `docs(std_lib): tls 1.3 docs (M5)`.

- `sf/docs/std_lib/tls.md`: TLS 1.2/1.3 title/overview, dedicated TLS 1.3
  section (suites, x25519/no-HRR, ECDSA/P-384/RSA-PSS CertificateVerify,
  PKCS#1 v1.5 rejection, KeyUpdate → `error.Closed`), `TLS_VERSION_13`,
  six-entry suite table, `suiteIsTls13`, 1.3 record APIs, session size
  124400, error/state/config updates.
- `examples/z98/demo/tls_demo/README.md`: TLS 1.3 notes, dual-version demo,
  tier coverage, RSA-PSS host, updated suite/group troubleshooting.
- `STD_README.MD`, `README.md`, `docs/sf/QUICK_REF.md`: TLS 1.2/1.3 prose and
  updated `std_tls` inventory.

## 5. Seed rotation (v117)

Command:

```text
$ bash scripts/seed/archive_seed.sh /tmp/m2_t4_v114_build/zig1_5_clean \
    /tmp/m2_t4_v114_build/gen release/seed/zig1-seed.tgz --update-changelog
```

Observed key lines (gcc warnings omitted):

```text
[archive] gcc-only rebuild of archive C md5 (fixed point): 45158dcede81125a39a2c2c58478e21e
[archive] wrote release/seed/zig1-seed.tgz (archive md5 111e0474c702a582516f60c2e570a3c0)
--- CHANGELOG entry ---
## 2026-10-22 — seed v117 (HEAD a16dd0d6)
| HEAD | `a16dd0d6` |
| seed binary md5 | `45158dcede81125a39a2c2c58478e21e` |
| self-emission C | 47 `.c` + 48 `.h` (10691275 bytes) |
| fixed point | `45158dcede81125a39a2c2c58478e21e` |
| lib manifest | `lib/manifest.md5` (45 std files; md5 `ef02702556fe1ae8c21e68d8f2bff141`) |
| archive md5 | `111e0474c702a582516f60c2e570a3c0` |
[archive] prepended entry to /workspace/znineeight/release/seed/CHANGELOG.md
```

The manifest md5 changed from v116's `0c022fe0…` to `ef027025…` because v116
predates the Task 1 `std_tls.zig` TLS 1.3 update; v117 now carries that
payload. There is no new module (still 45 std files) and the compiler fixed
point is unchanged.

### Fixed-point rebuild from the rotated archive

Command:

```text
$ FIXED_POINT_MD5=45158dcede81125a39a2c2c58478e21e \
    bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m5_t2_v117
```

Observed key lines (gcc warnings omitted):

```text
[seed] hop1 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] hop2 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] two-hop closure OK: hop1 == hop2 == 45158dcede81125a39a2c2c58478e21e
[seed] recorded fixed point OK: 45158dcede81125a39a2c2c58478e21e
=== [seed] Done: /tmp/m5_t2_v117 ===
```

## 6. Full gate on the rotated compiler

Command:

```text
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m5_t2_v117/zig1_5_clean
```

Observed tail:

```text
----------------------------------------
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

Tier on the rotated compiler (network enabled):

```text
$ OUT=/tmp/tier_tls_m5_v117 ZIG=/tmp/m5_t2_v117/zig1_5_clean Z98_NET=1 \
    bash examples/z98/demo/tls_demo/tests/tier_tls.sh
...
ok   - internet www.google.com/ status=200 bytes=91536
ok   - internet example.com/ status=200 bytes=577
ok   - internet www.microsoft.com/en-us/ status=200 bytes=201253
== tier_tls summary: 18 passed, 0 failed, 0 skipped ==
TIER_TLS PASS
```

## 7. Files changed (Task 2)

- `examples/z98/demo/tls_demo/tests/tier_tls.sh`
- `examples/z98/demo/tls_demo/main.zig` (example-only version range)
- `examples/z98/demo/tls_demo/README.md`
- `sf/docs/std_lib/tls.md`
- `STD_README.MD`, `README.md`, `docs/sf/QUICK_REF.md`
- `release/seed/zig1-seed.tgz`, `release/seed/CHANGELOG.md`
- `.superpowers/sdd/2026-10-21-phase1-m5-tls13-plan/task-2-report.md`

No `sf/src` changes. `progress.md` and `run.err` were not touched.

## 8. Concerns

- The local 1.3 interop cases both use the committed RSA leaf, so they exercise
  RSA-PSS CertificateVerify for both suites. ECDSA P-256/P-384
  CertificateVerify remains covered by the Task 1 canned-transcript fixtures,
  not by a local `openssl s_server` ECDSA cert (no ECDSA test cert is
  committed).
- The original `www.microsoft.com/en-us/` RSA-PSS smoke was a 200 soft-block
  page; Task 2-I replaced it (see §9) and added a challenge-marker check.
- Google response bytes vary between runs; the smoke asserts status=200 and
  bytes>0, while local status/body/bytes determinism is pinned byte-for-byte.
- The v117 manifest md5 differs from v116 because v116 predated the Task 1
  `std_tls.zig` payload; the compiler fixed point is unchanged.

## 9. Endpoint fix (Task 2-I)

Investigation report:
`.superpowers/sdd/2026-10-21-phase1-m5-tls13-plan/task-2i-network-report.md`.

Changes in `examples/z98/demo/tls_demo/tests/tier_tls.sh`:

- Removed the `www.microsoft.com/en-us/` RSA-PSS smoke (200 soft-block page).
- RSA-PSS TLS 1.3: `aws.amazon.com` primary, `www.mozilla.org` fallback.
- ECDSA TLS 1.3: `letsencrypt.org` primary, `example.com` fallback.
- Internet cases now fail when the response body/title contains
  `Your request has been blocked`, `Just a moment`, or `captcha`, in addition
  to the existing status=200 / bytes>0 checks.
- Local TLS 1.3 both-suite cases and the local TLS 1.2 fallback are unchanged.
- `examples/z98/demo/tls_demo/README.md` updated; local ECDSA test leaves were
  deliberately deferred (no source/seed changes in this fix).

Network tier run 1:

```text
$ OUT=/tmp/tier_tls_fix1 Z98_NET=1 bash examples/z98/demo/tls_demo/tests/tier_tls.sh
ok   - internet www.google.com/ status=200 bytes=91532
ok   - internet example.com/ status=200 bytes=577
ok   - internet RSA-PSS TLS 1.3 aws.amazon.com status=200 bytes=509641
ok   - internet ECDSA TLS 1.3 letsencrypt.org status=200 bytes=90353
ok   - check_win9x_imports.sh 9x whitelist PASS
== tier_tls summary: 19 passed, 0 failed, 0 skipped ==
TIER_TLS PASS
```

Network tier run 2:

```text
$ OUT=/tmp/tier_tls_fix2 Z98_NET=1 bash examples/z98/demo/tls_demo/tests/tier_tls.sh
ok   - internet www.google.com/ status=200 bytes=91500
ok   - internet example.com/ status=200 bytes=577
ok   - internet RSA-PSS TLS 1.3 aws.amazon.com status=200 bytes=509641
ok   - internet ECDSA TLS 1.3 letsencrypt.org status=200 bytes=90353
ok   - check_win9x_imports.sh 9x whitelist PASS
== tier_tls summary: 19 passed, 0 failed, 0 skipped ==
TIER_TLS PASS
```

