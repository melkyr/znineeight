# z9torr

z9torr — a BitTorrent client example for the Z98 bootstrap compiler.

This is the **M4 "real-swarm compatibility"** milestone. `z9torr <file.torrent>`
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
- `tools/`: C89 `ref_check` plus the mock tracker/peer/MSE/UDP-tracker.
- `tests/`: `tier1.sh`, `tier1_cli.sh`, `tier1_unit.sh`, `tier2.sh`,
  `tier3_encrypted.sh`, `tier_udp_tracker.sh`, `tier_dht.sh`, `tier_pex.sh`
  (hard gates) and `tier_real.sh` (best-effort real swarm).
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
M4 "real-swarm compatibility" complete. Hard gates (all PASS, run from the repo
root): `tier1.sh` `16/0`, `tier1_cli.sh` `8/8`, `tier1_unit.sh` `3/3`,
`tier2.sh` `17/0`, `tier3_encrypted.sh` `5/0`, `tier_udp_tracker.sh` `7/0`,
`tier_dht.sh` `4/0`, `tier_pex.sh` `11/0`. `scripts/stdlib/verify_stdlib.sh` is
green (`283 PASS / 0 FAIL`) and the compiler fixed point is untouched.

`tier_real.sh` is a **best-effort** real-swarm tier (not part of the hard gate
set): it exits `0` only on measured payload progress, `77` with an explicit
classified `SKIP: <reason>` when the client exits a recognized environmental code
(parse/tracker/peer/disk/timeout) because the network denies reachability, and
`1` on a build error, an unexpected internal state, or any other (crash/signal)
client exit. Next: M5 — Win9x cross-compat
(`docs/superpowers/plans/2026-10-08-z9torr-m5-win9x-plan.md`).
