# z9torr M1a report — D2 design-around (no nested slices) + `.torrent` size cap

Base: `85d4c12e` (branch `zig1_improvements`, no push). Compiler frozen
(`/tmp/z9_m0_seed/zig1_5_clean`); no changes under `sf/src/**`, `scripts/**`,
`repro/**`, `release/**`. Edits via `edit`/`fastedit` only.

## Summary

Executed Changes 1–4 and Verify 1–4 from `m1a-brief.md`. All nested-slice types
are gone from the example by design; the `.torrent` metadata is capped at 3 MiB
with a distinct error. Example emits **zero** `-Wincompatible-pointer-types`
warnings (was 2, from argv). Gates green: `tier1_cli` 6/6, `tier1` 15/15,
25/25 example matrix, `N2` (`[8][]const u8` + `announce_count: u32`) compiles
and runs.

Single commit on top of `85d4c12e` with message
`refactor(z9torr): design around D2 (no nested slices) + .torrent size cap`.

## Changes

### 1. `examples/z98/z9torr/cli.zig`
- `argAt(argv: [][*]u8, …)` → `argAt(argv: [*][*]u8, …)` (body unchanged).
- `parseArgs(argc, argv: [][*]u8)` → `parseArgs(argc, argv: [*][*]u8)` (body unchanged).

### 2. `examples/z98/z9torr/main.zig`
- `main` already took `(argc: i32, argv: [*][*]u8)`; removed `const n` +
  `var av: [][*]u8 = argv[0..n]` and now calls `cli.parseArgs(argc, argv)`.
- **E2 cap:** after `exists`, open the file via `filemod.open(Mode.Read)`,
  `filemod.size`, `filemod.close` (open→size→close). `sz < 0` → existing
  `"z9torr: cannot read torrent file"` (exit 2); `sz > torrentlib.MAX_TORRENT_BYTES`
  (`3145728`) → `"z9torr: torrent too large"` (exit 2, `FailureClass.torrent`).
- The new `catch` blocks end in `return;` (seed requires a terminating
  `return;` for `catch` blocks that call `std.os.exit`, else gcc sees an int→File
  assignment; see Build notes).

### 3. `examples/z98/z9torr/torrent.zig`
- `Torrent`: `announce_list: [][]const u8` → `announce_list: [8][]const u8` +
  `announce_count: u32` (piece_hashes stays flat `[]const u8`).
- Constants: added `MAX_ANNOUNCE_LIST = 8`, `MAX_TORRENT_BYTES = 3145728`
  (3 MiB); replaced `MAX_PIECES = 1048576` with
  `MAX_PIECES = MAX_TORRENT_BYTES / HASH_LEN` (= 157286).
- `load` first line: `if (file_bytes.len > MAX_TORRENT_BYTES) return error.TooLarge;`.
- Announce-list block rewritten: init all `MAX_ANNOUNCE_LIST` entries to `""`;
  walk tiers/strings; store `.bytes` while `fill < MAX_ANNOUNCE_LIST` (extras
  dropped); `result.announce_count = @intCast(u32, fill)`; absent → 0. No
  allocation, no `@ptrCast`, no `[][]const u8`.
- Header + `piece_hashes` comment updated to state the D2 rule.

### 4. Docs
- **Spec** §6: `announce_list: [8][]const u8` + `announce_count: u32`; the
  amendment note now states the **rule** (a slice `[]T` is safe only for a
  primitive or *named* `T`; never `[]` a synthetic type — use flat bytes,
  `[N]T`, or a named wrapper). §9: new bullet recording the 3 MiB metadata cap
  (arena-bound, distinct error before `readAll`, `MAX_PIECES` derived) and that
  the **downloaded payload is unbounded** (`total_length`, streamed to disk).
- **M1 plan** Task 1 interface → `[*][*]u8`; Task 2 interface →
  `[8][]const u8` + `announce_count: u32` + `MAX_TORRENT_BYTES`/`MAX_PIECES`.
- **M2 plan**: no `announce_list`/nested-slice mentions existed; added a D2-rule
  bullet to Self-Review confirming M1's shape and that M2's `[]PeerAddr` /
  `[]PieceState` / `[]BlockState` are slices of *named* structs (safe, no
  `[]synthetic`).
- **`examples/torrent_example_defects.md`** D2: added the variants the compiler
  fix must cover (`[][]const u8`, `[][20]u8`, `[][*]u8`, `[]?T`, `[]tuple`),
  the safe/unsafe design rule, and rewrote the workaround to "remove every
  `[]`-of-synthetic type by design". Root-cause/proper-fix text kept.
- **`NOTES.md`**: `--dump-c89` MD5 `b0e8496d…` → `b4403dec…` (stable 3×); added
  the M1a amendment note; fixed the now-stale `parseArgs` `[][*]u8` sentence.

## Deviations

