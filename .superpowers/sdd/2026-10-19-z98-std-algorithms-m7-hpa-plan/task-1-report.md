# M7 Task 1 report — `std_hpa`

Status: DONE

## Commits

- code: `e89acce2` — `feat(std_hpa): HPA* hierarchical pathfinding (M7)`
- report: recorded below after commit.

## Implementation

- `sf/src/std_hpa.zig`: §6.9 exact transition-tile abstraction. Clipped
  row-major clusters, cluster-major/row-major node ids, directed cross-cluster
  edges cost 10/14, exact cluster-restricted `jpsFind` intra-cluster costs in
  both directions, each adjacency range sorted by `to`.
- `hpaBuild` uses a counting/scatter pass, restores the build arena's used
  bytes before returning, and leaves only map arrays allocated.
- `hpaFind` validates map/grid, adds temporary `S`/`G` edges, runs A* with the
  octile heuristic and `(f<<32)|(~g)` key, refines with cluster-local
  `jpsFind`, drops duplicate boundary tiles, and follows the M5 `out`
  prefix/odd-slot/full-count truncation contract.
- Added the C89 full-grid A* reference, 8 crosscheck vectors, basic/cross
  fixtures, and the usage program; updated `expected_dirs.txt` and both seed
  copy lists (`build_from_seed.sh`, `archive_seed.sh`).

## Tests

Verified with the seed-built compiler (`/tmp/m7_seed/zig1_5_clean`, std_hpa
copied to its sibling `lib/`):

```
bash scripts/stdlib/run_fixtures.sh /tmp/m7_seed/zig1_5_clean \
  repro/mi_matrix/stdlib_hpa_basic_xmod \
  repro/mi_matrix/stdlib_hpa_cross_xmod stdlib_test/hpa_usage
PASS repro/mi_matrix/stdlib_hpa_basic_xmod
PASS repro/mi_matrix/stdlib_hpa_cross_xmod
PASS stdlib_test/hpa_usage
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
```

`stdlib_hpa_basic_xmod` checks 50 random 64x64 maps (8x8 clusters) against
`jpsFind` cost/NoPath with full path legality, entrance coverage (node/edge
cost 10/14 both ways), a fully blocked cluster, 32x32 parity, a same-cluster
route that leaves and re-enters, a 31x17/4x3 clipped grid, `start==goal`,
blocked/OOB/mismatched/zero-grid endpoints, `out` truncation, and deterministic
serialized `AbstractMap` fields.

`stdlib_test/hpa_usage` builds the map once, finds a path, checks endpoints and
cost against `jpsFind`, repeats the identical query, and prints:

```
hpa_usage
clusters: 6
nodes: 102
edges: 1766
cost: 132
repeat: 1
hpa ok
```

Determinism: `run_fixtures.sh` ran every fixture 3×; all stdout was
byte-identical, including the randomized `stdlib_hpa_basic_xmod` and
`stdlib_hpa_cross_xmod` programs.

## Crosscheck / vectors

```
bash scripts/stdlib/run_crosscheck.sh /tmp/m7_seed/zig1_5_clean std_hpa
PASS std_hpa (8 vectors)
run_crosscheck: 1 PASS / 0 FAIL over 1 modules
```

Vectors: `open8`, `nocut8`, `gap16`, `nondiv13x10`, `reenter24x16`,
`nopath8`, `same8`, `blocked8`. Each matched the C89 full-grid A* reference
(`gcc -m32 -std=c89 -O0`) and the committed `.expected` byte-for-byte:

```
open8          ok 98
nocut8         ok 20
gap16          ok 228
nondiv13x10    ok 156
reenter24x16   ok 58
nopath8        nopath
same8          ok 0
blocked8       nopath
```

## §4 gate

