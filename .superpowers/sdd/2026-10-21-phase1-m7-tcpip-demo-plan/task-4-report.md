# M7 Task 4 report — Phase 1 closeout

Status: COMPLETE — v119 rotated; full gate and both tiers green on the rotated compiler.

## Environment

- Repo: `/workspace/znineeight`
- Base: `69070dc4` (M7 T3 complete)
- Seed v118 compiler: `/tmp/m6_t3_v118_rotated/zig1_5_clean`
  (md5 `45158dcede81125a39a2c2c58478e21e`)
- Portable WireGuard tools: `IP=/tmp/m7_tools/ip/bin/ip`,
  `WG=/tmp/m7_tools/wg12/usr/bin/wg`,
  `LD_LIBRARY_PATH=/tmp/m7_tools/libs/usr/lib/x86_64-linux-gnu`

## Step 1 — seed scripts + rotation candidate

Seed scripts updated for the 47-file std set (`std_tcpip.zig` added to both
copy lists; archive `SEED_README.txt` counts updated).

Candidate archive generated with the unchanged v118 compiler and its
self-emission C:

```
$ bash scripts/seed/archive_seed.sh /tmp/m6_t3_v118_rotated/zig1_5_clean \
    /tmp/m6_t3_v118_rotated/gen /tmp/m7_t4_v119_candidate.tgz
[archive] gcc-only rebuild of archive C md5 (fixed point): 45158dcede81125a39a2c2c58478e21e
[archive] wrote /tmp/m7_t4_v119_candidate.tgz (archive md5 e7ac8cd2ed7e790a4b9225a82acaf4a5)
| seed binary md5 | `45158dcede81125a39a2c2c58478e21e` |
| fixed point | `45158dcede81125a39a2c2c58478e21e` |
| lib manifest | `lib/manifest.md5` (47 std files; md5 `e731a3d2a7aef913f5bbcfd8670e5a2e`) |
| archive md5 | `e7ac8cd2ed7e790a4b9225a82acaf4a5` |
```

Archive inventory check: 47 `lib/*.zig`, includes `std_tcpip.zig`, fixed point
unchanged.

## Step 2 — rotated compiler build + full gate

Built from the candidate v119 archive:

```
$ FIXED_POINT_MD5=45158dcede81125a39a2c2c58478e21e \
    bash scripts/seed/build_from_seed.sh /tmp/m7_t4_v119_candidate.tgz \
    /tmp/m7_t4_v119_build
[seed] hop2 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] two-hop closure OK: hop1 == hop2 == 45158dcede81125a39a2c2c58478e21e
[seed] recorded fixed point OK: 45158dcede81125a39a2c2c58478e21e
=== [seed] Done: /tmp/m7_t4_v119_build ===
rc=0
md5 45158dcede81125a39a2c2c58478e21e  /tmp/m7_t4_v119_build/zig1_5_clean
lib/ = 47 files (includes std_tcpip.zig)
```

Full std gate on the rotated compiler:

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m7_t4_v119_build/zig1_5_clean
...
run_fixtures: 336 PASS / 0 FAIL over 336 dirs
...
run_crosscheck: 10 PASS / 0 FAIL over 10 modules
STDLIB GATE OK
rc=0
```

`tier_tls.sh` on the rotated compiler, with the internet smoke enabled:

```
$ ZIG=/tmp/m7_t4_v119_build/zig1_5_clean Z98_NET=1 \
    bash examples/z98/demo/tls_demo/tests/tier_tls.sh
ok   - internet www.google.com/ status=200 bytes=90770
ok   - internet example.com/ status=200 bytes=577
ok   - internet RSA-PSS TLS 1.3 aws.amazon.com ... bytes=509551
ok   - internet ECDSA TLS 1.3 letsencrypt.org ... bytes=90353
ok   - RAM ceiling ok: /usr/bin/time peak RSS=2504 kB (ulimit -v 32768)
== tier_tls summary: 19 passed, 0 failed, 0 skipped ==
TIER_TLS PASS
rc=0
```

`tier_wireguard.sh` on the rotated compiler (portable netns tools):

```
$ ZIG=/tmp/m7_t4_v119_build/zig1_5_clean \
    bash examples/z98/demo/wireguard_demo/tests/tier_wireguard.sh
