# M5 Task 2 report — closeout docs + seed rotation

Status: COMPLETE

Commits: `48412061` `docs(std_lib): pathfind docs (M5)`, `995d130f`
`chore(seed): rotate (M5)`, plus this report commit
`docs(sdd): M5 T2 report`.

Base: `b3fec6ed` on `zig1_improvements`. Compiler:
`/tmp/m5_seed/zig1_5_clean` (md5 `21c957730d268f1e7883176fa5413b65`,
v108; `lib/` has the current 38-file std set).

## Scope

- Create `sf/docs/std_lib/pathfind.md`.
- Truth-up `docs/sf/QUICK_REF.md`, `README.md`, `STD_README.MD`.
- Verify Task 1's 38-file copy lists in `scripts/seed/archive_seed.sh` and
  `scripts/seed/build_from_seed.sh` (do not duplicate).
- Rotate the seed to v109 (38-file manifest; binary md5 and fixed point must
  stay `21c957730d268f1e7883176fa5413b65`).
- Re-run the full std gate and determinism after rotation.

## Seed rotation (verified)

Task 1's copy lists were already correct: `archive_seed.sh:117` and
`build_from_seed.sh:146` include `std_pathfind.zig`, and both scripts already
say 38. No duplicate edit was made.

Fresh self-emission used for the archive:
`/tmp/m5_t2_dump` (50 module+support `.c`, 49 `.h`; module file md5s identical
to `/tmp/m5_seed/gen`). The compiler-independent module C is unchanged because
the fixed point did not move.

```
$ bash scripts/seed/archive_seed.sh /tmp/m5_seed/zig1_5_clean \
    /tmp/m5_t2_dump release/seed/zig1-seed.tgz --update-changelog
[archive] gcc-only rebuild of archive C md5 (fixed point): 21c957730d268f1e7883176fa5413b65
[archive] wrote release/seed/zig1-seed.tgz (archive md5 e4338befc2a95daeca2b103d00da37c3)
```

- Seed: v108 → **v109** (HEAD `b3fec6ed`).
- Archive md5: `f73943f4ce5170e3c776fb985a24cb43` → **`e4338befc2a95daeca2b103d00da37c3`**.
- Manifest: **38 std files**, md5 `e390dff49f843bda62f221ef6184a1de`
  (v108: 37 files, `f98a25b905994f17c72a39d4507c3d7e`).
- Archived binary md5: **`21c957730d268f1e7883176fa5413b65`** (unchanged).
- Self-emission fixed point from the archive C:
  **`21c957730d268f1e7883176fa5413b65`** (unchanged).
- `gen/`: 46 `.c` + 47 `.h`, 10,307,965 bytes (unchanged).
- `release/seed/CHANGELOG.md`: v109 entry prepended.

## Docs

### `sf/docs/std_lib/pathfind.md` (new)

Follows the domain-doc template and sibling L5 docs: module table, overview,
quick start, API entries for `Point`, `Grid`, `JpsPlus`, `jpsFind`,
`jpsPlusBuild`, `jpsPlusFind`, performance, gates, and see-also. Documents:

- cardinal 10 / diagonal 14, heuristic `10*max+4*min`, row-major tiles;
- strict no-corner-cut diagonal legality (Harabor & Grastien, SoCS 2012);
- `out` as capacity: `out.len/2` forward pairs, odd slot ignored, full count
  returned, truncation via `2*return > out.len`;
- `error.NoPath` edge cases and `start == goal` -> 1;
- JPS+ direction order N,NE,E,SE,S,SW,W,NW, signed table semantics
  (positive jump, negative wall, 0 blocked/no move), static-map lifetime,
  32 bytes/cell persistent + N-byte transient bitmap (33 bytes/cell peak),
  and dimension/`dist.len` validation;
- report-only perf: plain JPS 1.84 s vs C89 A* 0.55 s (22% obstacles),
  0.69 s vs 0.01 s (open); JPS+ 6.06 ms vs `jpsFind` 8.87 ms per query
  (22%), 0.127 ms vs 3.37 ms (open); A* still faster. No 5x claim.

The quick-start example was compiled and run against `/tmp/m5_seed` (8x8 open
grid) and printed `88` (both searches return 8 tiles), matching the doc.

### Truth-up list

- `docs/sf/QUICK_REF.md` — current seed v108 → v109, archive md5
  `e4338befc2a95daeca2b103d00da37c3`, 38-file manifest
  `e390dff49f843bda62f221ef6184a1de`, binary/fixed point unchanged; std
  inventory 36+1 → 37+1 (`std_pathfind` added), install recipe adds
  `std_pathfind.zig`, new `std_pathfind` bullet with API/movement/table/out/
  perf; `[updated: 2026-10-21 — M5]` on the seed section.
- `README.md` — higher-layer module list adds `std_pathfind`; Standard Library
  section stamped `[updated: 2026-10-21 — M5]`.
- `STD_README.MD` — L5 row adds `std_pathfind` and pathfinding to its meaning;
  job table adds the grid-pathfinding row; domain index adds `pathfind.md`;
  those three sections stamped `[updated: 2026-10-21 — M5]`.
