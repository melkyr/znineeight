# z9torr — demo golden

`z9torr <file.torrent>` parses a single-file torrent, announces to the tracker,
and downloads the payload from up to `--max-peers` peers (rarest-first, one
coroutine per announced peer, verifying every piece by SHA-1, with
cross-restart resume). This directory records the golden commands, the
emitted-C89 md5, the committed fixture hashes, and the
`tests/tier1.sh`/`tests/tier2.sh` gates.

## Build and run (binding seed recipe)

From the repository root:

```bash
mkdir -p /tmp/z9torr_demo
timeout 120 /tmp/z9_m0_seed/zig1_5_clean -ffast -o /tmp/z9torr_demo examples/z98/z9torr/main.zig
sh /tmp/z9torr_demo/build_target.sh linux /tmp/z9torr_demo/prog
/tmp/z9torr_demo/prog examples/z98/z9torr/testdata/t1_single_1m.torrent
```

Expected stdout for `t1_single_1m.torrent`:

```
name: t1.bin
length: 1048576
piece length: 262144
pieces: 4
info_hash: 5bb27f309ea4f5a0a1bf338c0cf2462295d694b5
```

## `--dump-c89` md5

Byte-identity gate over the emitted C89 on stdout (bare dump, warnings on
stderr). Compiler: binding seed `/tmp/z9_m0_seed/zig1_5_clean`.

```bash
cd /workspace/znineeight
timeout 120 /tmp/z9_m0_seed/zig1_5_clean --dump-c89 examples/z98/z9torr/main.zig | md5sum
```

- md5: `b24be5e55c6a885d40d85fce97c97fcc` (stable 3×; M3 Task 4 + stats-delta guard)
- command: `timeout 120 /tmp/z9_m0_seed/zig1_5_clean --dump-c89 examples/z98/z9torr/main.zig | md5sum`

## Fixtures and `info_hash`

`info_hash` is SHA-1 over the **exact** `info` dictionary bytes (never
re-encoded), computed by `z9torr`, by `tools/ref_check.c`, and committed under
`testdata/expected/<name>.infohash` — all three must agree.

| fixture | payload | `piece length` | pieces | `info.name` | payload sha1 | info_hash |
|---|---|---|---|---|---|---|
| `t1_single_1m`   | 1 048 576 B | 262144 | 4   | `t1.bin` | `7a985d40cf76ef129b2889fa5bfce75304067dc9` | `5bb27f309ea4f5a0a1bf338c0cf2462295d694b5` |
| `t2_single_25m`  | 26 214 400 B | 262144 | 100 | `t2.bin` | `00fcf3e712b1271e12542032a2797248590673d3` | `7e01c65cc1c75f4e82f023782927a1eb6d9239f5` |
| `t5_unicode_name` | 30 000 B | 16384 | 2 | `naïve_日本.txt` | `e45424576f6f969f43a7ec4f3546291c2435ff45` | `900776c4c462a8f13e6db288a209da21eaa29727` |

The `ref_check.c` reference uses the same recipe (no `-m32` needed):

```bash
gcc -std=c89 -O0 -Wall -o /tmp/ref_check examples/z98/z9torr/tools/ref_check.c
/tmp/ref_check --infohash examples/z98/z9torr/testdata/t1_single_1m.torrent
# infohash 5bb27f309ea4f5a0a1bf338c0cf2462295d694b5
```

## Tier-1 gate

```bash
bash examples/z98/z9torr/tests/tier1.sh
```

Builds via the recipe above, then asserts per fixture: exit 3 (the fixture's
tracker is unreachable, so the run stops after printing the metadata, per spec
§8), printed `info_hash` == committed expected == `ref_check`, and 3×
byte-identical stdout.
Malformed inputs (truncated file, bad piece count, mutated `info` byte) must
each exit 2 with the typed `z9torr: malformed torrent` message. Summary:
`15 passed, 0 failed` → `TIER1 PASS`. The gate fails closed if
`127.0.0.1:6969` is already listening (spec §12 item 9): a leftover
`mock_tracker` would turn the intended tracker-unreachable exit 3 into a peer
error and silently misread, so the guard aborts with exit 1 instead.

### Malformed-input note

