# M7 HPA*: std_hpa Hierarchical Pathfinding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land HPA\* (Botea et al. 2004) — cluster partition + abstract-graph search + per-cluster refinement — for maps too large for full JPS.

**Architecture:** `std_hpa.zig` L5 — `hpaBuild` partitions the grid into clusters, finds entrances on cluster borders, precomputes intra-cluster entrance-to-entrance costs (Dijkstra per entrance); `hpaFind` = A\* on the abstract graph + tile-level refinement of each traversed cluster (JPS or Dijkstra within cluster). Arena-owned.

**Tech Stack:** Z98 → C89; gcc C89 ref = full-grid A\* (cost agreement on random maps is the authority).

**Spec:** `docs/superpowers/specs/2026-10-19-z98-std-algorithms-design.md` (§5, §6.9)

## Global Constraints

M1 plan Global Constraints bind verbatim. Extra: same no-corner-cut rule as M5; `hpaFind` cost must equal full-grid A*/`jpsFind` cost (exact v1 transition-tile abstraction, not the paper's near-optimal entrance-segment compression); build-time errors only `error.OutOfMemory`; `hpaFind` errors only `NoPath`/`OutOfMemory`; `AbstractMap` fields are public and ordered as §6.9; crosscheck compares cost only; query scratch is caller-reset and must not be the map arena if reset.

## Review Focus

1. Entrance identification — every walkable border adjacency with a legal cross-cluster move must produce a transition node and edge; a missed entrance makes a whole cluster unreachable (NoPath on a solvable map). Diagonal corner crossings must obey strict no-corner-cut.
2. Abstract-graph cost correctness — precomputed intra-cluster costs must match tile-level `jpsFind`; random-map cost-agreement fixture is the canary.
3. Refinement stitching — cluster boundary tiles must connect without duplicates; off-by-one at borders yields gaps in the output path. The stitched path must be legal and have exactly the abstract path's octile cost.
4. Empty/degenerate clusters (fully blocked) — must not create nodes or fake costs; clipped edge clusters and zero-sized maps must behave as §6.9.
5. Build determinism — same grid ⇒ same `AbstractMap` fields (R6); cluster/node/edge order fixed as §6.9.
6. Ownership and truncation — build scratch must be released; `hpaFind` must not corrupt a caller's map arena; `out` must follow M5's odd-slot/prefix/full-count contract.


---

### Task 1: `std_hpa` — build + search

**Files:**
- Create: `sf/src/std_hpa.zig`
- Create: `scripts/stdlib/ref/std_hpa/ref.c` (full-grid A\*, C89)
- Create: `scripts/stdlib/vectors/std_hpa/*.{in,expected}`
- Create: `repro/mi_matrix/stdlib_hpa_{basic,cross}_xmod/{main.zig,expected.txt,expected.rc}`
- Create: `stdlib_test/hpa_usage/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`, seed copy lists (`build_from_seed.sh:146`, `archive_seed.sh:117`)

**Interfaces:**
- Consumes: `std_pathfind.{Point,Grid,jpsFind}` (M5), `std_heap`, `std_arena`.
- Produces: `std_hpa.{Cluster,AbstractNode,AbstractEdge,AbstractMap,hpaBuild,hpaFind}` — §6.9 fields/signatures verbatim. Terminal milestone; no downstream consumers.

- [ ] **Step 1: Write failing fixtures.** `stdlib_hpa_basic_xmod`: 64×64 random maps with 8×8 clusters; compute the octile cost and legality of the returned path and compare cost with `jpsFind` on 50 maps; entrance coverage (every legal cross-cluster adjacency has the expected node/edge and cost 10/14); fully blocked cluster contributes no nodes; 32×32 parity with `jpsFind`; a same-cluster case whose best route leaves and re-enters; a non-divisible grid (31×17, 4×3 clusters); `start==goal`, blocked/out-of-bounds endpoints, and `out` truncation; deterministic serialized `AbstractMap` fields. Path legality checks: walkable tiles, 8-adjacency, strict no-corner-cut, exact endpoints, and octile cost.
- [ ] **Step 2: Run — FAIL (module absent).**
- [ ] **Step 3: Implement `std_hpa`** — clip row-major clusters; mark transition tiles (walkable with a legal cross-cluster 8-neighbour); assign node ids cluster-major then row-major; build cross-cluster edges (cost 10 cardinal / 14 legal diagonal); for each same-cluster node pair compute exact cluster-restricted cost with `jpsFind` on a compact cluster-local `Grid` (copy the rect; map local↔global coordinates) and add directed edges both ways; sort each adjacency range by `to`; fill `node_start`/`edge_start`. Build permanent arrays first, use temporary `tile->node` and local-search scratch, then release scratch before return (arena OOM may consume allocations). `hpaFind`: validate map/grid; handle `start==goal`; add temporary `S`/`G` edges; A\* with §6.9 heuristic/key; refine same-cluster segments via compact `jpsFind`, cross-cluster edges as one step; stitch without duplicate boundary tiles; fill `out` with the M5 truncation contract. Query scratch is caller-reset and must not be the map arena if reset.
- [ ] **Step 4: Crosscheck green** — `stdlib_hpa_cross_xmod --crosscheck` vs ref full-grid A\*. `.in` per grid: `width height cluster_w cluster_h start_x start_y goal_x goal_y`, then `height` rows of `width` bytes `0`/`1`. Output exactly `ok <octile_cost>` or `nopath`; always exit 0. Compare **cost only** (tile count is not invariant; path legality is unit-fixture-only). Ref uses the same movement/no-corner-cut rules and computes cost to the goal.
- [ ] **Step 5: Usage program** — `stdlib_test/hpa_usage` builds a small deterministic map, runs one `hpaFind`, checks the path endpoints/cost and a second identical call, and prints deterministic summary lines ending `hpa ok`; capture expected files.
- [ ] **Step 6: Gates + commit.** Full §4 RUN set; 3× determinism; import-resolvability; `feat(std_hpa): HPA* hierarchical pathfinding (M7)`.


### Task 2: M7 closeout — docs, truth-ups, seed rotation

**Files:**
- Create: `sf/docs/std_lib/hpa.md`; Modify: `release/seed/CHANGELOG.md` (via archive script)
- Modify: `STD_README.MD` (L5 row, domain table, doc-index row)
- Modify: `README.md` (higher-layer module list)
- Modify: `docs/sf/QUICK_REF.md` (current seed v110→v111, 39→40, install list, HPA* bullet)
- Modify: `scripts/seed/archive_seed.sh` (copy list, 39→40 prose at lines 36–37, 117, 166, 176–177, 256, 317)
- Modify: `scripts/seed/build_from_seed.sh` (39→40 comment/list at lines 24, 146)
- Modify: `scripts/stdlib/expected_dirs.txt` (fixtures + usage, if not already added by Task 1)

- [ ] **Step 1: Docs.** `hpa.md`: concrete `AbstractMap` fields, clipped-cluster model, exact transition-tile/edge semantics, `S`/`G` handling, `out`/truncation contract, build/query scratch ownership, static-grid rebuild rule, determinism, exact-cost guarantee, cluster-size tradeoff, and when to prefer HPA* over JPS. Note that classic entrance-segment compression is deferred.
- [ ] **Step 2: Truth-ups.** Add `std_hpa`/`hpa.md` to `STD_README.MD` L5/domain/doc-index rows; add `std_hpa` to the root `README.md` higher-layer list; update `QUICK_REF.md` current seed/count/install list and HPA* bullet; update all 39→40 counts, copy lists, and manifest prose in both seed scripts.
- [ ] **Step 3: Rotate seed.** Archive + manifest (40 files, v111); binary md5 + fixed point must remain `21c957730d268f1e7883176fa5413b65`.
- [ ] **Step 4: Full gate re-run + commits.** `STDLIB GATE OK`, 3× determinism, import-resolvability; commits `docs(std_lib): hpa docs (M7)`, `chore(seed): rotate (M7)`. Program complete — deferred list (Swiss, pdqsort, sort extras, zstd dicts, PBD collisions, compressors) stands as recorded in spec §2/§7.
