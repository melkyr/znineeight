# M7 Task 2 report — closeout docs, truth-ups, seed rotation

Status: DONE

## Commits

- docs: `5419357a` — `docs(std_lib): hpa docs (M7)`
- seed: `96b1fab6` — `chore(seed): rotate (M7)`
- report: this commit — `docs(sdd): M7 T2 report`

## Docs

- Created `sf/docs/std_lib/hpa.md`: concrete `AbstractMap`/`Cluster`/
  `AbstractNode`/`AbstractEdge` fields; clipped row-major clusters; exact
  transition-tile model; directed cross-cluster 10/14 edges plus exact
  cluster-restricted `jpsFind` intra-cluster edges both ways; sorted adjacency
  ranges; temporary `S`/`G` nodes and same-cluster direct edge; refinement and
  duplicate-boundary dropping; `out` capacity/odd-slot/full-count truncation;
  build/query scratch ownership; static-grid rebuild rule; determinism and
  exact-cost guarantee; `O(sum_c k_c^2 * A_c)` build tradeoff; when to prefer
  HPA* over JPS; deferred classic entrance-segment compression.

## Truth-ups

- `STD_README.MD`: L5 row adds HPA* and `std_hpa`; domain table adds the
  HPA* row; doc index adds `hpa.md`.
- `README.md`: higher-layer module list adds `std_hpa`.
- `docs/sf/QUICK_REF.md`: current seed v110 → v111, 39 → 40, archive/manifest
  md5s, std inventory 39 + `std.zig` = 40, install list adds `std_hpa.zig`,
  and a full `std_hpa` (M7) bullet.
- `scripts/seed/archive_seed.sh`: lib copy-list prose adds `std_hpa.zig`; all
  39→40 counts/prose at the lib inventory and SEED_README entry.
- `scripts/seed/build_from_seed.sh`: 39→40 std-lib comment; copy list already
  carried `std_hpa.zig`.
- `scripts/stdlib/expected_dirs.txt`: verified Task 1 already pinned
  `stdlib_hpa_basic_xmod`, `stdlib_hpa_cross_xmod`, and `stdlib_test/hpa_usage`
  (not duplicated).

## Seed v111

- Archive: `release/seed/zig1-seed.tgz`
- Archive md5: `5dc851a1a96c0776ef36e8e5b29774b7`
- Manifest: 40 std files, md5 `788f5642c1fdb13ee532673c5d24ed7e`
- Archived binary md5 / rotation fixed point:
  `21c957730d268f1e7883176fa5413b65` (unchanged from v110)
- `release/seed/CHANGELOG.md` entry: v111, HEAD `b2035261`, 46 `.c` + 47 `.h`
  (10,307,965 bytes)
- Archive check: `lib/std_hpa.zig` present; manifest has 40 entries and its own
  `std_hpa.zig` line; embedded `SEED_README.txt` says 40 std files.

## Full gate

```
bash scripts/stdlib/verify_stdlib.sh /tmp/m7_seed/zig1_5_clean
run_fixtures: 312 PASS / 0 FAIL over 312 dirs
run_crosscheck: 9 PASS / 0 FAIL over 9 modules
STDLIB GATE OK
```

HPA targeted fixtures (3× repeated runs, byte-identical logs):

```
PASS repro/mi_matrix/stdlib_hpa_basic_xmod
PASS repro/mi_matrix/stdlib_hpa_cross_xmod
PASS stdlib_test/hpa_usage
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
```

Import-resolvability: the full gate built both HPA fixtures and the usage
program from `@import("std_hpa.zig")` through the seed compiler's sibling
`lib/`, the same install path the updated seed copy lists populate.

## Concerns

- None.
