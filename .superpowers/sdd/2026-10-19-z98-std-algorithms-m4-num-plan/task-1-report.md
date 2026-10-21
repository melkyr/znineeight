# M4 Task 1 report — std_num Dormand-Prince RK45

Status: COMPLETE

Base: `33c43c9a` (branch `zig1_improvements`)

Commits:
- `0231ddc9` feat(std_num): Dormand-Prince RK45 (M4)
- (this report commit follows)

## Files

- `sf/src/std_num.zig` — `Rk45Config`, `Rk45State`, `rk45Step` (spec §6.6 verbatim).
- `scripts/stdlib/ref/std_num/ref.c` — C89 reference, same tableau/operation order.
- `scripts/stdlib/vectors/std_num/basic.{in,expected}` — 10 crosscheck lines.
- `repro/mi_matrix/stdlib_num_basic_xmod/{main.zig,expected.txt,expected.rc}`.
- `repro/mi_matrix/stdlib_num_cross_xmod/{main.zig,expected.txt,expected.rc}`.
- `scripts/stdlib/expected_dirs.txt` — both new fixture dirs pinned (C-sorted).
- `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` — copy lists gain `std_num.zig` (count text untouched).

## Tableau

Dormand & Prince, "A family of embedded Runge-Kutta formulae", J. Comput.
Appl. Math. 6(1), 1980, pp. 19-26 (MATLAB ode45 pair). Coefficients are
transcribed as exact IEEE-754 bit patterns because the Z98 decimal-float
literal path is not correctly rounded:

```
c2=1/5
a21=1/5
c3=3/10   a31=3/40   a32=9/40
c4=4/5    a41=44/45  a42=-56/15 a43=32/9
c5=8/9    a51=19372/6561 a52=-25360/2187 a53=64448/6561 a54=-212/729
c6=1      a61=9017/3168 a62=-355/33 a63=46732/5247 a64=49/176
          a65=-5103/18656
c7=1      a71=35/384 a73=500/1113 a74=125/192 a75=-2187/6784 a76=11/84
b5 = a7 (FSAL)
b4 = 5179/57600, 0, 7571/16695, 393/640, -92097/339200, 187/2100, 1/40
e  = b5 - b4
```

FSAL: `state.dy` is `f(t,y)` on entry and `k7=f(t_new,y_new)` on return.
Scaled RMS norm `sqrt(mean((e_i/(atol+rtol*max(|y_n|,|y_{n+1}|)))²))`;
reject `dt *= 0.9*err^(-1/5)`; accept grow `1.5x` capped at `max_step`.

## Evidence so far

- Step 2 (pre-implementation): targeted basic fixture failed `DUMP-RC2` (module absent).
- Ref build: `gcc -m32 -std=c89 -O0 ... ref.c` rc 0.
- Targeted fixtures:
  `bash scripts/stdlib/run_fixtures.sh <zig1> <both num dirs>` -> `2 PASS / 0 FAIL`.
- Crosscheck:
  `bash scripts/stdlib/run_crosscheck.sh <zig1> std_num` ->
  `PASS std_num (1 vectors)` / `1 PASS / 0 FAIL`.
- Three-way bit-exact evidence: `cmp` of Z98 driver stdout, ref stdout, and
  committed `basic.expected` is clean (10 lines; 9 trajectories + one `small`).

## Gates

Commands run from repo root with `<zig1> = /tmp/m4_t1_build/zig1_5_clean`
(seed-built from `release/seed/zig1-seed.tgz` after editing).

1. Full fixture set:
   `bash scripts/stdlib/verify_stdlib.sh <zig1>`
   Observed: `run_fixtures: 301 PASS / 0 FAIL over 301 dirs`,
   `run_crosscheck: 6 PASS / 0 FAIL over 6 modules`, `STDLIB GATE OK`,
   exit 0.
2. Targeted crosscheck: `bash scripts/stdlib/run_crosscheck.sh <zig1> std_num`
   -> `PASS std_num (1 vectors)` / `1 PASS / 0 FAIL`.
3. Determinism 3x: basic fixture md5
   `cccc34673db4e6a35d1bae0678588e62` for all 3 runs; crosscheck driver md5
   `8eb6154703beff0c03b0f306d4ac344e` for all 3 runs; both `cmp` clean.
4. Import-resolvability: produced compiler's sibling `lib/` contains
   `std_num.zig`; both fixtures resolve `@import("std_num.zig")` and build.

## Concerns

- `dt` conflict: the context says `dt` returns "the step actually taken", but
  the same contract also requires an accepted step to grow `dt` by 1.5x for
  the next call, and the step-growth fixture requires the returned value to
  grow toward `max_step`. Implemented as the standard in/out adaptive size
  (next step recommendation); `state.t` advances by the actual accepted step.
- No-allocation API + C89 means stage scratch needs a fixed bound
  (`RK45_MAX_DIM = 64`); larger vectors are a caller precondition (`@panic`).
  The spec does not state a dimension limit.
- Crosscheck prints exact f64 bit patterns (16 fixed-width hex digits) rather
  than decimal fixed precision, because that is stricter: Z98 == ref ==
  committed `.expected` byte-for-byte.
