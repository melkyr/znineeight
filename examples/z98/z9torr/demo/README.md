# z9torr — demo golden

`z9torr <file.torrent>` parses a single-file torrent and prints a metadata
summary. This directory records the golden commands, the emitted-C89 md5, and
the committed fixture `info_hash` values used by `tests/tier1.sh`.

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

- md5: `b0e8496d741aa130b7252bd7ebefe985` (stable 3×)
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
