# z9torr — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `83881722`

**MD5 (`--dump-c89`):** `b4403decb51c775075fb1beb89a35c73` (seed `zig1_5_clean`; stable 3×; M1a amendment)

## Build Recipes

### seed zig1_5_clean (build + run) — binding
```bash
mkdir -p /tmp/z9_m1_out
timeout 120 /tmp/z9_m0_seed/zig1_5_clean -ffast -o /tmp/z9_m1_out examples/z98/z9torr/main.zig
sh /tmp/z9_m1_out/build_target.sh linux /tmp/z9_m1_out/prog
/tmp/z9_m1_out/prog examples/z98/z9torr/testdata/t1_single_1m.torrent
```

### seed zig1_5_clean (dump C89) — for the MD5 above
```bash
timeout 120 /tmp/z9_m0_seed/zig1_5_clean --dump-c89 examples/z98/z9torr/main.zig | md5sum
# b4403decb51c775075fb1beb89a35c73  -
```

## Expected Output
For `testdata/t1_single_1m.torrent`:
```
name: t1.bin
length: 1048576
piece length: 262144
pieces: 4
info_hash: 5bb27f309ea4f5a0a1bf338c0cf2462295d694b5
```
Invoked with no torrent path (or `--help`), the program prints the `usage:`
block from `cli.usage` and exits 1 (0 for `--help`).

## Notes
M1 (core, pure) is complete: `cli.zig` (argv parsing, `usage`, `exitCodeFor`),
`torrent.zig` (single-file bencode parse + SHA-1 `info_hash`; `piece_hashes` is a
flat `[]const u8`, 20 B/piece), `tools/ref_check.c` (C89 reference), committed
`testdata/` fixtures, and `tests/tier1.sh` (end-to-end gate:
`15 passed, 0 failed / TIER1 PASS`). `main` prints the metadata summary above.

Task 1 of M1 adds `cli.zig` (argv parsing, `usage`, `exitCodeFor`) and wires `main.zig`
to it. `main` now has `pub fn main(argc: i32, argv: [*][*]u8) void` so the emitted C
wrapper forwards `argc`/`argv`; the return type stays `void`. `parseArgs` takes the
many-pointer `[*][*]u8` (M1a: no `[]synthetic` — D2).

**M1a amendment (2026-10-08):** design around compiler defect D2 (never `[]` a
synthetic type) and cap the `.torrent` metadata:
- `parseArgs`/`argAt` take `[*][*]u8`, not `[][*]u8`.
- `Torrent.announce_list` is the fixed `[8][]const u8` + `announce_count: u32`
  (extras dropped), not `[][]const u8`.
- `MAX_TORRENT_BYTES = 3145728` (3 MiB) caps the metadata before `readAll`; an
  oversize file prints `z9torr: torrent too large` and exits 2. `MAX_PIECES` is
  derived from it. The downloaded payload stays unbounded (`total_length`,
  streamed to disk).
With these, the emitted `.c` has **zero** `-Wincompatible-pointer-types`
warnings (previously two, from argv).

Exit codes per spec §8: 0 success, 1 usage, 2 torrent/file, 3 tracker/net, 4 peer,
5 disk. The seed compiler has no `anyerror`, so `exitCodeFor` uses the brief-authorized
fixed-mapping alternative: it takes a concrete `FailureClass` enum (usage=1..disk=5).

The seed `lib/std.zig` does not re-export `file`, so `std_file` is imported by path
(`@import("std_file.zig")`). Tests: `tests/tier1_cli.sh` (CLI shapes).

**Win9x argv caveat:** on Windows 9x the CRT builds `argv` from `GetCommandLineA`, which
is subject to the 16-bit command-line length limit and Win9x quoting rules. The parser
consumes the `argv` the runtime supplies and never re-tokenizes the raw command line, so
Win9x argument handling matches the CRT's, not a custom splitter.
