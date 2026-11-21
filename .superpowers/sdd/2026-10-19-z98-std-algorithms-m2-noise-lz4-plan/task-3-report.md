# M2 Task 3 report — usage, docs, truth-ups, seed rotation

Status: COMPLETE

Plan: `docs/superpowers/plans/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan.md` Task 3.
Branch: `zig1_improvements`. Compiler: `/tmp/m2_t1d_build/zig1_5_clean`
(md5 `21c957730d268f1e7883176fa5413b65`).

## Step 1 — usage program

Created `stdlib_test/noise_lz4_usage/main.zig`. Fixed seed only
(`SEED = 0x5EED1234`, expanded via `std_rand.xoshiroInit`, no clock/env):
samples 2D/3D noise, checks `[-1, 1]`, checks two identical inits are
bit-identical, checks `noiseFbm2d(..., octaves=0) == 0.0`, decodes an embedded
valid 16-byte all-literals LZ4 block.

Commands + observed output:

```
$ bash scripts/stdlib/run_fixtures.sh --capture /tmp/m2_t1d_build/zig1_5_clean stdlib_test/noise_lz4_usage
CAPTURED stdlib_test/noise_lz4_usage (stdout 71 bytes, rc 0)
----------------------------------------
run_fixtures: --capture mode (goldens written; review before committing)
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
```

Captured `expected.txt`:

```
range: 128 ok
determinism: 128 ok
fbm0: 0.0
lz4: 16 bytes
noise_lz4 ok
```

`expected.rc` = `0`. Independent non-capture re-run:

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t1d_build/zig1_5_clean stdlib_test/noise_lz4_usage
PASS stdlib_test/noise_lz4_usage
----------------------------------------
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
```

`scripts/stdlib/expected_dirs.txt`: inserted
`stdlib_test/noise_lz4_usage` (the noise/lz4 fixture dirs were already pinned
by Tasks 1–2).

## Step 2 — docs

- Extended existing `sf/docs/std_lib/noise.md` (did not recreate): added the
  exact fBm stack (`frequency/amplitude = 1.0`, per-octave `*= lacunarity/gain`,
  no normalization), validation gotchas, and a usage-program pin. The pinned
  2014 seed-0 lattice values were **corrected in fix round 1** to the
  authoritative ref/vector output (see below); the "blueprint §5.5
  zero-at-lattice superseded" statement remains.
- Extended `sf/docs/std_lib/codecs.md` with `std_lz4`: module table/import,
  overview contract, full `lz4DecompressBlock` API (returns bytes written;
  `error.Corrupt` vs `error.OutputTooSmall`; last-5-literals / last-match-12
  rules; raw block not frame; little-endian offsets; no allocation/state),
  and the offline-compress workflow (host `lz4` block API or extract a frame's
  block payload; commit raw block + expected separately; no runtime host-lz4
  dependency).

## Step 3 — truth-ups

- `STD_README.MD`: domain-table rows for `std_rand`→`rand.md`,
  `std_noise`→`noise.md`, `std_lz4`→`codecs.md`; doc-index entries for
  `rand.md`, `noise.md`, and `std_lz4` added to the codecs description.
- `README.md`: higher-layer path-import list now includes `std_noise`,
  `std_lz4`.
- `docs/sf/QUICK_REF.md`: std inventory now 34 `std_*.zig` + `std.zig` = 35
  (list includes `std_lz4`); install recipe adds `std_noise.zig` and
  `std_lz4.zig`.
- `scripts/seed/archive_seed.sh`: module comment/list and `SEED_README.txt`
  template/CHANGELOG template now say 35 with `std_lz4.zig`.
- `scripts/seed/build_from_seed.sh`: stale `32` std-lib comment → `35`.

Docs/truth-up checks observed:

```
$ grep -n "std_rand\|std_noise\|std_lz4\|rand.md\|noise.md\|codecs.md" STD_README.MD
132:| PCG32 / xoshiro256\*\* pseudorandom generators | `std_rand` | [rand.md](sf/docs/std_lib/rand.md) |
133:| OpenSimplex 2D/3D noise and fBm | `std_noise` | [noise.md](sf/docs/std_lib/noise.md) |
134:| LZ4 raw block decode | `std_lz4` | [codecs.md](sf/docs/std_lib/codecs.md) |
...
214:- [rand.md](sf/docs/std_lib/rand.md) ...
216:- [noise.md](sf/docs/std_lib/noise.md) ...
218:- [codecs.md](sf/docs/std_lib/codecs.md) — ... `std_lz4` ...

