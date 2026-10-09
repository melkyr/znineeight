# z9torr — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `b71088ed` (M3 sources Task 0–3; Task 4 multi-peer tier2 + `removePeer` wiring + docs on top)

**MD5 (`--dump-c89`):** `5fe4a00979e129c39c2ffec0a7bec792` (seed `zig1_5_clean`; stable 3×; M3 Task 4)

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
# 5fe4a00979e129c39c2ffec0a7bec792  -
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

**M2 (single-peer download + resume) is complete (2026-10-08).** New modules:
`wire.zig` (BE framing + handshake), `tracker.zig` (HTTP announce + compact
peers), `disk.zig` (single-file write-through + read-back), `resume.zig`
(fastresume sidecar `.z9torr.resume` + re-hash), `piece.zig` (depth-4 request
pipeline + SHA-1 verify), `peer.zig` (one peer coroutine), and
`tools/mock_tracker.zig` (`:6969`) + `tools/mock_peer.zig` (`:6970`). `main`
announces, downloads, verifies, and prints a `summary: fetched=<bytes>
requests=<n>` line at exit.

Resume uses the sidecar's `completed_bits` plus a `partial` list of
`{index, block_mask}` entries (one per half-downloaded piece); on restart the
present 16 KiB blocks are seeded as already-received so only the missing blocks
are requested. A `bitfield` whose body is not exactly `ceil(n_pieces/8)` bytes
rejects the peer (exit 4).

Tests: `tests/tier1.sh` (15/0; parse + `ref_check`), `tests/tier1_cli.sh` (CLI
shapes), `tests/tier2.sh` (15/0; download `t1`/`t2`, interrupt+restart resume
with strictly-fewer fetched bytes, malformed-peer rejection). The `--dump-c89`
md5 above is stable 3× for the M2 source.

## M3 — multi-peer + scheduler + rate limits (2026-10-08)

New modules: `scheduler.zig` (rarest-first `Scheduler` + `addPeer`/`removePeer`),
`ratelimit.zig` (`TokenBucket`), `stats.zig` (`statsRender`); `main.zig` now
spawns one coroutine per announced peer (up to the 16-slot runtime cap) and
shares two global token buckets refilled on a 100 ms cadence. `mock_tracker.zig`
advertises N compact peers via `--peers a,b,c` / repeatable `--peer`.

Flags (from `cli.usage`): `--max-peers N` (1..100 accepted; runtime clamps to
`MAX_RUNTIME_PEERS = 16` and to the announced count), `--max-up N` (`0` or
`>= 13`), `--max-down N` (`0` or `16384..65535`). A nonzero rate below one
request/block quantum is a usage error (exit 1).

Operator ruling #3: the `main.zig` drive loop calls
`scheduler.removePeer(&g_sched, &g_sched.peers[slot])` for every spawned slot
whose task is `done`/`cancelled` after each `tick`, so finished peers stop
inflating `piece_rarest` and the stats peer count. `removePeer` early-returns on
an inactive slot (repeat-safe) and is never called on a live task.

Tests: `tests/tier2.sh` now runs 4 `mock_peer`s on the declared ports
(`testdata/ports.txt` = tracker `6969`, peers `6970`–`6973`) and asserts, for
`t2_single_25m`: exit 0 + SHA-1; the no-double-request invariant via
`Z9TORR_CLAIM_LOG=1` (100 claims / 100 unique pieces); that >1 peer slot worked
(observed 4); and a multi-peer interrupt/restart resume with strictly-fewer
fetched bytes. `tests/tier1.sh` fails closed if `127.0.0.1:6969` is already
listening (spec §12 item 9). Gates: tier1 `15/0`, tier1_cli all pass, tier2
`17/0`.

The `--dump-c89` md5 above is stable 3× for the M3 Task 4 source; refresh with
`timeout 120 /tmp/z9_m0_seed/zig1_5_clean --dump-c89 examples/z98/z9torr/main.zig | md5sum`.

Next: M4 (`2026-10-08-z9torr-m4-win9x-plan.md`).
