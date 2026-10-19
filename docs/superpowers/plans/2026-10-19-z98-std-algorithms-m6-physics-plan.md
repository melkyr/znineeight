# M6 Physics: std_physics PBD — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land Position-Based Dynamics (Verlet + distance-constraint projection) for cloth/soft-body/rope.

**Architecture:** `std_physics.zig` L5 — arena-sized `PbdWorld`; `pbdStep` = Verlet integrate then iterative constraint projection with per-iteration constraint shuffle (`rng: std_rand.Xoshiro256`); no collision constraints in v1.

**Tech Stack:** Z98 → C89; gcc C89 ref for cross-check (independent PBD implementation).

**Spec:** `docs/superpowers/specs/2026-10-19-z98-std-algorithms-design.md` (§5, §6.8)

## Global Constraints

M1 plan Global Constraints bind verbatim. Extra: `pbdAddParticle`/`pbdAddDistance` over init counts → `@panic` (precondition); dt² scaling exact; determinism under fixed `seed` (constraint shuffle is seeded).

## Review Focus

1. Verlet `dt²` scaling — gravity off by orders of magnitude is the classic PBD transcription error; free-fall 1% fixture catches it.
2. Constraint shuffle determinism — same seed ⇒ same trajectory (3× gate); an unseeded shuffle breaks R6.
3. Stiffness semantics — stiffness=1 exact-in-one vs fractional convergence; spring fixture asserts both.
4. Pin semantics — `inv_mass=0` must never move; chain fixture pins the endpoint.
5. Projection order bias — shuffling exists to kill it; a fixture asserting uniform final positions over seeds catches a dead shuffle.

---

### Task 1: `std_physics` — PBD world

**Files:**
- Create: `sf/src/std_physics.zig`
- Create: `scripts/stdlib/ref/std_physics/ref.c` (C89 PBD, same Verlet/projection)
- Create: `scripts/stdlib/vectors/std_physics/*.{in,expected}`
- Create: `repro/mi_matrix/stdlib_physics_{basic,cross}_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`, seed copy lists (`build_from_seed.sh:146`, `archive_seed.sh:115`)

**Interfaces:**
- Consumes: `std_rand.Xoshiro256`/`xoshiroInit`/`xoshiroBounded` (M1 names).
- Produces: `std_physics.{Particle,DistanceConstraint,PbdWorld,pbdInit,pbdStep,pbdAddParticle,pbdAddDistance,pbdPin}` — §6.8 signatures verbatim.

- [ ] **Step 1: Write failing fixtures.** `stdlib_physics_basic_xmod`: free-fall 60 steps dt=1/60 within 1% of analytic; pinned-spring oscillation converges to rest length; 10-particle chain hangs, stretch < 5%; no-force particle position-constant over 1000 steps (fp tolerance); pin never moves; over-count add → `@panic` (fixture asserts trap rc).
- [ ] **Step 2: Run — FAIL (module absent).**
- [ ] **Step 3: Implement `std_physics.zig`** — Verlet `new = pos + (pos-prev)*(1-damping) + g*dt²`; distance projection `Δ = (len-rest)/len * 0.5*stiffness` per iteration on both endpoints (respecting `inv_mass`); per-iteration constraint-order shuffle via `rng` (Fisher–Yates over a scratch index array in the world arena).
- [ ] **Step 4: Crosscheck green** — `stdlib_physics_cross_xmod --crosscheck` vs ref over vector scenarios (fixed seed; output = final positions at fixed precision).
- [ ] **Step 5: Gates + commit.** Full §4 RUN set; 3× determinism (same seed ⇒ byte-identical trajectory); import-resolvability. `feat(std_physics): Position-Based Dynamics (M6)`.

### Task 2: M6 closeout — docs + seed rotation

**Files:**
- Create: `sf/docs/std_lib/physics.md`; Modify: `release/seed/CHANGELOG.md` (via archive script)

- [ ] **Step 1: Docs** — API, Verlet contract, stiffness/iterations guidance (cloth: 1 + 4–8 iters; soft: lower + more), no-collision v1 note, determinism note.
- [ ] **Step 2: Rotate seed** — archive + manifest (39 files); binary md5 + fixed point unchanged.
- [ ] **Step 3: Full gate re-run + commits** (`docs(std_lib): physics docs (M6)`, `chore(seed): rotate (M6)`).
