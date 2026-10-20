# M2 Task 1 report — std_noise

**Status:** STOP-PRESENTED (hard Step-1 gate failed; `std_noise` NOT implemented; awaiting spec amendment)
**Branch:** `zig1_improvements`
**Plan:** `docs/superpowers/plans/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan.md` Task 1
**Spec:** `docs/superpowers/specs/2026-10-19-z98-std-algorithms-design.md` §6.5, §5.5
**Brief:** `.superpowers/sdd/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan/task-1-brief.md`
**Context:** `.superpowers/sdd/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan/task-1-context.md`
**Environment:** repo root `/workspace/znineeight`; seed-built compiler `/tmp/t4_review/zig1_5_clean` (md5 `b299b4b435e624d0ddbd2edde681cbc3`).

## STOP-present text

I found the intention is blueprint §5.5 zero-at-lattice (`noise2d` exactly `0` at `(0,0)`, `(1,0)`, `(0,1)`, `(1,1)`), but this is impossible given the 2014 reference returns `0`, `0.42680000932807727`, `-0.061333742599571132`, `-0.62215238898136938` for those four points (seed `0`).

Only `(0,0)` is zero. The other three integer lattice points are nonzero, so the claimed Perlin-style zero-at-integer-lattice property does not hold for the 2014 OpenSimplex reference. Per Task 1 Step 1, work stopped immediately after the pre-check.

## Files created (pre-check evidence only)

- `scripts/stdlib/ref/std_noise/ref.c` — C89 port of Kurt Spencer's 2014 OpenSimplex v1.1 (2D/3D), with attribution header. Permutation state is initialized with the binding M1 xoshiro256** Fisher-Yates mapping (not the Java class's internal LCG) so a future crosscheck would pin the same state; gradients, skew/unskew constants, attenuation, and normalization match the 2014 source.
  - Default mode implements the Step-4 line protocol (`2 <seed> <x> <y>` / `3 <seed> <x> <y> <z>`; one 16-lowercase-hex IEEE-754 f64 bit pattern per line).
  - `--lattice` implements the Step-1 four-point check for seed `0`.
- This report.

No `sf/src/std_noise.zig`, no fixtures, no vectors, no `expected_dirs.txt` change, no seed copy-list change, and no `std_noise` crosscheck driver were created. No unrelated files were modified.

## Step 1 — reference port and four lattice checks

Build (exact reference flags; the extra warning flags in the earlier compile were not used for the recorded run):

```sh
gcc -m32 -std=c89 -O0 scripts/stdlib/ref/std_noise/ref.c -o /tmp/ref_noise_exact
```

Run:

```sh
/tmp/ref_noise_exact --lattice
```

Observed (3 consecutive runs byte-identical):

```text
0 0 0000000000000000 0
1 0 3fdb50b0fc7fc814 0.42680000932807727
0 1 bfaf6722e5367f4f -0.061333742599571132
1 1 bfe3e8ac2079b43e -0.62215238898136938
```

Interpretation (seed `0`):

| point | value | zero? |
|---|---:|---|
| `(0,0)` | `0.0` | yes |
| `(1,0)` | `0.42680000932807727` | **no** |
| `(0,1)` | `-0.061333742599571132` | **no** |
| `(1,1)` | `-0.62215238898136938` | **no** |

The nonzero result is stable under re-running the reference. The port was also cross-checked against an independent scratch Python transcription of the same 2014 2D algorithm and the same xoshiro permutation; values agree to the printed decimal precision (last-bit differences were observed only from host floating-point evaluation, not from algorithm structure).

## Crosscheck / vector format

The reference implements the required Step-4 protocol, but no `.in`/`.expected` vectors or `stdlib_noise_cross_xmod` driver were created because the Step-1 gate stopped the task. `noiseFbm2d` is therefore untested and unimplemented. The reference default mode was not exercised beyond the lattice pre-check.

## Gates / battery

Not run. The plan says "STOP-present immediately; do not implement" on a nonzero lattice result, so the full §4 RUN set, 3× fixture determinism, import-resolvability, and crosscheck gate were intentionally not run. There is no `std_noise` module to gate. The only executed check is the compiled reference pre-check above.

## Commits

- Feat commit: **not created** — `feat(std_noise): OpenSimplex 2D/3D + fBm (M2)` would misrepresent a stopped task with no `std_noise` module.
- Report commit: `docs(sdd): M2 T1 report` (this file).
- `scripts/stdlib/ref/std_noise/ref.c` is left uncommitted as working-tree evidence for the STOP-present.

## Concerns

1. **Primary blocker:** blueprint §5.5's zero-at-integer-lattice claim is false for the 2014 OpenSimplex reference at `(1,0)`, `(0,1)`, `(1,1)`. The plan/spec must decide whether to drop this assertion, narrow it to `(0,0)`, or pin the reference behavior. Do not implement `std_noise` until that ruling lands.
2. **3D gradient-count discrepancy:** the brief/context say "12 cube-edge gradients" for 3D, but the actual 2014 v1.1 reference (`OpenSimplexNoiseKS.java`) uses 24 3D gradients (rhombicuboctahedron), with `perm_grad[i] = (perm[i] % 24) * 3`. The port follows the actual 2014 source (24). This needs an explicit plan ruling before Step 3 if work resumes.
3. **Seed-init mismatch vs upstream source:** the binding contract requires `perm`/`perm_grad` via M1 xoshiro Fisher-Yates, while the Java 2014 class uses an internal 64-bit LCG. The port follows the binding contract, so it will not byte-match the Java class's seed-0 permutation; it is the crosscheck reference for the planned Z98 mapping.
4. **Last-bit FP reproducibility:** the scratch independent transcription and the C reference agreed in decimal but differed in the final one or two bits of the f64 pattern for some points. Any future crosscheck must compare the Z98-emitted C and the C reference under the same `gcc -m32 -std=c89 -O0` expression order (x87 vs SSE evaluation matters). This was not reached because of the STOP.
