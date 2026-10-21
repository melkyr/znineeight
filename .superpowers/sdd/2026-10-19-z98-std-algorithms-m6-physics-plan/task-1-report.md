# M6 Task 1 report — std_physics PBD world

Status: COMPLETE

## Commits

- `453efcc00ce2170df5478073e2ce221cbbd66779` — `feat(std_physics): Position-Based Dynamics (M6)` (source/ref/vectors/fixtures/usage/test-harness/seed-copy-list).
- Report commit — `docs(sdd): M6 T1 report` (this file; plan/spec left uncommitted to the controller).

## Environment facts (verified)

- Branch: `zig1_improvements`; base `36c5ee49` (M5 complete).
- Seed compiler: `/tmp/m5_seed/zig1_5_clean`, md5 `21c957730d268f1e7883176fa5413b65` (matches context).
- Plan/spec already modified in worktree by controller; left uncommitted.
- `run.err` untracked; left alone.

## Step 1 — fixtures authored

Created `repro/mi_matrix/stdlib_physics_{basic,cross,panic}_xmod/` and
`stdlib_test/physics_usage/` (main.zig + goldens), plus the `expected_dirs.txt`
pin entries for all four dirs. Basic covers free-fall, pinned-velocity
convergence, stiffness 1/0.5, 10-particle chain, no-force bit identity, pinned
bit identity, and 8-seed spread. Panic covers over-capacity `pbdAddParticle`
(one process can reach only one trapping precondition).

## Step 2 — pre-implementation failure (module absent)

Command:

```
bash scripts/stdlib/run_fixtures.sh /tmp/m5_seed/zig1_5_clean repro/mi_matrix/stdlib_physics_basic_xmod
```

Observed:

```
FAIL repro/mi_matrix/stdlib_physics_basic_xmod (DUMP-RC2)
    dump stderr:                                           ^^^^
run_fixtures: 0 PASS / 1 FAIL over 1 dirs
RC=1
```

Direct dump confirmed the cause:

```
error[3048]: could not resolve imported file 'std_physics.zig'
error[20]: identifier 'phys' is not declared or imported in this module
RC=2
```

## Step 3 — std_physics.zig implemented

Created `sf/src/std_physics.zig` with §6.8 names/fields/signatures:
`Particle`, `DistanceConstraint`, `PbdWorld` (particles, constraints, order,
particle_count, constraint_count, gravity, damping, iterations, rng),
`pbdInit`, `pbdStep`, `pbdAddParticle`, `pbdAddDistance`, `pbdPin`.

- Arena allocations zeroed with `std_mem.zeroU8`; counts start at 0; defaults
  gravity `{0,0,0}`, damping 0, iterations 4, `xoshiroInit(seed)`.
- Verlet for non-pinned only with `dt*dt`; `prev` = old pos.
- Per-iteration identity-fill + Fisher–Yates shuffle with
  `xoshiroBounded(&rng, i+1)` for `i = constraint_count-1..1`; projection in
  `order` sequence.
- Projection `len = f32(std_math.sqrt(f64(dx*dx+dy*dy+dz*dz)))` with f32
  products/sums mirroring the emitted C, inverse-mass weights, skip
  `len==0`/`wa+wb==0`, no collisions.
- Guard shapes: over-capacity / negative `inv_mass` / `a==b` / invalid live
  index / `pbdPin` out of range -> `@panic`.

Fixtures assign array fields element-wise because the compiler warns (3000) on
whole-array field assignment; scalar element writes are clean. Direct targeted
runs:

```
freefall ok
pinned ok
stiff1 ok
stiff05 ok
chain ok
noforce ok
pin ok
distinct: 8
physics basic ok
```

```
physics_usage
worlds-identical: 1
pin-fixed: 1
distance-ok: 1
physics ok
```

Panic probe: empty stdout, `panic: pbdAddParticle: over capacity`, rc 133.

## Step 4 — crosscheck green