A single `info` byte mutation that keeps the bencode valid (e.g. `t1.bin` →
`X1.bin`) simply changes the computed `info_hash`; `z9torr` has no external
expected hash to compare against, so it correctly exits 0 (hash
`eb62affad7137a6d2fa381bc764633a8562d2c3c`). The brief's literal
"info byte → info_hash mismatch → exit 2" is therefore not achievable. The
gate instead mutates an `info` byte to trip a real typed check: `t1.bin` →
`/1.bin`, whose leading path separator fails the single-file path-safety check
(`BadFilePath`) while still exercising the exact `info`-span bytes.

## Tier-2 gate (download + resume)

```bash
bash examples/z98/z9torr/tests/tier2.sh
```

Builds `z9torr` + `mock_tracker` (`:6969`) + `mock_peer` with the binding
recipe, generates the two golden payloads with the `tests/mkfixture.sh`
`awk srand` recipe, and starts `mock_tracker` advertising **every** declared
peer port (`testdata/ports.txt`: tracker `6969`, peers `6970`–`6973`). The
multi-peer cases start one `mock_peer` per peer port; the single-peer and
malformed cases start only the first. It asserts:

| case | assertion | observed |
|---|---|---|
| `t1_single_1m` download | exit 0 + `sha1sum` == `7a985d40cf76ef129b2889fa5bfce75304067dc9` | `summary: fetched=1048576 requests=64` |
| `t2_single_25m` multi-peer download | exit 0 + `sha1sum` == `00fcf3e712b1271e12542032a2797248590673d3` | `summary: fetched=26214400 requests=1600` |
| no-double-request invariant | `Z9TORR_CLAIM_LOG=1` yields exactly 100 `claim slot=.. piece=..` lines over 100 distinct piece indices | `100 claims / 100 unique pieces` |
| multi-peer actually used | >1 distinct peer slot in the claim log | `4 peer slots claimed work` |
| interrupt + restart `t2` (multi-peer) | exit 0 + sha1 == expected + non-empty sidecar `partial[]` + fetched < cold | cold `26214400` → restart `25837568` (run-specific) |
| `mock_peer --mode bad-bitfield-length` | exit 4 | `z9torr: peer error` |
| `mock_peer --mode wrong-info-hash` | exit 4 | `z9torr: peer error` |

Summary: `17 passed, 0 failed` → `TIER2 PASS`.

### Multi-peer scheduler invariant

With `Z9TORR_CLAIM_LOG=1` each scheduler claim prints one
`claim slot=<n> piece=<i>` line (`peer.zig`). Rarest-first selection
(`pickPiece`) and `claim` are consecutive with no suspension between them, so a
piece is claimed exactly once; the gate extracts those lines and asserts 100
claims over 100 distinct piece indices (no duplicate requests) and that more
than one peer slot did work. `main.zig` also retires each finished peer via
`scheduler.removePeer` in the drive loop so its availability bits stop
inflating `piece_rarest` and the stats peer count tracks live peers only.

### Resume evidence

The resume case runs `t2` under fresh `mock_peer`s, waits until
`.z9torr.resume` has ≥1 verified piece (`completed_bits` non-zero) **and** a
non-empty `partial[]` (bencoded `7:partialld…`), then `kill -9`s the client and
restarts it against fresh `mock_peer`s. The restart's `summary: fetched=` is
strictly less than the cold run's — the partial piece's already-written 16 KiB
blocks are seeded from the sidecar `block_mask` and not re-requested:

```
cold    summary: fetched=26214400 requests=1600
restart summary: fetched=25837568 requests=...
```

(These are one observed run; the restart figures vary with the kill point,
i.e. how many pieces/blocks were already on disk. The cold run always fetches
the full payload, `26214400` bytes / `1600` requests.)

Both SHA-1 to `testdata/expected/t2_single_25m.sha1` (`00fcf3e7…`). The gate runs
each client in a fresh temp CWD (`$OUT/run.*`), so no `t1.bin`/`t2.bin`/
`.z9torr.resume` leaks into the repository.

## Flags

`cli.usage` surfaces the bounds and `parseArgs` enforces them (a violation is a
usage error: exit 1):

- `--max-peers N` — concurrent peers. `1..100` are accepted; values above `100`
  are rejected. The runtime clamps the request to the 16-slot cap
  (`MAX_RUNTIME_PEERS`) and to the announced peer count, so the visible maximum
  is `16`.
- `--max-down N` — download limit in bytes/s. `0` means unlimited; a nonzero
  value below one 16384-byte block quantum (`--max-down >= 16384`) or above
  `65535` is a usage error.
- `--max-up N` — upload limit in bytes/s. `0` means unlimited; a nonzero value
  below one 13-byte request frame (`--max-up >= 13`) is a usage error.
