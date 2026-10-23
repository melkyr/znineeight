# M6 Task 3 report — docs + seed v118 closeout

Status: complete (Task 3 only).

## 1. Environment / base

- Repo root `/workspace/znineeight`; branch `zig1_improvements`; task base
  `651f83a0` (`docs(sdd): M6 T2 complete ledger`).
- Current seed at start: v117, 45 lib files, archive
  `111e0474c702a582516f60c2e570a3c0`, manifest
  `ef02702556fe1ae8c21e68d8f2bff141`, binary/fixed point
  `45158dcede81125a39a2c2c58478e21e`.
- `run.err` remains untracked/untouched. `progress.md` untouched.
- No `sf/src`, tier, compiler, or unrelated source changes.

## 2. Baseline build (current `sf/src` with the v117 seed)

Command:

```text
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m6_t3_v118_build
```

Observed key lines (gcc warnings omitted):

```text
[seed] hop1 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] hop2 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] two-hop closure OK: hop1 == hop2 == 45158dcede81125a39a2c2c58478e21e
=== [seed] Done: /tmp/m6_t3_v118_build ===
$ md5sum /tmp/m6_t3_v118_build/zig1_5_clean
45158dcede81125a39a2c2c58478e21e  /tmp/m6_t3_v118_build/zig1_5_clean
```

`/tmp/m6_t3_v118_build/gen` is the v117 compiler's self-emission of the current
`sf/src` (47 module `.c` + 48 module `.h` + emitted support); it was used as the
archive's `gen_dir` input.

## 3. Docs

Created `sf/docs/std_lib/wireguard.md` with:

- API spec §5.7 (constants, `WgPeer`/`WgDevice`, `WgError`, `WgAction`,
  `wgInit`, `wgAddPeer`, `wgCreateInitiation`, `wgProcessResponse`,
  `wgTai64n`, `wgSend`, `wgTick`, `wgReceive`, LE helpers);
- ASCII initiation/response/cookie/transport message-flow diagram;
- timer table (120 s rekey, 180 s reject, 5 s + bounded jitter retry,
  10 s keepalive, message caps);
- replay-window semantics (2048 bits, authenticate before window update);
- cookie consumption / `mac2` semantics;
- explicit `wall_unix_ns` vs `now_ms` warning;
- rekey continuity (active session preserved; pending installed on response).

Truth-ups applied:

- `STD_README.MD`: seed v117 → v118, 45 → 46 files, new archive/manifest
  md5s, L5 row + module inventory, which-module row, domain-doc index row,
  section dates → M6.
- `README.md`: Current Status v118; Determinism block v118/46 files; higher-layer
  list `std_wireguard`; standard-library prose.
- `docs/sf/QUICK_REF.md`: v117 → v118, 45 → 46, inventory 44 → 45
  `std_*.zig`, install list, `std_wireguard` module bullet, gate count
  `330/0` → `333/0`, installer count 45 → 46.
- `scripts/seed/archive_seed.sh`, `scripts/seed/build_from_seed.sh`: 45 → 46
  and `std_wireguard.zig` in the lib install/SEED_README lists.

Doc quick-check:

```text
$ for p in sf/docs/std_lib/wireguard.md docs/sf/QUICK_REF.md release/seed/zig1-seed.tgz; do
    test -e "$p" && echo "OK $p" || echo "MISSING $p"; done
OK sf/docs/std_lib/wireguard.md
OK docs/sf/QUICK_REF.md
OK release/seed/zig1-seed.tgz
$ grep -nE "^#|^##" sf/docs/std_lib/wireguard.md
1:# WireGuard — `std_wireguard`
12:## Module overview
69:## Message flow
97:## Quick start
157:## `wall_unix_ns` vs `now_ms`
177:## Timers
207:## Replay window
226:## Cookies and `mac2`
245:## API (spec §5.7)
630:## Determinism
639:## Pins
$ git diff --check && echo DIFF_CHECK_OK
DIFF_CHECK_OK
```

No stale `v117`/`45` count remains in the truth-up targets (the only `v117`
occurrences are the intentional `v117 → v118` history sentence in QUICK_REF).

## 4. Seed rotation (v118)

Command:

```text
$ bash scripts/seed/archive_seed.sh /tmp/m6_t3_v118_build/zig1_5_clean \
    /tmp/m6_t3_v118_build/gen release/seed/zig1-seed.tgz --update-changelog
```

Observed key lines (gcc warnings omitted):

