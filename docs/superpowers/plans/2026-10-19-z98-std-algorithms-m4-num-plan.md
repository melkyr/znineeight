# M4 Numerics: std_num RK45 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the Dormand–Prince adaptive RK45 integrator with fn-ptr callback surface.

**Architecture:** `std_num.zig` L5 — caller-supplied state slices + derivative callback `fn (f64, []const f64, []f64) void`; FSAL 7-stage embedded pair; scaled RMS error norm; no allocation.

**Tech Stack:** Z98 → C89; gcc C89 ref for cross-check.

**Spec:** `docs/superpowers/specs/2026-10-19-z98-std-algorithms-design.md` (§5, §6.6)

## Global Constraints

M1 plan Global Constraints bind verbatim. Extra: error set exactly `error.StepTooSmall`; state vector caller-supplied (never arena); explicit method — stiff systems documented out of scope.

## Review Focus

1. Tableau transcription — a wrong Butenin coefficient passes smooth ODEs and fails stiff-ish ones; the Van der Pol fixture is the canary.
2. RMS error norm vs max-norm — max makes step size oscillate; the step-size monotonicity fixture catches it.
3. FSAL reuse correctness — reusing a stale stage silently changes order; exponential-decay tolerance (1e-6) is tight enough to catch it.
4. dt in/out semantics — `dt` reports the step ACTUALLY taken; a caller stepping twice with the same `dt` integrates wrong.
5. fn-ptr call convention — D8-class shapes were fixed, but a mismatched arity here fails at gcc level; compile both fixtures early.

---

### Task 1: `std_num` — RK45 step

**Files:**
- Create: `sf/src/std_num.zig`
- Create: `scripts/stdlib/ref/std_num/ref.c` (C89 RK45, same tableau)
- Create: `scripts/stdlib/vectors/std_num/*.{in,out}`
- Create: `repro/mi_matrix/stdlib_num_{basic,cross}_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`, seed copy lists (`build_from_seed.sh:146`, `archive_seed.sh:115`)

**Interfaces:**
- Consumes: none.
- Produces: `std_num.{Rk45Config,Rk45State,rk45Step}` — §6.6 signatures verbatim. M6 does NOT consume it (PBD is Verlet); surface frozen for user code.

- [ ] **Step 1: Write failing fixtures.** `stdlib_num_basic_xmod`: exponential `dy/dt=-y`, y(0)=1 → t=1 within 1e-6 of `1/e`; harmonic oscillator 10 periods, energy drift < 1e-4; Van der Pol reference endpoint match; step-size monotonic growth toward `max_step` on a smooth problem; `min_step` hit → `error.StepTooSmall`.
- [ ] **Step 2: Run — FAIL (module absent).**
- [ ] **Step 3: Implement `rk45Step`** — Dormand–Prince 7-stage tableau (transcribe from the 1980 reference, commit the coefficients with citation); FSAL (stage 7 == next stage 1); scaled RMS error `err = sqrt(mean((e_i/(atol+rtol*max(|y_n|,|y_n+1|)))²))`; reject `dt *= 0.9*err^(-1/5)`, accept grow `*1.5` capped at `max_step`; `dt: *f64` in/out.
- [ ] **Step 4: Crosscheck green** — `stdlib_num_cross_xmod --crosscheck` vs ref over vector ODE/step pairs (tolerance-tight outputs byte-printed with fixed precision).
- [ ] **Step 5: Gates + commit.** Full §4 RUN set; 3× determinism; import-resolvability. `feat(std_num): Dormand-Prince RK45 (M4)`.

### Task 2: M4 closeout — docs + seed rotation

**Files:**
- Create: `sf/docs/std_lib/num.md`; Modify: `release/seed/CHANGELOG.md` (via archive script)

- [ ] **Step 1: Docs** — API, tolerance semantics, FSAL note, stiff-system caveat.
- [ ] **Step 2: Rotate seed** — archive + manifest (37 files); binary md5 + fixed point unchanged.
- [ ] **Step 3: Full gate re-run + commits** (`docs(std_lib): num docs (M4)`, `chore(seed): rotate (M4)`).
