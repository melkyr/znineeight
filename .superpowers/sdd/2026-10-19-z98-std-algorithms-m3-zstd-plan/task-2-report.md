# M3 Task 2 report — docs + seed rotation

Status: COMPLETE

Base commit: `65785344` (branch `zig1_improvements`).

## Step 1 — Docs

Created `sf/docs/std_lib/zstd.md`:

- RFC 8878 subset boundaries: standard frames, raw/RLE/compressed blocks,
  predefined/RLE/FSE Huffman and FSE sequence tables, repeat modes, skippable
  frames; **no dictionaries** (nonzero dict id is `error.Corrupt`).
- Window override: `ZSTD_DEFAULT_WINDOW_LOG = 21` (2 MiB); a 256 MB box passes
  `24`–`28` for `zstd --long=...` frames; the cap is checked from the frame
  header before block decode.
- Offline-compress workflow (`zstd -19`, optional `--long`, no `-D`; commit
  `.in`/`.expected`, never regenerate in a test run).
- Error contract: `error.Corrupt`, `error.OutputTooSmall`,
  `error.WindowTooBig`; no partial-output contract.

Truth-ups (current state only; historical seed notes left period-accurate):

- `STD_README.MD` — L4 row now includes `std_lz4` + `std_zstd`; module table
  row `Zstd frame decode | std_zstd | zstd.md`; domain-doc index entry.
- root `README.md` — higher-layer import list adds `std_zstd`.
- `docs/sf/QUICK_REF.md` — current seed block v106 → v107, 36 std `.zig`,
  `std_zstd`; inventory 35 `std_*.zig` + `std.zig` = 36; install recipe adds
  `sf/src/std_zstd.zig`.

## Step 2 — Seed rotation

Command:

```
bash scripts/seed/archive_seed.sh /tmp/m3_t1_build/zig1_5_clean \
  /tmp/m3_t1_build/gen release/seed/zig1-seed.tgz --update-changelog
```

Observed (rotation log `/tmp/m3_t2_rotate.log`; gcc `-Wall` warnings are the
usual unused-bootstrap-helper noise):

```
[archive] gcc-only rebuild of archive C md5 (fixed point): 21c957730d268f1e7883176fa5413b65
[archive] wrote release/seed/zig1-seed.tgz (archive md5 5ec6e497bb962ff0fdf3145311acc4a1)
## 2026-10-21 — seed v107 (HEAD 65785344)
| lib manifest | `lib/manifest.md5` (36 std files; md5 `aac8a4bf651d8d616c2b4ee3400c58f3`) |
| archive md5 | `5ec6e497bb962ff0fdf3145311acc4a1` |
[archive] prepended entry to release/seed/CHANGELOG.md
```

Verified archive contents:

```
$ tar -tzf release/seed/zig1-seed.tgz | grep '^zig1-seed/lib/.*\.zig$' | wc -l
36
$ tar -tzf release/seed/zig1-seed.tgz | grep std_zstd
zig1-seed/lib/std_zstd.zig
$ tar -xOzf release/seed/zig1-seed.tgz zig1-seed/lib/manifest.md5 | wc -l
36
$ md5sum release/seed/zig1-seed.tgz
5ec6e497bb962ff0fdf3145311acc4a1  release/seed/zig1-seed.tgz
```

Rotated-archive rebuild (two-hop closure + fixed-point gate):

```
FIXED_POINT_MD5=21c957730d268f1e7883176fa5413b65 \
  bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m3_t2_seedcheck
```

Observed:

```
[seed] hop1 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] hop2 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] two-hop closure OK: hop1 == hop2 == 21c957730d268f1e7883176fa5413b65
[seed] recorded fixed point OK: 21c957730d268f1e7883176fa5413b65
=== [seed] Done: /tmp/m3_t2_seedcheck ===
```

`/tmp/m3_t2_seedcheck/lib` has 36 files; `std_zstd.zig` matches `sf/src`
(`78571d92335b609e9176608a493f4630`).

Seed values:

| field | before (v106) | after (v107) |
|---|---|---|
| archive md5 | `46dff057dd1751a937021dba97ad118f` | `5ec6e497bb962ff0fdf3145311acc4a1` |
| lib files | 35 | 36 |
| manifest md5 | `87a231a3a2d511814cf413ae1a5586eb` | `aac8a4bf651d8d616c2b4ee3400c58f3` |
| binary md5 | `21c957730d268f1e7883176fa5413b65` | `21c957730d268f1e7883176fa5413b65` |
| fixed point | `21c957730d268f1e7883176fa5413b65` | `21c957730d268f1e7883176fa5413b65` |