$ grep -n "std_noise\|std_lz4" README.md
298:`std_rand`, `std_noise`, `std_lz4`)

$ grep -n "std set is\|installs all\|std_lz4.zig <exe\|Current seed" docs/sf/QUICK_REF.md
27:**Current seed: v106** ...
105:**Std-module inventory:** the `sf/src` std set is **34** `std_*.zig` + `std.zig`
114:`scripts/seed/build_from_seed.sh` installs all 35 ...
232:  `mkdir -p <exe_dir>/lib && cp ... sf/src/std_rand.zig sf/src/std_noise.zig sf/src/std_lz4.zig <exe_dir>/lib/`

$ grep -n "35 std\|all 35\|std_lz4.zig" scripts/seed/archive_seed.sh scripts/seed/build_from_seed.sh
scripts/seed/archive_seed.sh:165:zig1-seed/lib/        the 35 std .zig ...
scripts/seed/archive_seed.sh:174:                      std_rand.zig, std_noise.zig, std_lz4.zig)
scripts/seed/archive_seed.sh:175:zig1-seed/lib/manifest.md5  per-file md5 of every lib/*.zig (35 std files,
scripts/seed/archive_seed.sh:315:| lib manifest | `lib/manifest.md5` (35 std files; ...
scripts/seed/build_from_seed.sh:24:#   std lib: 35 std .zig copied into <out>/lib/

$ grep -n "Offline-compress workflow\|error.OutputTooSmall\|std_lz4" sf/docs/std_lib/codecs.md
1:# Codecs — ... + `std_lz4`
5:| **Modules** | ... `std_lz4` |
...
1159:- `error.OutputTooSmall` — ...
$ grep -n "fBm parameters\|seed 0\|superseded\|noise_lz4_usage" sf/docs/std_lib/noise.md
18:for the lattice behavior: at seed 0, ...
19:`(1,1)` are nonzero (blueprint §5.5 zero-at-integer-lattice is superseded).
48:**Lattice pin (2014 reference, seed 0):** ...
152:**fBm parameters (exact stack)** ...
174:| usage program | ... stdlib_test/noise_lz4_usage ... |
```

## Step 4 — seed rotation (v106)

Command (full command; gcc emitted only pre-existing unused-helper warnings):

```
$ bash scripts/seed/archive_seed.sh /tmp/m2_t1d_build/zig1_5_clean /tmp/m2_t1d_build/gen release/seed/zig1-seed.tgz --update-changelog
[archive] gcc-only rebuild of archive C md5 (fixed point): 21c957730d268f1e7883176fa5413b65
[archive] wrote release/seed/zig1-seed.tgz (archive md5 46dff057dd1751a937021dba97ad118f)
--- CHANGELOG entry ---
## 2026-10-21 — seed v106 (HEAD 51ca1fd2)
| seed binary md5 | `21c957730d268f1e7883176fa5413b65` |
| self-emission C | 46 `.c` + 47 `.h` (10307965 bytes) |
| fixed point | `21c957730d268f1e7883176fa5413b65` |
| lib manifest | `lib/manifest.md5` (35 std files; md5 `87a231a3a2d511814cf413ae1a5586eb`) |
| archive md5 | `46dff057dd1751a937021dba97ad118f` |
[archive] prepended entry to /workspace/znineeight/release/seed/CHANGELOG.md
```

Archive/manifest evidence:

```
$ md5sum release/seed/zig1-seed.tgz
46dff057dd1751a937021dba97ad118f  release/seed/zig1-seed.tgz
$ tar -tzf release/seed/zig1-seed.tgz | grep -c '^zig1-seed/lib/std.*\.zig$'
35
$ tar -tzf release/seed/zig1-seed.tgz | grep 'manifest.md5\|std_lz4\|std_noise'
zig1-seed/lib/std_noise.zig
zig1-seed/lib/manifest.md5
zig1-seed/lib/std_lz4.zig
$ tar -xOzf release/seed/zig1-seed.tgz zig1-seed/lib/manifest.md5 > /tmp/m2_t3_manifest.md5
$ wc -l < /tmp/m2_t3_manifest.md5
35
$ md5sum /tmp/m2_t3_manifest.md5
87a231a3a2d511814cf413ae1a5586eb  /tmp/m2_t3_manifest.md5
$ grep -E "std_lz4|std_noise|std_rand" /tmp/m2_t3_manifest.md5
b895490d1df8184011ee32bd57f2225a  std_lz4.zig
b8d8f628c5631b6746fa97e4d1ac02dc  std_noise.zig
732f34adf8c2d3ed34ca90d86b050f09  std_rand.zig
```

Binary md5 / fixed point remain `21c957730d268f1e7883176fa5413b65`
(unchanged from v105). `docs/sf/QUICK_REF.md` current-seed block updated to
v106/archive `46dff057...`/manifest `87a231a3...`/35 files.

## Step 5 — full gate

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m2_t1d_build/zig1_5_clean
...
run_fixtures: 297 PASS / 0 FAIL over 297 dirs
== std-lib crosscheck gate ==
PASS smoke (3 vectors)
PASS std_lz4 (20 vectors)
PASS std_noise (1 vectors)
PASS std_rand (2 vectors)
----------------------------------------
run_crosscheck: 4 PASS / 0 FAIL over 4 modules
STDLIB GATE OK
```

Exit status `0`. The new `stdlib_test/noise_lz4_usage` is included in the 297
and each fixture ran 3× byte-identically (harness determinism rule).

## Commits / concerns

- `660adfcd` — `docs(std_lib): noise + lz4 docs (M2)` (usage program, docs, truth-ups)
- `2c860db7` — `chore(seed): rotate (M2)` (v106 archive + CHANGELOG)
- (this commit) — `docs(sdd): M2 T3 report`
- Concerns: none.

## Fix round 1 — noise lattice pin truth-up

Review finding: `sf/docs/std_lib/noise.md` carried stale seed-0 lattice
decimals from the earlier x87 STOP run instead of the authoritative current
2014 reference / vector output. Docs-only fix; no source/std/compiler/seed
changes.

Commands + observed output:

```
$ gcc -m32 -std=c89 -O0 scripts/stdlib/ref/std_noise/ref.c -o /tmp/m2_t3_fr1_ref
$ /tmp/m2_t3_fr1_ref --lattice
0 0 0000000000000000 0
1 0 3fdb50b0fc7fc810 0.42680000932807705
0 1 bfaf6722e5367f41 -0.061333742599571035
1 1 bfe3e8ac2079b43d -0.62215238898136926

$ sed -n '1,6p' scripts/stdlib/vectors/std_noise/grid.expected
0000000000000000
3fdb50b0fc7fc810
bfaf6722e5367f41
bfe3e8ac2079b43d
3fddda84d5a52c93
bfd30ed03992f1ac
```

The first four `grid.expected` lines match the `--lattice` bits exactly.
Corrected `noise.md` lattice pin:

- `(0,0) == 0` — bits `0000000000000000`
- `(1,0) = 0.42680000932807705` — bits `3fdb50b0fc7fc810`
- `(0,1) = -0.061333742599571035` — bits `bfaf6722e5367f41`
- `(1,1) = -0.62215238898136926` — bits `bfe3e8ac2079b43d`

The "2014 reference authoritative / blueprint §5.5 zero-at-lattice superseded"
meaning is unchanged. Full stdlib gate not required for a docs-only fix and
was not re-run.

Commits:

- `docs(std_lib): M2 noise lattice pin truth-up`
- `docs(sdd): M2 T3 fix round 1`



