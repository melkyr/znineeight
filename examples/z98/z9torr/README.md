# z9torr

z9torr — a BitTorrent client example for the Z98 bootstrap compiler.

This is the **M6 "Win9x default profile"** milestone (M6 makes the default
`-osw` = Windows 9x no-CRT; M5 added Win9x cross-compat, the Wine smoke, and
the manual Win98 procedure; see the M6/M5 sections below). `z9torr <file.torrent>`
parses a single-file torrent, announces to a tracker (UDP `udp://` when present,
else HTTP), and downloads from up to `--max-peers` peers (rarest-first, one
coroutine per announced peer, verifying every piece by SHA-1, with
cross-restart resume). M4 adds **MSE/PE protocol encryption**, a **UDP tracker
(BEP 15)**, **DHT (BEP 5) + PEX (BEP 11)** peer discovery, and fixes the
all-zero `peer_id`.

## Files
- `main.zig`: Entry point. Parses the torrent, announces, spawns peer coroutines.
- `cli.zig`: `Args`/`parseArgs`/`usage`/`exitCodeFor` (spec §8 exit codes).
- `torrent.zig`: single-file bencode parse + SHA-1 `info_hash`.
- `wire.zig`: peer-wire framing + handshake (plaintext and RC4-encrypted).
- `peer.zig`: one peer coroutine; MSE-first transport with plaintext fallback.
- `mse.zig`: MSE/PE encrypted handshake (DH-768 + RC4).
- `tracker.zig` / `udp_tracker.zig`: HTTP tracker + UDP tracker (BEP 15).
- `dht.zig` / `pex.zig`: DHT (BEP 5) and PEX (BEP 11) peer discovery.
- `scheduler.zig` / `piece.zig` / `disk.zig` / `resume.zig` / `ratelimit.zig` /
  `stats.zig`: rarest-first scheduler, pipeline, disk, resume, rates, stats.
- `console.zig`: stdout console/redirect probe for the 1 Hz progress line (M5
  T3b; `GetFileType`/`isatty`, `@isWindows()`).
- `tools/`: C89 `ref_check` plus the mock tracker/peer/MSE/UDP-tracker.
- `tests/`: `tier1.sh`, `tier1_cli.sh`, `tier1_unit.sh`, `tier2.sh`,
  `tier3_encrypted.sh`, `tier_udp_tracker.sh`, `tier_dht.sh`, `tier_pex.sh`,
  `tier_stall.sh` (non-blocking probe), `tier_fallback.sh` (encrypted-first
  plaintext fallback), `tier_refseed.sh`/`tier_refseed_py.sh` (real
  aria2c / Python MSE responders), `tier_mse_diag.sh` (MSE against aria2c +
  Python) (hard gates), `tier_real.sh` (best-effort real swarm),
  `tier4_wine.sh` (M5 `-osw` + mingw build + Wine smoke) and
  `tier_win9x_io.sh` (M5 T3b redirected-vs-console progress gate).
- `testdata/`, `demo/`: committed fixtures, goldens, and golden commands;
  `demo/win9x_README.txt` is the manual Win98 (T5) procedure.
- `NOTES.md`, `README.md`: build recipes, expected output, and status.

## Build and Run

```bash
mkdir -p /tmp/z9_m1_out
timeout 120 /tmp/t54/zig1_5_clean -fsafe -o /tmp/z9_m1_out examples/z98/z9torr/main.zig
sh /tmp/z9_m1_out/build_target.sh linux /tmp/z9_m1_out/prog
/tmp/z9_m1_out/prog examples/z98/z9torr/testdata/t1_single_1m.torrent
```

**Expected output** (for `testdata/t1_single_1m.torrent`):
```
name: t1.bin
length: 1048576
piece length: 262144
pieces: 4
info_hash: 5bb27f309ea4f5a0a1bf338c0cf2462295d694b5
```

With no torrent path (or `--help`) it prints the `usage:` block and exits 1
(0 for `--help`).

