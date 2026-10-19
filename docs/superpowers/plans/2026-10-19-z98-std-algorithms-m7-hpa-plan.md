# M7 HPA*: std_hpa Hierarchical Pathfinding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land HPA\* (Botea et al. 2004) — cluster partition + abstract-graph search + per-cluster refinement — for maps too large for full JPS.

**Architecture:** `std_hpa.zig` L5 — `hpaBuild` partitions the grid into clusters, finds entrances on cluster borders, precomputes intra-cluster entrance-to-entrance costs (Dijkstra per entrance); `hpaFind` = A\* on the abstract graph + tile-level refinement of each traversed cluster (JPS or Dijkstra within cluster). Arena-owned.

**Tech Stack:** Z98 → C89; gcc C89 ref = full-grid A\* (cost agreement on random maps is the authority).

**Spec:** `docs/superpowers/specs/2026-10-19-z98-std-algorithms-design.md` (§5, §6.9)

## Global Constraints

M1 plan Global Constraints bind verbatim. Extra: same no-corner-cut rule as M5; `hpaFind` cost must equal reference A\* cost (optimality preserved for uniform grids per the paper's refinement); build-time errors only `error.OutOfMemory`.

## Review Focus

1. Entrance identification — every walkable border adjacency must produce an entrance; a missed entrance makes a whole cluster unreachable (NoPath on a solvable map).
2. Abstract-graph cost correctness — precomputed intra-cluster costs must match tile-level reality or refinement breaks; random-map cost-agreement fixture is the canary.
3. Refinement stitching — cluster boundary tiles must connect; off-by-one at borders yields gaps in the output path.
4. Empty/degenerate clusters (fully blocked) — must not create entrances or fake costs.
5. Build determinism — same grid ⇒ same abstract map (R6); iteration order over clusters/entrances fixed.

---

### Task 1: `std_hpa` — build + search

**Files:**
- Create: `sf/src/std_hpa.zig`
- Create: `scripts/stdlib/ref/std_hpa/ref.c` (full-grid A\*, C89)
- Create: `scripts/stdlib/vectors/std_hpa/*.{in,out}`
- Create: `repro/mi_matrix/stdlib_hpa_{basic,cross}_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`, seed copy lists (`build_from_seed.sh:146`, `archive_seed.sh:115`)

**Interfaces:**
- Consumes: `std_pathfind.{Point,Grid,jpsFind}` (M5), `std_heap`, `std_arena`.
- Produces: `std_hpa.{Cluster,AbstractMap,hpaBuild,hpaFind}` — §6.9 signatures verbatim. Terminal milestone; no downstream consumers.

- [ ] **Step 1: Write failing fixtures.** `stdlib_hpa_basic_xmod`: build on 64×64 clustered (8×8) random maps; `hpaFind` cost == `jpsFind` cost on 50 random maps (optimality); entrance coverage (every walkable border pair reachable abstractly); fully-blocked cluster contributes nothing; small-map parity (32×32 grid = same cost as JPS); determinism (same grid ⇒ same abstract map dump).
- [ ] **Step 2: Run — FAIL (module absent).**
- [ ] **Step 3: Implement `std_hpa`** — cluster partition; border scan for entrances (walkable adjacent pair on each cluster edge); per-entrance Dijkstra inside cluster for inter-entrance costs (arena scratch, discarded after build); abstract node/edge tables; `hpaFind` = A\* over abstract graph (composite heap key as M5) + per-traversal-cluster refinement via `jpsFind` restricted to cluster rect; stitched `out` (x,y) pairs.
- [ ] **Step 4: Crosscheck green** — `stdlib_hpa_cross_xmod --crosscheck` vs ref A\* over vector maps (output = cost + tile count).
- [ ] **Step 5: Gates + commit.** Full §4 RUN set; 3× determinism; import-resolvability. `feat(std_hpa): HPA* hierarchical pathfinding (M7)`.

### Task 2: M7 closeout — docs + seed rotation

**Files:**
- Create: `sf/docs/std_lib/hpa.md`; Modify: `release/seed/CHANGELOG.md` (via archive script)

- [ ] **Step 1: Docs** — API, when to prefer HPA\* over JPS (map size vs build cost), optimality guarantee, determinism.
- [ ] **Step 2: Rotate seed** — archive + manifest (40 files); binary md5 + fixed point unchanged.
- [ ] **Step 3: Full gate re-run + commits** (`docs(std_lib): hpa docs (M7)`, `chore(seed): rotate (M7)`). Program complete — deferred list (Swiss, pdqsort, sort extras, zstd dicts, PBD collisions, compressors) stands as recorded in spec §2/§7.
