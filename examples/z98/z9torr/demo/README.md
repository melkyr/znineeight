# z9torr — demo golden

`z9torr <file.torrent>` parses a single-file torrent, announces to the tracker,
and downloads the payload from one peer (verifying every piece by SHA-1, with
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

- md5: `b6595db02d0a4fadb497a1becdb703cd` (stable 3×)
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

Builds via the recipe above, then asserts per fixture: exit 0, printed
`info_hash` == committed expected == `ref_check`, and 3× byte-identical stdout.
Malformed inputs (truncated file, bad piece count, mutated `info` byte) must
each exit 2 with the typed `z9torr: malformed torrent` message. Summary:
`15 passed, 0 failed` → `TIER1 PASS`.

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

Builds `z9torr` + `mock_tracker` (`:6969`) + `mock_peer` (`:6970`) with the
binding recipe, generates the two golden payloads with the `tests/mkfixture.sh`
`awk srand` recipe, and asserts:

| case | assertion | observed |
|---|---|---|
| `t1_single_1m` download | exit 0 + `sha1sum` == `7a985d40cf76ef129b2889fa5bfce75304067dc9` | `summary: fetched=1048576 requests=64` |
| `t2_single_25m` download | exit 0 + `sha1sum` == `00fcf3e712b1271e12542032a2797248590673d3` | `summary: fetched=26214400 requests=1600` |
| interrupt + restart `t2` | exit 0 + sha1 == expected + non-empty sidecar `partial[]` + fetched < cold | cold `26214400` → restart `25870336` (requests `1600` → `1579`) |
| `mock_peer --mode bad-bitfield-length` | exit 4 | `z9torr: peer error` |
| `mock_peer --mode wrong-info-hash` | exit 4 | `z9torr: peer error` |

Summary: `15 passed, 0 failed` → `TIER2 PASS`.

### Resume evidence

The resume case runs `t2` under a fresh `mock_peer`, waits until
`.z9torr.resume` has ≥1 verified piece (`completed_bits` non-zero) **and** a
non-empty `partial[]` (bencoded `7:partialld…`), then `kill -9`s the client and
restarts it against a fresh `mock_peer`. The restart's `summary: fetched=` is
strictly less than the cold run's — the partial piece's already-written 16 KiB
blocks are seeded from the sidecar `block_mask` and not re-requested:

```
cold    summary: fetched=26214400 requests=1600
restart summary: fetched=25870336 requests=1579
```

Both SHA-1 to `testdata/expected/t2_single_25m.sha1` (`00fcf3e7…`). The gate runs
each client in a fresh temp CWD (`$OUT/run.*`), so no `t1.bin`/`t2.bin`/
`.z9torr.resume` leaks into the repository.