## Status
**M6 "Win9x default profile"** (2026-10-18): the default `-osw` now emits the
Windows 9x no-CRT path, so `z9torr.exe` is a single drag-and-drop PE32 that
imports only `KERNEL32.DLL` + `WSOCK32.DLL` (no msvcrt.dll). The committed
import gate is green (`check_win9x_imports.sh ... 9x`) and
`tests/tier_win9x_io.sh` passes `3/0`. Under 32-bit Wine the full loopback
download completes with rc 0 and the golden SHA-1; see the M6 section below for
the exact smoke results (including the tier4 progress-sampling timing caveat).
The real Win98 run remains manual (`demo/win9x_README.txt`) and hardware
verification is operator-pending. M5 Task 0 added 64-bit file offsets in
`sf/src/std_file.zig`; on the 9x profile these route through
`pal_file_seek64`'s Win95 `SetFilePointer` path (the `*Ex` calls are `-osw nt`).
T3b adds the stdout redirect fallback and Win9x `MAX_PATH`/reserved-name
validation (both example-only; `sf/src` untouched). The pre-M5 gates stay green:
`tier1.sh` `21/0`, `tier2.sh` `17/0`, `tier_win9x_io.sh` `3/0`.

**M4 polished** (2026-10-10): **M4.1 "real MSE/PE handshake"** is complete — the
encrypted handshake now completes against real implementations (aria2c 1.36.0
and an independent Python MSE responder), and the encrypted-first **plaintext
fallback** works (its retry loop was capped at 100 attempts, which exhausted in
microseconds after the MSE probe became coroutine-aware; it is now wall-clock
throttled across the full ~3 s window). The M4 polish closes the last
compatibility gap: the peer handshake now **ignores unknown reserved bits per
BEP 3** (the strict `wire.reservedAccepted` predicate is gone), so real peers
that advertise bits we do not implement are no longer rejected. Hash gates (all
PASS, from the repo root): `tier1.sh` `16/0`, `tier1_cli.sh` `8/8`,
`tier1_unit.sh` `3/3`, `tier2.sh` `17/0`, `tier3_encrypted.sh` `5/0`,
`tier_udp_tracker.sh` `7/0`, `tier_dht.sh` `4/0`, `tier_pex.sh` `11/0`,
`tier_stall.sh` `8/0`, `tier_fallback.sh` `8/0`, `tier_refseed_py.sh` `6/0`,
`tier_refseed.sh` `6/0`, `tier_mse_diag.sh` `11/0`. Compiler/seed unchanged
(seed v96, closure `46e3e7af98af3b5ff2a960c7c96025e3`).

`tier_real.sh` is a **best-effort** real-swarm tier (not part of the hard gate
set): it exits `0` only on measured payload progress, `77` with an explicit
classified `SKIP: <reason>` when the client exits a recognized environmental code
(parse/tracker/peer/disk/timeout) because the network denies reachability, and
`1` on a build error, an unexpected internal state, or any other (crash/signal)
client exit.

Best-effort live Debian retest with the fixed client (`lin_bin/`): 50 tracker
peers, 7 TCP connects, 7 `handshake ok` (2 encrypted + 5 plaintext); the exact
qBittorrent `reserved=0000000000180005` handshake now succeeds, and
**~37.75 MiB (4.9 %) was fetched** before the bounded 100 s window.

## Building for Windows 9x (seed v102)

The default `-osw` profile is Win9x (95/98/Me) no-CRT. Rebuild seed v102 from
`release/seed/zig1-seed.tgz` (archive md5
`702f34d87b7e6bf401dd206d2517dbee`; fixed point
`b299b4b435e624d0ddbd2edde681cbc3`) and emit with `-fsafe -osw`. The emitted
mingw recipe links the no-CRT runtime and produces a single PE32 console EXE;
no msvcrt.dll, no CRT redistributable.