wireguard_demo ok bytes=100 arena_peak=275192 rss_peak=2556 cpu_ms=70
wine -osw run: ... rss_peak=6804 cpu_ms=450
RAM ceiling ok: peak RSS=2388 kB (ulimit -v 32768)
== tier_wireguard summary: 5 passed, 0 failed, 0 skipped ==
TIER_WIREGUARD PASS
rc=0
```

Measured demo resources used in the README tables:

```
tls_demo Linux 1.2:  arena_peak=321 rss_peak=2880 cpu_ms=330
tls_demo Linux 1.3a: arena_peak=321 rss_peak=3064 cpu_ms=260
tls_demo Linux 1.3c: arena_peak=321 rss_peak=2908 cpu_ms=230
tls_demo Wine 1.2:   arena_peak=321 rss_peak=6908 cpu_ms=90
wireguard Linux DNS: bytes=100 arena_peak=275192 rss_peak=2556 cpu_ms=70
wireguard Wine:      bytes=100 arena_peak=275192 rss_peak=6804 cpu_ms=450
```

## Step 3 — docs/truth-ups/ledger

Created `sf/docs/std_lib/tcpip.md` (API, TCP policy table, DNS/ICMP completion
semantics, fixed memory bounds). Updated both demo READMEs with measured
Linux/Wine tables and cross-links. Truthed up `STD_README.MD`, `README.md`, and
`docs/sf/QUICK_REF.md` to 47 files / v119 / archive md5
`e7ac8cd2ed7e790a4b9225a82acaf4a5` / manifest
`e731a3d2a7aef913f5bbcfd8670e5a2e`, the 336/0 gate, and the Phase 1 summary.
Appended defect-ledger D7 (Phase 1 sweep: fixed PSS `-fsafe` mask, fixed X.509
path/key/sigalg, open demo-worked-around emitter lvalue shape).

## Step 4 — committed-archive re-verification

Rebuilt from the committed `release/seed/zig1-seed.tgz` after the rotation
commit:

```
$ FIXED_POINT_MD5=45158dcede81125a39a2c2c58478e21e \
    bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz \
    /tmp/m7_t4_v119_final
[seed] hop1 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] hop2 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] two-hop closure OK: hop1 == hop2 == 45158dcede81125a39a2c2c58478e21e
[seed] recorded fixed point OK: 45158dcede81125a39a2c2c58478e21e
=== [seed] Done: /tmp/m7_t4_v119_final ===
archive md5 e7ac8cd2ed7e790a4b9225a82acaf4a5
lib/ = 47 files
compiler md5 45158dcede81125a39a2c2c58478e21e
```

Full gate and both tiers on that compiler:

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m7_t4_v119_final/zig1_5_clean
run_fixtures: 336 PASS / 0 FAIL over 336 dirs
run_crosscheck: 10 PASS / 0 FAIL over 10 modules
STDLIB GATE OK
rc=0

$ ZIG=/tmp/m7_t4_v119_final/zig1_5_clean Z98_NET=1 \
    bash examples/z98/demo/tls_demo/tests/tier_tls.sh
== tier_tls summary: 19 passed, 0 failed, 0 skipped ==
TIER_TLS PASS
rc=0

$ ZIG=/tmp/m7_t4_v119_final/zig1_5_clean \
    bash examples/z98/demo/wireguard_demo/tests/tier_wireguard.sh   # run 1
== tier_wireguard summary: 5 passed, 0 failed, 0 skipped ==
TIER_WIREGUARD PASS
rc=0
$ ... same command ...                                            # run 2
== tier_wireguard summary: 5 passed, 0 failed, 0 skipped ==
TIER_WIREGUARD PASS
rc=0
```

Final-run resource samples (run-to-run variation is expected; the README
tables record one representative closeout run):
`wireguard_demo ok bytes=100 arena_peak=275192 rss_peak=2552 cpu_ms=70`
(Linux) and `rss_peak=6784 cpu_ms=450` (Wine); RAM run peak 2320 KiB, second
run 2424 KiB.

## Status

COMPLETE. Seed v119 = 47 std files, archive md5
`e7ac8cd2ed7e790a4b9225a82acaf4a5`, manifest md5
`e731a3d2a7aef913f5bbcfd8670e5a2e`, fixed point unchanged
`45158dcede81125a39a2c2c58478e21e` (std-only rotation; `sf/src`/compiler
untouched). Full stdlib + crosscheck gate green; both tiers green on the
rotated compiler; no silent skips.

## Concerns

- D7.3 remains an **open compiler emitter defect**: an indexed aggregate-field
  nested write (`arr[i].field[0..] = ...`) can materialise a by-value
  temporary. `wireguard_demo` works around it with an explicit pointer; no
  compiler change was in scope here.
- `tier_wireguard.sh` and the demo need a distinct client tunnel IP and an
  increasing `clock_override_unix` when reusing one kernel peer (TAI64N replay
  protection). The tier already isolates runs.
- DNS is A/IN only; CNAME chains are `DnsFailed` by contract.
- The seed CHANGELOG entry records the pre-closeout HEAD `69070dc4` because the
  archive was assembled before the docs commit; the archive itself is committed
  in `chore(seed): rotate (M7)`.
- `run.err` remained untracked and untouched.

## Commits

- `b41e12cb` `docs(std_lib): tcpip docs + Phase 1 closeout`
- `2d4eef3c` `chore(seed): rotate (M7)`
- this report: `docs(sdd): M7 closeout report`

## Fix round — docs accuracy (base `0d355391`)

Docs-only corrections; no seed/source/contract change, so no gate rerun was
required (the compiler, std sources, fixtures, and seed archive are
byte-identical to the verified v119 closeout).