## Step 3 — Full gate

Before rotation (`/tmp/m3_t1_build/zig1_5_clean`):

```
bash scripts/stdlib/verify_stdlib.sh /tmp/m3_t1_build/zig1_5_clean
...
run_fixtures: 299 PASS / 0 FAIL over 299 dirs
PASS smoke (3 vectors)
PASS std_lz4 (20 vectors)
PASS std_noise (1 vectors)
PASS std_rand (2 vectors)
PASS std_zstd (30 vectors)
run_crosscheck: 5 PASS / 0 FAIL over 5 modules
STDLIB GATE OK
```

After rotation, using the compiler rebuilt from the rotated archive
(`/tmp/m3_t2_seedcheck/zig1_5_clean`):

```
bash scripts/stdlib/verify_stdlib.sh /tmp/m3_t2_seedcheck/zig1_5_clean
...
run_fixtures: 299 PASS / 0 FAIL over 299 dirs
PASS smoke (3 vectors)
PASS std_lz4 (20 vectors)
PASS std_noise (1 vectors)
PASS std_rand (2 vectors)
PASS std_zstd (30 vectors)
run_crosscheck: 5 PASS / 0 FAIL over 5 modules
STDLIB GATE OK
```

No `sf/src` changes.

## Commits

- `657293b4` — `docs(std_lib): zstd docs (M3)` (docs + seed-script count/list
  truth-ups)
- `5115f33a` — `chore(seed): rotate (M3)` (`release/seed/CHANGELOG.md` +
  `release/seed/zig1-seed.tgz`)
- report commit follows this file (`docs(sdd): M3 T2 report`)

## Concerns

- None. Archive md5 moved as expected (new `lib/std_zstd.zig` tracked in
  `lib/manifest.md5`); binary md5 / fixed point held, confirming compiler/std
  zero coupling.

## Fix round 1 — doc accuracy (review)

Docs-only fix in `sf/docs/std_lib/zstd.md`; no code change and no seed
rotation. Full gate was not rerun (nothing executable changed).

- `cc172927` — `docs(std_lib): zstd doc accuracy fix (M3)`
- report commit follows this file — `docs(sdd): M3 T2 fix round 1`

- **Important 1 (window/level guidance).** Removed the false claim that the
  default `21` covers ordinary `-1`/`-19` output. The offline workflow now
  states that `-19` raises the window on larger inputs (libzstd 1.5.4 uses
  window log 23 on 10 MiB) and recommends `max_window_log` `23`–`24` for `-19`
  on more than 2 MiB, or constraining compression with
  `zstd --zstd=wlog=21`. Step 3 likewise recommends `23`–`24` for `-19` above
  2 MiB and notes `-1` fits the default.
- **Minor 2 (literal/sequence table modes).** Reworded to: Huffman literals are
  raw/RLE/compressed (direct-weight and FSE-compressed tree descriptions) plus
  treeless/repeat; FSE sequence tables use predefined/RLE/FSE-compressed plus
  repeat modes and repeat offsets.
- **Minor 3 (WindowTooBig wording).** Overview and error bullet now match the
  source: non-single-segment frames compare the frame **window log** against
  `max_window_log` (`sf/src/std_zstd.zig:1074-1078`), while a single-segment
  content size is compared against `2^max_window_log`.
- **Minor 4 (quick start input length).** Quick start now carries
  `packed_len` and passes `packed[0..packed_len]`, so trailing undefined bytes
  cannot cause a bogus magic/`error.Corrupt`.

Verification (host zstd 1.5.4, no repo changes):

```
$ zstd -19 -f /tmp/zstd_3m.bin -o /tmp/zstd_3m.zst && zstd -lv /tmp/zstd_3m.zst
Window Size: 3.00 MiB (3145728 B)        # single-segment, > 2^21
$ zstd -19 -f /tmp/zstd_10m.bin -o /tmp/zstd_10m.zst && zstd -lv /tmp/zstd_10m.zst
Window Size: 8.00 MiB (8388608 B)        # window log 23
```

Source check for the `WindowTooBig` contract:

```
sf/src/std_zstd.zig:1074-1078  wlog = 10 + exp; if (wlog > max_window_log) return error.WindowTooBig;
sf/src/std_zstd.zig:1113-1114  window_size = frame_size; if (window_size > windowCap(max_window_log)) ...
```