Client (`main.zig` → `z9torr.exe`):

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9torr_seed
mkdir -p /tmp/z9torr_win9x_build
/tmp/z9torr_seed/zig1_5_clean -fsafe -osw -o /tmp/z9torr_win9x_build \
    examples/z98/z9torr/main.zig
sh /tmp/z9torr_win9x_build/build_target.sh mingw \
    /tmp/z9torr_win9x_build/z9torr.exe
```

Import check (expected: PE32 i386, exactly KERNEL32 + WSOCK32, no msvcrt):

```bash
bash scripts/win32_cross/check_win9x_imports.sh \
    /tmp/z9torr_win9x_build/z9torr.exe 9x
```

Optional mock binaries for a localhost Win98 test:

```bash
mkdir -p /tmp/z9torr_mock_tracker /tmp/z9torr_mock_peer
/tmp/z9torr_seed/zig1_5_clean -fsafe -osw -o /tmp/z9torr_mock_tracker \
    examples/z98/z9torr/tools/mock_tracker.zig
sh /tmp/z9torr_mock_tracker/build_target.sh mingw \
    /tmp/z9torr_mock_tracker/mock_tracker.exe
/tmp/z9torr_seed/zig1_5_clean -fsafe -osw -o /tmp/z9torr_mock_peer \
    examples/z98/z9torr/tools/mock_peer.zig
sh /tmp/z9torr_mock_peer/build_target.sh mingw \
    /tmp/z9torr_mock_peer/mock_peer.exe