1. `MAX_TORRENT_BYTES` is `pub const` (brief wrote `const`) so `main.zig` can
   reference it instead of duplicating the magic number `3145728`. Value and
   behavior are exactly per brief.
2. The two new size-check `catch` blocks and the `sz < 0` / `sz > cap` branches
   end in `return;` (required by the seed's `catch` typing under `std.os.exit`;
   mirrors the pre-existing `readAll`/`load` catch blocks).
3. D2 variants also list `[]?T`/`[]tuple` with "expected to collide" (not
   separately reproduced); the reproducer covers slice-of-slice/array/pointer.

## Verify (exact commands + results)

### V1 — gate (`tier1_cli` + `tier1`)
```
$ bash examples/z98/z9torr/tests/tier1_cli.sh
ok   - --help exit 0 + usage on stdout
ok   - no args exit 1
ok   - unknown flag exit 1
ok   - --max-peers 101 exit 1
ok   - missing torrent exit 2
ok   - --max-down 70000 exit 1
== tier1_cli: all passed ==        (rc=0, 6/6)

$ bash examples/z98/z9torr/tests/tier1.sh
ok   - t1_single_1m: z9torr exit 0
ok   - t1_single_1m: info_hash == expected (5bb27f309ea4f5a0a1bf338c0cf2462295d694b5)
ok   - t1_single_1m: info_hash == ref_check (5bb27f309ea4f5a0a1bf338c0cf2462295d694b5)
ok   - t1_single_1m: deterministic 3x (byte-identical stdout)
ok   - t2_single_25m: z9torr exit 0
ok   - t2_single_25m: info_hash == expected (7e01c65cc1c75f4e82f023782927a1eb6d9239f5)
ok   - t2_single_25m: info_hash == ref_check (7e01c65cc1c75f4e82f023782927a1eb6d9239f5)
ok   - t2_single_25m: deterministic 3x (byte-identical stdout)
ok   - t5_unicode_name: z9torr exit 0
ok   - t5_unicode_name: info_hash == expected (900776c4c462a8f13e6db288a209da21eaa29727)
ok   - t5_unicode_name: info_hash == ref_check (900776c4c462a8f13e6db288a209da21eaa29727)
ok   - t5_unicode_name: deterministic 3x (byte-identical stdout)
ok   - truncated file: exit 2 + typed message
ok   - bad piece count: exit 2 + typed message
ok   - mutated info byte: exit 2 + typed message
== tier1 summary: 15 passed, 0 failed ==
TIER1 PASS                          (rc=0, 15/15)
```

### V2 — zero `-Wincompatible-pointer-types` in the example's emitted `.c`
Binding recipe into `/tmp/z9torr_m1a`; `build_target.sh` build log:
```
$ grep -c 'Wincompatible-pointer-types' /tmp/z9torr_m1a/build.log
0
```
Baseline (`85d4c12e`) had 2 (`main_*.c:169` argv, `cli_*.c:65` argv). Both gone.

### V3 — 25-example matrix
Built all 25 `examples/z98/*/` entries with the binding seed + target linker:
```
MATRIX: 25 PASS / 0 FAIL
```
z9torr builds, links, and runs (`t1` info_hash unchanged).

### Extra — E2 cap + announce-list path
```
$ dd if=/dev/zero of=big.torrent bs=1M count=4
$ /tmp/z9torr_m1a/prog big.torrent ; echo rc=$?
z9torr: torrent too large
rc=2

# 10-URL announce-list injected into t1 (top-level, info_hash preserved):
$ /tmp/z9torr_m1a/prog al.torrent
name: t1.bin
length: 1048576
piece length: 262144
pieces: 4
info_hash: 5bb27f309ea4f5a0a1bf338c0cf2462295d694b5
rc=0
```
(confirms parse path + >8 extras dropped without error; `announce_count` not
displayed by `main`.)

### N2 build-time verification
`[8][]const u8` + `announce_count: u32` compiled and linked on the seed on the
first successful attempt (no fallback). The seed's only complaints were the
pre-existing `warning[3037] potential null pointer dereference` (14, identical
count before/after) and the one transient gcc error from a `catch` block missing
`return;`, fixed as noted.

### New `--dump-c89` MD5
```
$ timeout 120 /tmp/z9_m0_seed/zig1_5_clean --dump-c89 examples/z98/z9torr/main.zig | md5sum
b4403decb51c775075fb1beb89a35c73  -    (stable 3×)
```

## Files changed
Source: `examples/z98/z9torr/{cli,main,torrent}.zig`.
Docs: spec §6/§9, M1 plan, M2 plan, `examples/torrent_example_defects.md`,
`examples/z98/z9torr/NOTES.md`, this report.

## Concerns

- None blocking. `MAX_TORRENT_BYTES` is `pub` (see Deviations #1).
- Pre-existing untracked scratch files in repo root (`anytype_pos.z98`, `*.err`,
  etc.) and two modified `progress.md` ledgers were left untouched and not
  staged; commit is scoped to the files listed above.