```
bash scripts/stdlib/verify_stdlib.sh /tmp/m7_seed/zig1_5_clean
...
PASS repro/mi_matrix/stdlib_hpa_basic_xmod
PASS repro/mi_matrix/stdlib_hpa_cross_xmod
...
PASS stdlib_test/hpa_usage
...
run_fixtures: 312 PASS / 0 FAIL over 312 dirs
== std-lib crosscheck gate ==
PASS smoke (3 vectors)
PASS std_hpa (8 vectors)
PASS std_lz4 (20 vectors)
PASS std_noise (1 vectors)
PASS std_num (1 vectors)
PASS std_pathfind (2 vectors)
PASS std_physics (1 vectors)
PASS std_rand (2 vectors)
PASS std_zstd (30 vectors)
----------------------------------------
run_crosscheck: 9 PASS / 0 FAIL over 9 modules
STDLIB GATE OK
```

Import-resolvability: the gate built both HPA fixtures and the usage program
from `@import("std_hpa.zig")` via the seed compiler's sibling `lib/`, proving
the module resolves at the same path the updated seed copy lists install.

Affected-example tiers: none (std-only program, §4 item 5). Seed rotation is
Task 2 closeout, not this task.

## Concerns

None. Build performs one exact-cost counting pass plus one scatter pass, using
only arena scratch that is released before return.

## Fix round 1 (review findings)

Status: DONE

Coverage added to `repro/mi_matrix/stdlib_hpa_basic_xmod/main.zig`:

- `edge-order ok`: every `edges[edge_start[n]..edge_start[n+1]]` range is
  strictly ascending by `to`.
- `node-order ok`: each cluster's node range is row-major by `(y,x)` and every
  node carries that cluster id.
- `scratch ok`: `arena.used` before/after `hpaBuild` equals the exact
  permanent allocation sum (with a non-zero pre-build base).
- `special ok`: blocked and OOB same-tile start/goal both return `NoPath`
  (shortcut ordering covered).
- `special ok`: map copies altered in `width`, `height`, `cluster_w`,
  `cluster_h`, `cluster_cols`, `cluster_rows`, `clusters.len`,
  `node_start.len`, and `edge_start.len` all return `NoPath`.
- `intra ok`: on a 16x16/8x8 clustered map, every same-cluster transition-node
  pair has both directed edges with the exact cluster-local `jpsFind` cost
  (and no edge when unreachable).

Targeted verification:

```
bash scripts/stdlib/run_fixtures.sh /tmp/m7_seed/zig1_5_clean \
  repro/mi_matrix/stdlib_hpa_basic_xmod \
  repro/mi_matrix/stdlib_hpa_cross_xmod stdlib_test/hpa_usage
PASS repro/mi_matrix/stdlib_hpa_basic_xmod
PASS repro/mi_matrix/stdlib_hpa_cross_xmod
PASS stdlib_test/hpa_usage
run_fixtures: 3 PASS / 0 FAIL over 3 dirs

bash scripts/stdlib/run_crosscheck.sh /tmp/m7_seed/zig1_5_clean std_hpa
PASS std_hpa (8 vectors)
run_crosscheck: 1 PASS / 0 FAIL over 1 modules
```

Mutation checks (each on a `/tmp` copy of `std_hpa`; seed lib restored after):

```
1 sortNodeEdges disabled -> rc 133, panic: edge order
2 node ids reversed within cluster -> rc 133, panic: node row-major order
3 `arena.used = perm_end` removed -> rc 133, panic: build scratch released
4 OOB/walkable endpoint validation removed before start==goal shortcut
  -> rc 133, panic: blocked same-tile path
```

Full gate:

```
bash scripts/stdlib/verify_stdlib.sh /tmp/m7_seed/zig1_5_clean
PASS repro/mi_matrix/stdlib_hpa_basic_xmod
PASS repro/mi_matrix/stdlib_hpa_cross_xmod
run_fixtures: 312 PASS / 0 FAIL over 312 dirs
run_crosscheck: 9 PASS / 0 FAIL over 9 modules
STDLIB GATE OK
```

Complexity truth-up (non-blocking): `hpaBuild` computes every reachable
same-cluster transition-node pair with a cluster-local `jpsFind`, so its worst
case is `O(sum_c k_c^2 * A_c)`, not the spec's stated
`O(sum_c k_c*(A_c+k_c))`. Implementation unchanged; controller to correct the
spec text.

No behavior change was required; the fix commit is coverage only.