Created `scripts/stdlib/ref/std_physics/ref.c` (C89, libm `sqrt`, f32 stores,
same xoshiro256**/rejection shuffle) and
`scripts/stdlib/vectors/std_physics/basic.{in,expected}`. The vector covers
free fall, pinned distance, 10-particle chain, stiffness 0.5, `len==0`,
`wa+wb==0`, asymmetric multi-constraint shuffle, and damping. `basic.expected`
is the frozen ref/Z98 agreement (exact `cmp`).

Commands / observed:

```
bash scripts/stdlib/run_crosscheck.sh /tmp/m5_seed/zig1_5_clean std_physics
PASS std_physics (1 vectors)
run_crosscheck: 1 PASS / 0 FAIL over 1 modules
RC=0
```

`run_crosscheck.sh` now builds refs with `-lm` (physics needs `sqrt`).

## Step 5 — usage program

`stdlib_test/physics_usage` builds two identical seeded 3-particle chains
(first pinned, gravity, 8 iterations), advances both in lockstep, asserts
bit-identical trajectories, pinned pos/prev unchanged, and both pinned
distances near rest. Captured goldens end `physics ok`.

## Step 6 — gates

Full gate:

```
bash scripts/stdlib/verify_stdlib.sh /tmp/m5_seed/zig1_5_clean
...
run_fixtures: 308 PASS / 0 FAIL over 308 dirs
== std-lib crosscheck gate ==
PASS smoke (3 vectors)
PASS std_lz4 (20 vectors)
PASS std_noise (1 vectors)
PASS std_num (1 vectors)
PASS std_pathfind (2 vectors)
PASS std_physics (1 vectors)
PASS std_rand (2 vectors)
PASS std_zstd (30 vectors)
run_crosscheck: 8 PASS / 0 FAIL over 8 modules
STDLIB GATE OK
RC=0
```

Targeted new fixtures:

```
bash scripts/stdlib/run_fixtures.sh /tmp/m5_seed/zig1_5_clean \
  repro/mi_matrix/stdlib_physics_basic_xmod \
  repro/mi_matrix/stdlib_physics_cross_xmod \
  repro/mi_matrix/stdlib_physics_panic_xmod stdlib_test/physics_usage
PASS repro/mi_matrix/stdlib_physics_basic_xmod
PASS repro/mi_matrix/stdlib_physics_cross_xmod
PASS repro/mi_matrix/stdlib_physics_panic_xmod
PASS stdlib_test/physics_usage
run_fixtures: 4 PASS / 0 FAIL over 4 dirs
RC=0
```

3x determinism (fresh build, same seed):

```
run1/run2/run3 rc=0
cmp12=0 cmp13=0
bb0dbb27876579168cb87c5e765a3bff  run1.out
bb0dbb27876579168cb87c5e765a3bff  run2.out
bb0dbb27876579168cb87c5e765a3bff  run3.out
```

Crosscheck driver 3x on `basic.in`: rc=0 each, `cmp` all equal, md5
`0c139fbda28e0acd51fe6dd79aa16bde`.

Panic rc (direct + harness): empty stdout, rc 133 (`panic: pbdAddParticle:
over capacity`).

Import-resolvability (scratch `/tmp/import_check`, cwd `/tmp`, no repo files):

```
md5sum /tmp/m5_seed/lib/std_physics.zig sf/src/std_physics.zig
b65ba5da3aa0527c2ce4d4c03e2f07a6  /tmp/m5_seed/lib/std_physics.zig
b65ba5da3aa0527c2ce4d4c03e2f07a6  sf/src/std_physics.zig
dump rc=0
build rc=0
import ok
run rc=0
```

Seed copy lists updated: `scripts/seed/build_from_seed.sh` and
`scripts/seed/archive_seed.sh` include `std_physics.zig`.

## Concerns

- One panic fixture can trip only one precondition per process; it exercises
  over-capacity `pbdAddParticle`. `pbdAddDistance` has the same capacity guard
  shape but is not the first trap in that probe.
- Z98 warns (3000) when assigning a whole `[3]f32` field in a fixture
  (`source: array / target: pointer`); fixtures therefore assign elements
  individually. `std_physics.zig` itself is warning-free.
