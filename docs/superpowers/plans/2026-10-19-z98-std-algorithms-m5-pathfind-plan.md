# M5 Pathfinding: std_pathfind JPS — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land Jump Point Search on uniform-cost grids (no corner-cutting), cross-checked against reference A\*.

**Architecture:** `std_pathfind.zig` L5 — caller-supplied `Grid` + `out` slice; open set = existing `std_heap` min-heap with composite key `(f<<32)|(~g)`; jump function iterative (bounded stack); arena for node scratch (width×height).

**Tech Stack:** Z98 → C89; gcc C89 ref = simple A\* with binary heap (different algorithm, same cost — agreement is the authority).

**Spec:** `docs/superpowers/specs/2026-10-19-z98-std-algorithms-design.md` (§5, §6.7)

## Global Constraints

M1 plan Global Constraints bind verbatim. Extra: corner-cutting disallowed (blueprint §4.4 modified pruning); `error.NoPath`/`error.OutOfMemory` only; L5→L4 import of `std_heap` sanctioned (spec §3 DAG rule).

## Review Focus

1. No-corner-cut pruning rules — the standard JPS diagonal rules allow squeezing between blocked tiles; the corner fixture must pin wall-adjacent paths.
2. Jump termination — an off-by-one in the straight-jump scan loops at map edge; the enclosed-goal fixture must return `NoPath`, not hang.
3. Composite heap key tie-break — wrong `(f<<32)|(~g)` packing flips ties toward worse paths; optimality-vs-A\* fixture is the canary.
4. Path reconstruction — parent indices into the node array; a stale parent after reopen yields a path through walls.
5. `out` bounds — `out.len < 2×tiles` must truncate cleanly (defined behavior), never overflow.

---

### Task 1: `std_pathfind` — JPS

**Files:**
- Create: `sf/src/std_pathfind.zig`
- Create: `scripts/stdlib/ref/std_pathfind/ref.c` (A\* + binary heap, C89)
- Create: `scripts/stdlib/vectors/std_pathfind/*.{in,expected}`
- Create: `repro/mi_matrix/stdlib_pathfind_{basic,cross}_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`, seed copy lists (`build_from_seed.sh:146`, `archive_seed.sh:115`)

**Interfaces:**
- Consumes: `std_heap` (`heapInit`/`heapPush`/`heapPop`), `std_arena`.
- Produces: `std_pathfind.{Point,Grid,jpsFind}` — §6.7 signatures verbatim. M7 `std_hpa` consumes `Grid`/`Point`/`jpsFind` semantics.

- [ ] **Step 1: Write failing fixtures.** `stdlib_pathfind_basic_xmod`: straight line 32×32 (0,0)→(31,0) = 32 tiles no diagonals; wall-with-gap routes through gap; enclosed goal → `error.NoPath`; corner pin (wall corner, no diagonal squeeze — path length asserts the no-cut route); out-too-small truncation defined; 50 random 64×64 grids JPS cost == A\* cost.
- [ ] **Step 2: Run — FAIL (module absent).**
- [ ] **Step 3: Implement `jpsFind`** — iterative jump fn (horizontal/vertical/diagonal) with the authors' no-corner-cut pruning; binary heap open set, composite `i64` key `(f<<32)|(~g)`; parent array in arena scratch; path reconstruction backwards into `out` as (x,y) pairs, forward order; tie-break toward goal.
- [ ] **Step 4: Crosscheck green** — `stdlib_pathfind_cross_xmod --crosscheck` vs ref A\* over vector grids (output = path cost + tile count line).
- [ ] **Step 5: Perf note + gates.** Blueprint's "5× faster than A\*" = report-only measurement (no timing gate — harness flakiness); record number in report. Full §4 RUN set; 3× determinism; import-resolvability.
- [ ] **Step 6: Commit.** `feat(std_pathfind): Jump Point Search (M5)`.

### Task 2: M5 closeout — docs + seed rotation

**Files:**
- Create: `sf/docs/std_lib/pathfind.md`; Modify: `release/seed/CHANGELOG.md` (via archive script)

- [ ] **Step 1: Docs** — API, no-corner-cut guarantee, `out` sizing rule, perf measurement.
- [ ] **Step 2: Rotate seed** — archive + manifest (38 files); binary md5 + fixed point unchanged.
- [ ] **Step 3: Full gate re-run + commits** (`docs(std_lib): pathfind docs (M5)`, `chore(seed): rotate (M5)`).
