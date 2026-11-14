# M5 Task 1b report — `std_pathfind` JPS+ preprocessed search

Status: COMPLETE (implementation, plus fixture, full gate, determinism,
import-resolvability, and perf measurements green). Code commit:
`e0f329fe` `feat(std_pathfind): JPS+ preprocessed search (M5)`; this report
commit: `docs(sdd): M5 T1b report`.

Base: `21e5efa4` on `zig1_improvements`. Compiler:
`/tmp/m5_seed/zig1_5_clean` (md5 `21c957730d268f1e7883176fa5413b65`,
v108).

## Files

- `sf/src/std_pathfind.zig` — added `JpsPlus`, `jpsPlusBuild`,
  `jpsPlusFind` alongside the unchanged `jpsFind`.
- `repro/mi_matrix/stdlib_pathfind_plus_xmod/{main.zig,vectors_data.zig,
  expected.txt,expected.rc}` — new plus fixture (61 embedded grids:
  11 `hand.in` + 50 `random64.in`).
- `scripts/stdlib/expected_dirs.txt` — pinned the new fixture (304 total).

## Preprocessing design

`dist[cell*8+dir]` is `width*height*8` signed `i32` in direction order
`N,NE,E,SE,S,SW,W,NW`. `jpsPlusBuild` is arena-only (no heap):

1. Mark cardinal jump points with `gridForced`, a grid-only copy of the
   existing `hasForced` logic. This is the strict no-corner-cut JPS forced
   neighbour rule (perpendicular cell walkable and the diagonal behind it
   blocked). Diagonal moves have no forced neighbours; no separate diagonal
   jump-point bit is marked.
2. Cardinal scans run along each row/column from the wall side, carrying
   `count` and `jumpPointLastSeen` (the `PrecomputeMap.cpp` recipe): reset at
   walls, positive distance after a jump point, otherwise negative distance.
   An immediate wall/edge/blocked direction is `0`, which the runtime treats
   as "no move".
3. Diagonal scans run in `NW,NE,SW,SE` direction order. A diagonal cell is `0`
   when the next diagonal cell or either adjacent cardinal cell is a wall.
   Otherwise it is `1` when the next diagonal cell has a positive cardinal
   distance in either component (that cell is a diagonal jump point), else it
   increments/decrements the next cell's diagonal distance. This propagates
   positives to the first diagonal jump point and negatives toward the wall.
4. The final map is exactly 32 bytes/cell. The build transiently uses one
   extra `n`-byte jump-point bitmap from the same arena.

`jpsPlusFind` validates map width/height and `dist.len == n*8` against the
grid (mismatch -> `error.NoPath`) and otherwise reuses the `jpsFind` contract:
same 8-connected movement, octile heuristic, `std_heap` composite key,
g/parent/closed scratch, path/`out` semantics, and errors. Each direction is
O(1):

- Cardinal: a positive distance jumps to the next static jump point; a
  non-positive distance gives the maximum freely walkable distance. A goal on
  that ray before the endpoint is returned first, mirroring `jumpCardinal`.
- Diagonal: the earliest of the static diagonal jump distance and the goal
  projection (the diagonal cell aligned with the goal row/column). The
  projection is accepted only when cardinal line-of-sight to the goal (or a
  cardinal jump) exists, mirroring the goal-aware cardinal probes in `jump`.
  The runtime then continues with the same `expand` forced-neighbour rules as
  `jpsFind`.

The map is static: callers must rebuild after any `Grid.tiles` mutation. No
cache is hidden in the module.

## Fixture

`stdlib_pathfind_plus_xmod` embeds the committed `hand.in` and `random64.in`
grids as a packed one-bit-per-tile blob (the harness runs fixtures from a
scratch CWD, so no vector-file I/O is possible). For every grid it builds one
`JpsPlus` and reuses it for:

- the vector start/goal case (cost equality with `jpsFind`, including
  `nopath`);
- 50 deterministic LCG-derived start/goal pairs (endpoints selected by a
  deterministic walkable scan);
- a `start==goal` case.

Additional checks: OOB/blocked start and goal, zero-sized grid, width/height
and `dist.len` mismatch -> `NoPath`, 11-slot out truncation (5 full pairs, odd
slot untouched, full count 32), and a 5x5 tiny-grid sign check:
`dist[(3,1)][W] == +1` (positive jump point), `dist[(2,0)][E] == -1`
(negative wall), and every direction of blocked cell `(3,2) == 0`.

The fixture data file is frozen from the two committed vector files; it was
regenerated from them (grid count 61, 208464 tile bits, 26058 packed bytes),
not transcribed by hand.

## Targeted evidence

Step 2 RED on the pre-task module (base `21e5efa4` has `jpsFind` only):

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m5_oldseed/zig1_5_clean \
    repro/mi_matrix/stdlib_pathfind_plus_xmod
FAIL repro/mi_matrix/stdlib_pathfind_plus_xmod (DUMP-RC2)
...
repro/mi_matrix/stdlib_pathfind_plus_xmod/main.zig:76:46: error[20]:
  identifier 'JpsPlus' is not declared or imported in this module