```text
[archive] gcc-only rebuild of archive C md5 (fixed point): 45158dcede81125a39a2c2c58478e21e
[archive] wrote release/seed/zig1-seed.tgz (archive md5 9716ea682cf7eb9147b5e642ce48fc93)
--- CHANGELOG entry ---
## 2026-10-23 — seed v118 (HEAD 651f83a0)
| HEAD | `651f83a0` |
| seed binary md5 | `45158dcede81125a39a2c2c58478e21e` |
| self-emission C | 47 `.c` + 48 `.h` (10691275 bytes) |
| fixed point | `45158dcede81125a39a2c2c58478e21e` |
| lib manifest | `lib/manifest.md5` (46 std files; md5 `15c7bc2daeba84f892ef376df7cf4a7d`) |
| archive md5 | `9716ea682cf7eb9147b5e642ce48fc93` |
[archive] prepended entry to /workspace/znineeight/release/seed/CHANGELOG.md
```

Archive contents verification:

```text
$ tar tzf release/seed/zig1-seed.tgz | grep 'lib/std' | wc -l
46
$ tar tzf release/seed/zig1-seed.tgz | grep 'lib/std_wireguard.zig'
zig1-seed/lib/std_wireguard.zig
$ tar xzf release/seed/zig1-seed.tgz -O zig1-seed/lib/manifest.md5 | grep -c 'std'
46
$ tar xzf release/seed/zig1-seed.tgz -O zig1-seed/lib/manifest.md5 | md5sum
15c7bc2daeba84f892ef376df7cf4a7d  -
```

## 5. Fixed-point rebuild from the rotated archive

Command:

```text
$ FIXED_POINT_MD5=45158dcede81125a39a2c2c58478e21e \
    bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m6_t3_v118_rotated
```

Observed key lines (gcc warnings omitted):

```text
[seed] hop1 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] hop2 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] two-hop closure OK: hop1 == hop2 == 45158dcede81125a39a2c2c58478e21e
[seed] recorded fixed point OK: 45158dcede81125a39a2c2c58478e21e
=== [seed] Done: /tmp/m6_t3_v118_rotated ===
$ md5sum /tmp/m6_t3_v118_rotated/zig1_5_clean
45158dcede81125a39a2c2c58478e21e  /tmp/m6_t3_v118_rotated/zig1_5_clean
$ ls /tmp/m6_t3_v118_rotated/lib/*.zig | wc -l
46
$ ls /tmp/m6_t3_v118_rotated/lib/std_wireguard.zig
/tmp/m6_t3_v118_rotated/lib/std_wireguard.zig
```

## 6. Full stdlib gate on the rotated compiler

Command:

```text
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m6_t3_v118_rotated/zig1_5_clean
```

Observed tail:

```text
PASS repro/mi_matrix/stdlib_wg_handshake_xmod
PASS repro/mi_matrix/stdlib_wg_transport_xmod
PASS repro/mi_matrix/stdlib_wireguard_cross_xmod
...
----------------------------------------
run_fixtures: 333 PASS / 0 FAIL over 333 dirs
== std-lib crosscheck gate ==
PASS smoke (3 vectors)
PASS std_hpa (8 vectors)
PASS std_lz4 (20 vectors)
PASS std_noise (1 vectors)
PASS std_num (1 vectors)
PASS std_pathfind (2 vectors)
PASS std_physics (1 vectors)
PASS std_rand (2 vectors)
PASS std_wireguard (3 vectors)
PASS std_zstd (30 vectors)
----------------------------------------
run_crosscheck: 10 PASS / 0 FAIL over 10 modules
STDLIB GATE OK
```

Standalone full crosscheck (per task contract; also run inside the gate above):

```text
$ bash scripts/stdlib/run_crosscheck.sh /tmp/m6_t3_v118_rotated/zig1_5_clean
PASS smoke (3 vectors)
PASS std_hpa (8 vectors)
PASS std_lz4 (20 vectors)
PASS std_noise (1 vectors)
PASS std_num (1 vectors)
PASS std_pathfind (2 vectors)
PASS std_physics (1 vectors)
PASS std_rand (2 vectors)
PASS std_wireguard (3 vectors)
PASS std_zstd (30 vectors)
----------------------------------------
run_crosscheck: 10 PASS / 0 FAIL over 10 modules
```

No compiler battery was run (no compiler source change). No `-osw`/tier run was
required by Task 3 (T2 already gated `-osw`; this task is docs + seed only).

## 7. Commits

```text
e4211d84 docs(std_lib): wireguard docs (M6)
ab180208 chore(seed): rotate (M6)
<this commit> docs(sdd): M6 closeout report
```

