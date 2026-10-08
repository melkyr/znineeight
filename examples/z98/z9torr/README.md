# z9torr

z9torr — a BitTorrent client example for the Z98 bootstrap compiler.

This is the M1 "core (pure)" milestone: `z9torr <file.torrent>` parses a
single-file torrent and prints a metadata summary (name, length, piece length,
piece count, `info_hash`) — no sockets yet.

## Files
- `main.zig`: Entry point. Parses the torrent and prints the metadata summary.
- `cli.zig`: `Args`/`parseArgs`/`usage`/`exitCodeFor` (spec §8 exit codes).
- `torrent.zig`: single-file bencode parse + SHA-1 `info_hash`.
- `tools/ref_check.c`: C89 reference for `--infohash` cross-checks.
- `tests/tier1_cli.sh`, `tests/tier1.sh`: CLI-shape and end-to-end gates.
- `testdata/`, `demo/`: committed fixtures, goldens, and golden commands.
- `NOTES.md`, `README.md`: build recipes, expected output, and status.

## Build and Run

```bash
mkdir -p /tmp/z9_m1_out
timeout 120 /tmp/z9_m0_seed/zig1_5_clean -ffast -o /tmp/z9_m1_out examples/z98/z9torr/main.zig
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
M1 complete. End-to-end gate: `bash examples/z98/z9torr/tests/tier1.sh` →
`15 passed, 0 failed / TIER1 PASS`. Downloading lands in M2.