```

GREEN with the new module:

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m5_seed/zig1_5_clean \
    repro/mi_matrix/stdlib_pathfind_basic_xmod \
    repro/mi_matrix/stdlib_pathfind_cross_xmod \
    repro/mi_matrix/stdlib_pathfind_plus_xmod
PASS repro/mi_matrix/stdlib_pathfind_basic_xmod
PASS repro/mi_matrix/stdlib_pathfind_cross_xmod
PASS repro/mi_matrix/stdlib_pathfind_plus_xmod
----------------------------------------
run_fixtures: 3 PASS / 0 FAIL over 3 dirs

$ bash scripts/stdlib/run_crosscheck.sh /tmp/m5_seed/zig1_5_clean std_pathfind
PASS std_pathfind (2 vectors)
----------------------------------------
run_crosscheck: 1 PASS / 0 FAIL over 1 modules
```

Determinism (fixture binary run three times):

```
$ for i in 1 2 3; do /tmp/plus_det/prog | md5sum; done
c9899195bb97e8b8970e6fd543bb4d8e  -
c9899195bb97e8b8970e6fd543bb4d8e  -
c9899195bb97e8b8970e6fd543bb4d8e  -
```

The harness itself also runs every fixture three times and compares stdout.

## Full gate

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
----------------------------------------
run_crosscheck: 7 PASS / 0 FAIL over 7 modules
STDLIB GATE OK
```

Baseline was 303/303 + 7/7; this task adds the plus fixture, hence 304/304.

## Import resolvability

Rebuilt from the committed seed archive (copy list already contains
`std_pathfind.zig`):

```
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz \
    /tmp/m5_t1b_build
[seed] hop2 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] two-hop closure OK: hop1 == hop2 == 21c957730d268f1e7883176fa5413b65
=== [seed] Done: /tmp/m5_t1b_build ===

$ md5sum /tmp/m5_t1b_build/lib/std_pathfind.zig sf/src/std_pathfind.zig
9663a35da0794ee2a08f992f3a9dc7cf  /tmp/m5_t1b_build/lib/std_pathfind.zig
9663a35da0794ee2a08f992f3a9dc7cf  sf/src/std_pathfind.zig
```

Both pathfind fixtures and the crosscheck resolve and pass with that built
compiler:

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m5_t1b_build/zig1_5_clean \
    repro/mi_matrix/stdlib_pathfind_basic_xmod \
    repro/mi_matrix/stdlib_pathfind_cross_xmod \
    repro/mi_matrix/stdlib_pathfind_plus_xmod
PASS ...basic...
PASS ...cross...
PASS ...plus...
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
$ bash scripts/stdlib/run_crosscheck.sh /tmp/m5_t1b_build/zig1_5_clean std_pathfind
PASS std_pathfind (2 vectors)
```

## Perf (report only; no timing gate)

Two 256x256 maps, start `(0,0)` -> goal `(255,255)`, one build followed by
200 queries; same LCG map generation (`seed 12345`, corners opened 3x3).
Z98 timings use `std_time.highRes`; the C89 A* baseline uses `gettimeofday`.
All programs built with `gcc -m32 -std=c89 -O0`.

| map | build once | 200 plus queries | 200 `jpsFind` queries | 200 C89 A* queries | cost |
| --- | ---: | ---: | ---: | ---: | ---: |
| fully open | 19.311 ms | 25.449 ms | 674.910 ms | 12.929 ms | 3570 |
| 22% obstacles | 17.446 ms | 1211.876 ms | 1773.773 ms | 532.117 ms | 4104 |

Per query: plus `0.127 ms` open / `6.06 ms` 22%; `jpsFind` `3.37 ms` /
`8.87 ms`; A* `0.065 ms` / `2.66 ms`. Plus is ~26x faster than `jpsFind` on
the open map and ~1.46x on the 22% map. A* remains faster than plus in this
O0 microbenchmark on both maps; this is reported, not gated.

## Concerns

- `PrecomputeMap.cpp`'s count starts at `-1`, so the direction immediately at
  an edge or wall is `0` (the same encoding as a blocked cell); runtime treats
  every non-positive entry as "no jump". The tiny fixture pins a true blocked
  cell (`0`), a negative wall distance (`-1`), and a positive jump (`+1`).
- The plus runtime keeps the goal-aware behaviour of `jump` by checking goal
  rays/projections on top of the static table; without that, a goal that is
  cardinally aligned from a mid-diagonal cell but not itself a static jump
  point would be missed.
- The embedded `vectors_data.zig` is a generated fixture artifact (one bit per
  tile). It must be regenerated if the committed pathfind vector corpus
  changes; the generator is not committed.
- `jpsPlusBuild` transiently allocates the `n`-byte jump-point bitmap in
  addition to the 32 bytes/cell table; the bitmap is arena memory and never
  freed individually.
- Perf numbers are a single run of a `-O0` microbenchmark and are noisy; they
  are informational only.