## 8. Files changed (Task 3)

- `sf/docs/std_lib/wireguard.md` (new)
- `STD_README.MD`, `README.md`, `docs/sf/QUICK_REF.md`
- `scripts/seed/archive_seed.sh`, `scripts/seed/build_from_seed.sh`
- `release/seed/zig1-seed.tgz`, `release/seed/CHANGELOG.md`
- `.superpowers/sdd/2026-10-21-phase1-m6-wireguard-plan/task-3-report.md`

No `sf/src` changes. `progress.md` and `run.err` untouched.

## 9. Concerns

- Cookies: consumption/`mac2` is implemented and fixture-pinned, but cookie
  expiry is not enforced because initiation construction has no `now_ms`
  parameter. This is documented in `wireguard.md` and carried from T2.
- `WG_REKEY_AFTER_MESSAGES` (`1 << 60`) is published but not consumed by the
  current `wgSend` guard; only `WG_REJECT_AFTER_MESSAGES` stops sending. The
  doc states this explicitly rather than implying a message-count rekey.
- Initiator-only: received type-1 initiations are `error.Corrupt`;
  cookie-reply generation is out of scope.
- The seed archive's recorded HEAD is `651f83a0` (the pre-closeout HEAD at
  rotation time); the rotation commit follow-up contains the archive itself.

## 10. Fix round — docs accuracy (base `6463f8f2`)

Docs-only corrections in `sf/docs/std_lib/wireguard.md`; no source, seed, or
tier changes. The full gate was **not rerun** (docs-only). Minimal evidence:

```text
$ grep -n "@intCast(u64, std.time.ticksMs())\|wallClockUnix()) \* 1000000000\|2^64 - 8193\|preshared_key.*optional\|does not check .iface_pub\|jittered retry interval\|TAI64N timestamp is big-endian" sf/docs/std_lib/wireguard.md
48:helpers, with one exception: the TAI64N timestamp is big-endian (8-byte
125:const now_ms: u64 = @intCast(u64, std.time.ticksMs());
126:const wall_unix_ns: u64 = @intCast(u64, std.time.wallClockUnix()) * 1000000000;
189:| `WG_REKEY_AFTER_TIME_MS` | 120 000 ms | Once the session is 120 s old, `wgTick` starts a rekey initiation (`.send_handshake`) when the pending handshake is due — immediately if none is in flight, otherwise after the jittered retry interval. ...
193:| `WG_REJECT_AFTER_MESSAGES` | `2^64 - 8193` | `wgSend` returns `error.SessionExpired` once `sending_counter` reaches this value. |
437:  `preshared_key` is optional and all-zero when no PSK is configured;
445:  or a failed X25519 operation. (`wgAddPeer` does not check `iface_pub`; the
$ grep -n "milliTimestamp\|2^64 - 8192\|when no handshake is in flight\|preshared_key.*are required" sf/docs/std_lib/wireguard.md
none
$ grep -n "pub fn ticksMs\|pub fn wallClockUnix" sf/src/std_time.zig
56:pub fn ticksMs() u32 {
116:pub fn wallClockUnix() i64 {
$ grep -n "WG_REJECT_AFTER_MESSAGES" sf/src/std_wireguard.zig | head -2
49:pub const WG_REJECT_AFTER_MESSAGES: u64 = 0xFFFFFFFFFFFFFFFF - (1 << 13);
814:        if (p.sending_counter >= WG_REJECT_AFTER_MESSAGES) return error.SessionExpired;
$ git diff --check && echo DIFF_CHECK_OK
DIFF_CHECK_OK
```

Fixes applied:

1. Quick start now uses `@intCast(u64, std.time.ticksMs())` and
   `@intCast(u64, std.time.wallClockUnix()) * 1000000000`.
2. Reject-after-messages is `2^64 - 8193` (matches
   `0xFFFFFFFFFFFFFFFF - (1 << 13)`).
3. `preshared_key` is documented as optional/all-zero, not required.
4. `wgAddPeer` `error.InvalidPeer` no longer claims an `iface_pub` check; the
   uninitialised-device-key check is attributed to `wgCreateInitiation`.
5. Rekey wording now states that a new initiation can be sent while one is
   pending, on the jittered retry interval; “when no handshake is in flight”
   was removed.
6. The endianness statement is scoped: all multi-byte wire integers are
   little-endian except the big-endian TAI64N timestamp.

Fix-round commit: `docs(std_lib): fix wireguard doc accuracy (M6)`; report
commit: `docs(sdd): M6 T3 fix round`.