- `sf/docs/std_lib/tcpip.md` memory table: `recv_seq` corrected to
  `[TCP_RECV_WINDOW]u32` = **32 KiB**; `TcpSock` total remains 65,648 B
  (16 KiB send + 8 KiB receive ring + 32 KiB sequence + 8 KiB validity +
  fields).
- `README.md` Phase 1 summary: Linux runs real HTTPS; the `-osw` builds are
  emission/import-gated, not executed. Only `tier_wireguard` runs Wine.
- `tcpip.md` truth-ups: removed `OutputTooSmall` from `dnsResolve` and
  `OutOfMemory` from `tcpipPoll` (the poll does not allocate); `.done` also
  covers the idle stack; odd checksum byte is `data[i] << 8` (high byte, zero
  low pad); RTO sets `ssthresh = cwnd/2` (floor `2*mss`); the advertised
  window is 8 KiB minus outstanding unread bytes (`recvWindow`); `icmpPing`
  RTT is measured from the last retry send.
- Defect ledger D7: added a Phase 1 STOP cross-reference (M2 const-rodata
  STOP-1 `.bss` fallback + STOP-2 seed-rotation resolution; M4 `tls_demo`
  Winsock-lifetime and clock-overflow fixes `e9c039df`), with no renumbering.

Docs commit: `c6036786` `docs(std_lib): Phase 1 closeout doc accuracy`.
Report commit: `docs(sdd): M7 T4 fix round`.

## Fix round 2 — STOP cross-reference correction (base `641f6948`)

Docs-only; no source/seed change and no gate rerun (inputs byte-identical to
the verified v119 closeout).

- Corrected D7 STOP-2: it was resolved by **v112** (1C-F, fixed point
  `21c95773…` → `45158dce…`) and then **v113** (Task 4), not “v113→v114”.
- Removed the false claim that a tier/Wine run pins `tls_demo`'s Winsock
  lifetime. `tier_tls.sh` only builds/import-gates `-osw`; no tier executes
  `tls_demo` under Wine, and the Winsock lifetime has no automated regression
  coverage. The manual Wine recipe in `examples/z98/demo/tls_demo/README.md` is
  the only current check.
- Reframed the M4 Winsock/clock items as **Medium/Low review fixes**, not
  STOPs.
- Root `README.md`: scoped “not executed” to **not executed by `tier_tls`**;
  `tier_wireguard` executes its demo under Wine and `tls_demo/README.md`
  documents a manual Wine run.

Docs commit: `docs(std_lib): correct Phase 1 STOP cross-reference`.
Report commit: `docs(sdd): M7 T4 fix round 2`.

## Post-closeout final-review commits

The closeout logs above report `5 passed, 0 failed, 0 skipped` because the
earlier summary counted only the **5 in-netns integration cases**. The four
config checks and four build/import checks already existed and ran at closeout.
Commit `afc87e59` added config-failure propagation and carried the outer
counts into the summary, producing `13 passed, 0 failed, 0 skipped`
(4 config + 5 in-netns integration + 4 build/import). The truth-up is recorded
in `docs/sf/QUICK_REF.md`, `examples/torrent_example_defects.md`, and
`wireguard_demo/NOTES.md`.

- `afc87e59` `test(tier): propagate config failures + DNS source negative (Phase1 M7)`
  — config regressions abort before `unshare`; outer counts carried into the
  inner summary; DNS fixture rejects wrong source IP/port.
- `7748696f` `docs(std_lib): M7 final-review truth-ups` — README tier/resource/
  prefix truth-ups, D7.3 cross-reference correction, spec §5.8 idle `.done`.
- `7fc85e6b` `docs(sdd): M7 final-review fix` — task-3 final-review report.
- `6787ed35` `docs(std_lib): M7 tier count truth-up` — this count correction.
- This report: `docs(sdd): M7 T4 fix round 3` (this commit).

Docs-only; product `sf/src`, seed, compiler, fixtures, and gate behavior are
unchanged by the count truth-up (`6787ed35`).

## Fix round 4 — historical tier count context (base `3703f280`)

Docs-only; no source, seed, fixture, or gate change.

- Removed the false claim that the config/build checks were added after
  closeout. The four config checks and four build/import checks already
  existed and ran at closeout;
  the older `5 passed, 0 failed, 0 skipped` summary counted only the
  **5 in-netns integration cases**. Commit `afc87e59` added config-failure
  propagation and carried the outer counts into the summary, yielding
  `13/13` (4 config + 5 in-netns + 4 build/import).
- Corrected `examples/torrent_example_defects.md` and
  `examples/z98/demo/wireguard_demo/NOTES.md` to that meaning; added context
  to the task-3 report status line; corrected this report's post-closeout
  paragraph.

Docs commit: `b19d1ef6` `docs(std_lib): correct M7 historical tier count context`.
Report commit: `docs(sdd): M7 T4 fix round 4`.
