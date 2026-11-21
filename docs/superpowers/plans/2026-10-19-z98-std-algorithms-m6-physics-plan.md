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
3. Stiffness semantics — stiffness=1 exact-in-one vs fractional convergence; pinned-distance fixture asserts both.
4. Pin semantics — `inv_mass=0` must never move; chain fixture pins the endpoint.
5. Projection order bias — 8-seed asymmetric fixture asserts at least two distinct final positions, catching a dead shuffle.


---

### Task 1: `std_physics` — PBD world

**Files:**
- Create: `sf/src/std_physics.zig`
- Create: `scripts/stdlib/ref/std_physics/ref.c` (C89 PBD, same Verlet/projection, f32 stores; link `-lm` for `sqrt`)
- Create: `scripts/stdlib/vectors/std_physics/*.{in,expected}` (f32 hex-bit protocol)
- Create: `repro/mi_matrix/stdlib_physics_{basic,cross,panic}_xmod/{main.zig,expected.txt,expected.rc}`
- Create: `stdlib_test/physics_usage/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`, seed copy lists (`build_from_seed.sh:146`, `archive_seed.sh:117`), `scripts/stdlib/run_crosscheck.sh` (ref link `-lm`)

**Interfaces:**
- Consumes: `std_rand.Xoshiro256`/`xoshiroInit`/`xoshiroBounded`, `std_arena.Arena`/`alloc`, `std_math.sqrt(f64)`, `std_mem.zeroU8`.
- Produces: `std_physics.{Particle,DistanceConstraint,PbdWorld,pbdInit,pbdStep,pbdAddParticle,pbdAddDistance,pbdPin}` — §6.8 fields/signatures verbatim.

- [ ] **Step 1: Write failing fixtures.** `stdlib_physics_basic_xmod`: free-fall 600 steps dt=1/60 within 1% of continuous analytic `0.5*g*T²`; pinned distance constraint with initial velocity converges to rest length; stiffness=1 restores rest in one projection and stiffness=0.5 moves halfway; 10-particle chain (first pinned, rest spacing 1, gravity `{0,-9.81,0}`, dt=1/60, iterations 8, stiffness 1) hangs with max adjacent stretch <5%; no-force particle bit-identical over 1000 steps; pinned particle bit-identical under gravity/constraints; 8-seed asymmetric scenario produces at least two distinct final position vectors. Add `stdlib_physics_panic_xmod` for over-capacity `pbdAddParticle`/`pbdAddDistance`: empty stdout, `expected.rc=133`.
- [ ] **Step 2: Run — FAIL (module absent).**
- [ ] **Step 3: Implement `std_physics.zig`** — Verlet `new = pos + (pos-prev)*(1-damping) + g*dt²` for non-pinned particles only; store `prev=old pos`; distance projection uses f64 `std_math.sqrt` then f32 cast, inverse-mass weighting `wa/(wa+wb)` / `wb/(wa+wb)`, skips `len==0`/`wa+wb==0`; per-iteration Fisher–Yates shuffle of `order[]` with `xoshiroBounded(i+1)`, projected in `order` sequence. Initialize counts/defaults as §6.8.
- [ ] **Step 4: Crosscheck green** — `stdlib_physics_cross_xmod --crosscheck` vs ref. `.in` is line-oriented: seed, gravity, damping, iterations, steps, dt, particle list (`x y z inv_mass` as 8-hex f32 bits), constraint list (`a b stiffness`); output is one line per particle of `x y z` as 8-hex f32 bits. Ref mirrors the same PRNG/shuffle/f32 store protocol; `run_crosscheck.sh` uses exact `cmp`.
- [ ] **Step 5: Usage program** — `stdlib_test/physics_usage` builds two identical seeded worlds, asserts pin stays fixed, runs a pinned constraint, and prints deterministic summary lines ending `physics ok`; capture expected files.
- [ ] **Step 6: Gates + commit.** Full §4 RUN set; 3× determinism (same seed ⇒ byte-identical trajectory); import-resolvability. `feat(std_physics): Position-Based Dynamics (M6)`.


### Task 2: M6 closeout — docs, truth-ups, seed rotation

**Files:**
- Create: `sf/docs/std_lib/physics.md`; Modify: `release/seed/CHANGELOG.md` (via archive script)
- Modify: `STD_README.MD` (L5 row, domain table, doc index), `README.md` (higher-layer list), `docs/sf/QUICK_REF.md` (seed v109→v110, 38→39, install list, physics bullet)
- Modify: `scripts/seed/archive_seed.sh` (copy list + 38→39 prose at lines 36-37, 117, 166, 176-177, 256, 317), `scripts/seed/build_from_seed.sh:24,146`

- [ ] **Step 1: Docs** — API, Verlet contract, f64-sqrt/f32-cast length rule, stiffness/iterations guidance (cloth: 1 + 4–8 iters; soft: lower + more), no-collision v1 note, determinism note, panic preconditions, and `stdlib_test/physics_usage`.
- [ ] **Step 2: Truth-ups.** Add `std_physics`/`physics.md` to `STD_README.MD` L5 row, domain table, and doc index; add `std_physics` to the root `README.md` higher-layer list; update `QUICK_REF.md` current seed/count/install list and physics bullet; update `archive_seed.sh`/`build_from_seed.sh` copy lists and all 38→39 prose.
- [ ] **Step 3: Rotate seed** — archive + manifest (39 files, v110); binary md5 + fixed point unchanged (`21c957730d268f1e7883176fa5413b65`).
- [ ] **Step 4: Full gate re-run + commits** (`docs(std_lib): physics docs (M6)`, `chore(seed): rotate (M6)`).