- `scripts/seed/archive_seed.sh` / `scripts/seed/build_from_seed.sh` — already
  at 38 with `std_pathfind.zig` from Task 1; verified, not edited.

## Archive verification

```
$ tar -xzf release/seed/zig1-seed.tgz -C /tmp/m5_t2_verify
$ md5sum /tmp/m5_t2_verify/zig1-seed/zig1
21c957730d268f1e7883176fa5413b65
$ ls /tmp/m5_t2_verify/zig1-seed/lib/*.zig | wc -l
38
$ md5sum /tmp/m5_t2_verify/zig1-seed/lib/manifest.md5
e390dff49f843bda62f221ef6184a1de
$ grep -c 'std_pathfind.zig' /tmp/m5_t2_verify/zig1-seed/lib/manifest.md5
1
```

## Full gate (post-rotation)

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m5_seed/zig1_5_clean
...
run_fixtures: 304 PASS / 0 FAIL over 304 dirs
== std-lib crosscheck gate ==
PASS smoke (3 vectors)
PASS std_lz4 (20 vectors)
PASS std_noise (1 vectors)
PASS std_num (1 vectors)
PASS std_pathfind (2 vectors)
PASS std_rand (2 vectors)
PASS std_zstd (30 vectors)
run_crosscheck: 7 PASS / 0 FAIL over 7 modules
STDLIB GATE OK
```

## Determinism (3 runs each, byte-identical)

```
plus fixture stdout md5:       c9899195bb97e8b8970e6fd543bb4d8e  (x3)
cross default stdout md5:      833a34d8492494d2071c8b53e7dbed4a  (x3)
cross hand stdout md5:         26232c0940cc384a0b4a88e970a3ac70  (x3)
cross random64 stdout md5:     8e4c21ddbe78cc2dafd99bd49067e224  (x3)
```

`hand` and `random64` match the committed `.expected` md5s; the harness itself
also runs every fixture three times.

## Import resolvability (post-rotation archive)

```
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m5_t2_build
[seed] hop2 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] two-hop closure OK: hop1 == hop2 == 21c957730d268f1e7883176fa5413b65
=== [seed] Done: /tmp/m5_t2_build ===

$ md5sum /tmp/m5_t2_build/lib/std_pathfind.zig sf/src/std_pathfind.zig
9663a35da0794ee2a08f992f3a9dc7cf  /tmp/m5_t2_build/lib/std_pathfind.zig
9663a35da0794ee2a08f992f3a9dc7cf  sf/src/std_pathfind.zig
```

The rebuilt compiler passes the three pathfind fixtures and the
`std_pathfind` crosscheck; the full gate above uses `/tmp/m5_seed`.

## Concerns

- The archive's recorded HEAD is `b3fec6ed` (the implementation base), because
  rotation ran before the docs/seed commits. The compiler source at that HEAD
  is identical to the closeout code state: the only post-base commits are docs
  and the seed itself, and the fixed point stayed
  `21c957730d268f1e7883176fa5413b65`.
- No `sf/src/std_pathfind.zig` change was made in this task.
- The doc states `Grid.tiles.len >= width*height` as a caller precondition;
  the implementation validates dimensions in `jpsPlusFind` but not the tile
  slice length in the search functions.
- `run.err` was left untouched (untracked).

## Fix round 1 — perf table unit

Finding (Important, docs-only): `sf/docs/std_lib/pathfind.md` labeled the
plain-JPS table “per query”, but the `1.84 s` / `0.69 s` values are totals
over 200 queries (Task 1 report: 200 runs; Task 1b: 200 JPS queries =
1773.773 ms = 8.87 ms/query). That overstated per-query latency ~200× and
made the JPS+ table look inconsistent.

Fix: the plain-JPS table now states **200 queries total** in its heading and
both column headers, followed by an explicit sentence separating it from the
JPS+ table, which remains **per query**. Values were not changed.

Evidence:

```
$ sed -n '297,317p' sf/docs/std_lib/pathfind.md
Measurements are report-only (no timing gate). Two 256×256 maps, start
`(0,0)` → goal `(255,255)`, built with `gcc -m32 -std=c89 -O0`; Z98 timings
use `std_time.highRes`, the C89 A* baseline uses `gettimeofday`.

Plain JPS, **200 queries total**, versus a C89 A* reference:

| map | Z98 JPS (200 queries) | C89 A* (200 queries) |
| --- | ---: | ---: |
| 22% obstacles | 1.84 s | 0.55 s |
| fully open | 0.69 s | 0.01 s |

The values above are totals over 200 queries. JPS+ build once, then 200
queries (**per query**):

| map | JPS+ | `jpsFind` |
| --- | ---: | ---: |
| 22% obstacles | 6.06 ms | 8.87 ms |
| fully open | 0.127 ms | 3.37 ms |
```

No source or seed changes, so no seed rotation or tier gate rerun was needed.
The earlier post-rotation full gate (304/304 fixtures, 7/7 crosscheck,
`STDLIB GATE OK`) remains the applicable gate result.

