# M5 Pathfinding: std_pathfind JPS — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land Jump Point Search on uniform-cost grids (no corner-cutting), cross-checked against reference A\*, plus optional JPS+ preprocessed search for static maps.

**Architecture:** `std_pathfind.zig` L5 — caller-supplied `Grid` + `out` slice; open set = existing `std_heap` min-heap with composite key `(f<<32)|(~g)`; jump function iterative (bounded stack); arena for node scratch (width×height). JPS+ adds an arena-owned `JpsPlus` table of 8 signed distances per cell, built once per static grid and reused across queries.

**Tech Stack:** Z98 → C89; gcc C89 ref = simple A\* with binary heap (different algorithm, same cost — agreement is the authority).

**Spec:** `docs/superpowers/specs/2026-10-19-z98-std-algorithms-design.md` (§5, §6.7)

## Global Constraints

M1 plan Global Constraints bind verbatim. Extra: 8-connected uniform-cell-cost grid; cardinal move cost 10, diagonal 14 (integer octile); heuristic `10*max(dx,dy)+4*min(dx,dy)`; diagonal legal only when both adjacent cardinal cells are walkable (strict no corner cutting, SoCS 2012 pruning); `error.NoPath`/`error.OutOfMemory` only; L5→L4 import of `std_heap` sanctioned (spec §3 DAG rule). JPS+ is optional and static-grid: 8 signed `i32` distances per cell (positive jump point, negative wall, 0 blocked), caller builds once and rebuilds after any grid mutation.

## Review Focus

1. No-corner-cut pruning rules — the standard JPS diagonal rules allow squeezing between blocked tiles; the corner fixture must pin wall-adjacent paths.
2. Jump termination — an off-by-one in the straight-jump scan loops at map edge; the enclosed-goal fixture must return `NoPath`, not hang.
3. Composite heap key tie-break — wrong `(f<<32)|(~g)` packing flips ties toward worse paths; optimality-vs-A\* fixture is the canary.
4. Path reconstruction — parent indices into the node array; a stale parent after reopen yields a path through walls.
5. `out` bounds — `out` is a capacity: write at most `out.len/2` complete pairs, ignore an odd trailing slot, return the FULL tile count, and never overflow; caller detects truncation via `2*return > out.len`.
6. JPS+ distance table — sign and direction order wrong, or a stale map after grid mutation, silently changes paths; the plus fixture compares every handed/random cost against `jpsFind`.
7. JPS+ build cost/memory — 32 bytes per cell (8 × i32); build once must be separated from query timing, and arena exhaustion must surface as `OutOfMemory`.

---

### Task 1: `std_pathfind` — JPS

**Files:**
- Create: `sf/src/std_pathfind.zig`
- Create: `scripts/stdlib/ref/std_pathfind/ref.c` (A\* + binary heap, C89)
- Create: `scripts/stdlib/vectors/std_pathfind/*.{in,expected}`
- Create: `repro/mi_matrix/stdlib_pathfind_{basic,cross}_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`, seed copy-list loops in `scripts/seed/build_from_seed.sh` and `scripts/seed/archive_seed.sh`

**Interfaces:**
- Consumes: `std_heap` (`heapInit`/`heapPush`/`heapPop`), `std_arena`.
- Produces: `std_pathfind.{Point,Grid,jpsFind}` — §6.7 signatures verbatim. M7 `std_hpa` consumes `Grid`/`Point`/`jpsFind` semantics.

- [ ] **Step 1: Write failing fixtures.** `stdlib_pathfind_basic_xmod`: straight line 32×32 (0,0)→(31,0) = 32 tiles no diagonals; wall-with-gap routes through gap; enclosed goal → `error.NoPath`; corner pin (wall corner, no diagonal squeeze — path length asserts the no-cut route); start==goal → 1 tile; out-of-bounds/blocked start or goal → `error.NoPath`; out-too-small writes a `out.len/2` prefix and returns the FULL tile count. The 50 random 64×64 cost checks are crosscheck vectors, not part of the basic fixture.
- [ ] **Step 2: Run — FAIL (module absent).**
- [ ] **Step 3: Implement `jpsFind`** — 8-connected grid (`idx = y*width+x`); cardinal cost 10, diagonal cost 14; heuristic `10*max(dx,dy)+4*min(dx,dy)`; diagonal legal only when both adjacent cardinal cells are walkable; use the no-corner-cut pruning from Harabor & Grastien, *The JPS Pathfinding System* (SoCS 2012), not the 2011 corner-cutting rules. Iterative jump fn; `std_heap` open set with composite key `(i64(f)<<32)|i64((~g)&0xffffffff)`; g/parent/closed arrays in arena scratch; path reconstruction backwards into `out` as forward (x,y) pairs; return the full tile count even when `out` truncates; tie-break toward goal.
- [ ] **Step 4: Crosscheck green** — `stdlib_pathfind_cross_xmod --crosscheck` vs ref A\* over vector grids. `.in`: one line `width height start_x start_y goal_x goal_y`, then `height` rows of `width` bytes `0`/`1`; output exactly `ok <cost>` or `nopath`, always exit 0. Compare cost only (tile count is not invariant across equal-cost paths). The vector corpus includes 50 deterministic 64×64 grids.
- [ ] **Step 5: Perf note + gates.** Blueprint's "5× faster than A\*" = report-only measurement (no timing gate — harness flakiness); record number in report. Full §4 RUN set; 3× determinism; import-resolvability.
- [ ] **Step 6: Commit.** `feat(std_pathfind): Jump Point Search (M5)`.