```

Copy the exe + mocks + a `.torrent` and run from an MS-DOS Prompt; the exact
copy/run procedure, mocks and payload details are in `demo/win9x_README.txt`.
`-osw nt` is the explicit CRT/NT opt-in (XP+ file APIs), not the Win9x default.
Native `build_target_nocrt.bat` (MSVC 6) / `build_owc_nocrt.bat` (OpenWatcom)
are emitted no-CRT scripts; `build_target_crt.bat` / `build_owc_crt.bat` are
static-CRT alternates. They are design-verified, hardware pending; real
Win98/Me hardware verification remains **operator-pending** (not claimed).

## M6 — Win9x default profile (2026-10-18)

- **Default profile:** bare `-osw` = Windows 9x, no CRT. The emitted mingw
  script links `-m32 -nostdlib -Wl,-e,_mainCRTStartup` with
  `-lgcc -lkernel32 -lwinmm -lwsock32` (winmm is linked but unused unless a
  WINMM symbol is referenced); the emitted no-CRT runtime provides
  `mainCRTStartup`/argv, stdio/console, env, clock and
  `strlen`/`memcpy`/`memset`/`strncmp`. Result: a single drag-and-drop
  `z9torr.exe`; no msvcrt.dll redistributable. `-osw nt` is the explicit
  opt-in CRT/XP profile.
- **Emitted scripts:** 9x no-CRT default `build_target_nocrt.bat` /
  `build_owc_nocrt.bat`; static-CRT alternates `build_target_crt.bat` /
  `build_owc_crt.bat`; `build_target.bat` / `build_owc.bat` remain
  profile-correct aliases. Native MSVC/OpenWatcom scripts are design-verified;
  hardware verification is pending (operator, after the z9play milestone).
- **Build:** seed v101 (`/tmp/t54/zig1_5_clean`, fixed point
  `b299b4b435e624d0ddbd2edde681cbc3`). `-fsafe` and `-ffast` both emit/link
  the 9x no-CRT image. `-osw --dump-c89` md5
  `54146cf3afc4c25cb5d98efccc68a2f1` (stable 3×).
- **Imports (emitted no-CRT path):** PE32; exactly `KERNEL32.DLL` +
  `WSOCK32.DLL`; no `MSVCRT.DLL` and no XP+ `GetFileSizeEx` /
  `SetFilePointerEx` / `GetFileAttributesExA`. Gate:
  `bash scripts/win32_cross/check_win9x_imports.sh <exe> 9x` → PASS. The legacy
  `cross_build_run.sh` harness links the normal CRT (its exe imports MSVCRT),
  so it is not 9x-profile evidence; `cross_nocrt.sh` is not a drop-in for
  z9torr (no `-lwsock32`).
- **Wine smoke:** the tier4 run exe is built with the emitted 9x no-CRT
  `build_target.sh`, and its functional loopback checks pass (rc 0, fetched
  1048576, golden SHA-1 `7a985d40…`, `PARITY=OK`). Its 1 Hz progress assertion
  is timing-sensitive: the 1 MiB loopback transfer can finish before the first
  sample, and the committed one-shot mock-peer restart occasionally races the
  MSE-first probe (then the run exits 4 before fetching). A throttled loopback
  run (`--max-down 32768`) produced 34 progress lines, no bare CR, rc 0 and
  the same golden SHA-1. `tests/tier_win9x_io.sh` `3/0`.

## M5 — Win9x cross-compat (2026-10-11)

M5 makes the client build and run for Win9x.

- **Build mode:** the client is built and run with **`-fsafe`** (checked
  arithmetic). Since M5 S1/S2 every tier and every mock is `-fsafe`; the UB that
  `-ffast` used to hide is fixed, and the example's build recipes no longer say
  `-ffast`.
- **Windows build:** emit with `-osw`; the emitted `build_target.sh mingw`
  is the 9x no-CRT path. It links `-m32 -nostdlib -Wl,-e,_mainCRTStartup`
  plus `-lgcc -lkernel32 -lwinmm -lwsock32` (winmm is linked but unused unless
  a WINMM symbol is referenced). The legacy `cross_build_run.sh` harness links
  the normal CRT and its exe imports MSVCRT, so it is not 9x-profile evidence.
  The M5-era `-osw` emit md5 was
  `4a330207a420462a9ad4376ace7d0a63`; under the M6 default 9x profile (seed
  v101) it is `54146cf3afc4c25cb5d98efccc68a2f1` (stable 3×):
  ```bash
  timeout 120 /tmp/t54/zig1_5_clean -osw --dump-c89 \
      examples/z98/z9torr/main.zig | md5sum
  ```
  ```bash
  mkdir -p /tmp/t54_z9torr
  timeout 120 /tmp/t54/zig1_5_clean -fsafe -osw -o /tmp/t54_z9torr \
      examples/z98/z9torr/main.zig
  sh /tmp/t54_z9torr/build_target.sh mingw /tmp/t54_z9torr/z9torr.exe
  ```
- **T4 — automated Wine smoke:** `tests/tier4_wine.sh` emits `-osw`, mingw
  cross-builds, and runs `z9torr_run.exe` under 32-bit Wine against the host
  mocks; it asserts exit 0 + the t1 golden SHA-1 (`PARITY=OK`) and that the
  redirected Win32 progress uses one line per refresh (no bare CR). M5 observed
  `19/0`; the M6 no-CRT re-run results are in the M6 section above. It is a
  smoke, not real hardware.
- **T3b — Win9x runtime behaviours:** `console.zig` detects an interactive
  stdout (`GetFileType`/`FILE_TYPE_CHAR` on Windows, `isatty(1)` on POSIX) so
  the progress line uses an in-place `\r` only on a console and one line per
  refresh (`\n`) when redirected (`tests/tier_win9x_io.sh`). `torrent.load`
  rejects an `info.name` over `MAX_PATH`/255 and Win9x reserved device names
  (CON/PRN/AUX/NUL/COM1-9/LPT1-9, case-insensitive, with or without extension)
  as the typed name error (exit 2).
- **T5 — manual Win98 run:** documented in `demo/win9x_README.txt` (copy the
  exe + the mocks + a `.torrent`, run `z9torr.exe file.torrent`, with the
  expected console output, the FAT no-sparse-file note, and MAX_PATH/reserved
  names). The Win98 machine is outside the repo, so T5 is manual only.

Next: M6 T5.5 covers z9play; z9torr's real Win98/Me load/run verification is
operator-owned and pending (plan Amendment 5).