### Task 1b: `std_pathfind` — JPS+ preprocessed search

**Files:**
- Modify: `sf/src/std_pathfind.zig`
- Create: `repro/mi_matrix/stdlib_pathfind_plus_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Consumes: `std_heap`, `std_arena`, `Grid`, `Point`, `jpsFind` semantics.
- Produces: `JpsPlus{dist: []i32, width: u32, height: u32}`, `jpsPlusBuild(arena, grid) !JpsPlus`, `jpsPlusFind(arena, map, grid, start, goal, out) !u32` — spec §6.7. This is an optional preprocessed path; `jpsFind` stays unchanged for dynamic grids.

- [ ] **Step 1: Write failing fixture.** `stdlib_pathfind_plus_xmod`: build a `JpsPlus` map for each committed `hand`/`random64` grid; `jpsPlusFind` cost equals `jpsFind` cost on every case; build once and query 50 start/goal pairs per map; `start==goal`; invalid/blocked endpoints; out truncation; map/grid dimension mismatch; a tiny-grid check of the signed distance convention (positive jump point, negative wall, 0 blocked).
- [ ] **Step 2: Run — FAIL (JPS+ symbols absent).**
- [ ] **Step 3: Implement.** Add `JpsPlus` and `jpsPlusBuild`/`jpsPlusFind`. `dist` is `width*height*8` signed `i32` values in direction order `N,NE,E,SE,S,SW,W,NW`; positive = next jump point, negative = wall, `0` = blocked. Build with strict no-corner-cut JPS+ preprocessing (Game AI Pro 2 ch. 14 §14.6 / SoCS 2012), arena only, no heap. `jpsPlusFind` uses the same movement, heuristic, `std_heap`, g/parent/closed scratch, path reconstruction and `out` contract as `jpsFind`, but jumps via the table in O(1) per direction. Validate `map.width/height` and `dist.len` against `grid`; mismatch -> `error.NoPath`. Static-grid contract: rebuild the map if `Grid.tiles` changes. Keep `jpsFind` behavior unchanged.
- [ ] **Step 4: Perf note + gates.** Measure build once + 200 queries separately from build time on the 22%/open 256×256 maps; record numbers in the report (no timing gate). Full §4 RUN set; 3× determinism; import-resolvability.
- [ ] **Step 5: Commit code.** `feat(std_pathfind): JPS+ preprocessed search (M5)`.
- [ ] **Step 6: Commit report.** `docs(sdd): M5 T1b report`.

### Task 2: M5 closeout — docs + seed rotation

**Files:**
- Create: `sf/docs/std_lib/pathfind.md`; Modify: `release/seed/CHANGELOG.md` (via archive script)
- Modify: `scripts/seed/archive_seed.sh` (37→38 count text, module comment/list, manifest prose)
- Modify: `scripts/seed/build_from_seed.sh` (37→38 std-lib comment)
- Modify: `docs/sf/QUICK_REF.md` (current std count/install recipe + pathfind bullet)
- Modify: `README.md` (higher-layer module list)
- Modify: `STD_README.MD` (L5 row + doc-index row)

- [ ] **Step 1: Docs** — API (JPS + JPS+), movement model (cardinal 10 / diagonal 14, strict no-corner-cut), JPS+ table/sign/static-grid lifetime and 32N-byte memory, `out` truncation rule, perf measurement.
- [ ] **Step 2: Rotate seed** — archive + manifest (38 files); binary md5 + fixed point unchanged.
- [ ] **Step 3: Full gate re-run + commits** (`docs(std_lib): pathfind docs (M5)`, `chore(seed): rotate (M5)`).
