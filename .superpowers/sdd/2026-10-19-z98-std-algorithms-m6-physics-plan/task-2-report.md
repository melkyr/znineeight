# M6 Task 2 report — closeout docs + seed rotation

Status: COMPLETE

Commits: `bb2648cc` `docs(std_lib): physics docs (M6)`,
`f95eee8b` `chore(seed): rotate (M6)`, plus this report commit
`docs(sdd): M6 T2 report`.

Base: `dc99f30c` on `zig1_improvements`. Compiler:
`/tmp/m5_seed/zig1_5_clean` (md5 `21c957730d268f1e7883176fa5413b65`,
v109; `lib/` has the current 39-file std set after Task 1).

## Scope

- Create `sf/docs/std_lib/physics.md`.
- Truth-up `STD_README.MD`, `README.md`, `docs/sf/QUICK_REF.md`.
- Update `scripts/seed/archive_seed.sh` and `scripts/seed/build_from_seed.sh`
  prose/copy lists to 39 std files.
- Rotate the seed to v110 (39-file manifest; binary md5 and fixed point must
  stay `21c957730d268f1e7883176fa5413b65`).
- Re-run the full std gate and verify the rotated archive/build.
- No `sf/src` changes; controller-modified plan/spec left uncommitted.

## Docs

### `sf/docs/std_lib/physics.md` (new)

Follows the domain-doc template and sibling L5 docs: module table, overview,
quick start, API entries for `Particle`, `DistanceConstraint`, `PbdWorld`,
`pbdInit`, `pbdAddParticle`, `pbdAddDistance`, `pbdPin`, `pbdStep`,
preconditions, gates, and see-also. Documents:

- the Verlet contract `new = pos + (pos-prev)*(1-damping) + gravity*dt*dt`,
  `prev = old pos`, and non-pinned-only integration;
- the f64 `std_math.sqrt` / f32-cast length rule in both `pbdAddDistance` and
  `pbdStep`;
- inverse-mass projection (`wa/(wa+wb)`, `wb/(wa+wb)`) and the
  `len==0`/`wa+wb==0` skips;
- stiffness as the per-iteration fraction, with cloth guidance (stiffness 1,
  4–8 iterations) and soft-body guidance (lower stiffness, more iterations);
- no collision constraints in v1;
- seeded Fisher–Yates shuffle determinism (same seed + world + dt sequence =>
  bit-identical trajectory);
- pin semantics (`inv_mass = 0`, never moves), `iterations == 0` = integrate
  only, and all panic preconditions;
- gates and the `stdlib_test/physics_usage` R7b usage program.

The quick-start example was compiled and run against `/tmp/m5_seed`; it prints
`0.628548` for the free end's height after 240 steps, matching the doc text.

### Truth-up list

- `STD_README.MD` — L5 meaning adds position-based physics and the module list
  adds `std_physics`; job table adds the PBD row; domain index adds
  `physics.md`; Layer model / Which module / Domain docs stamps move to
  `[updated: 2026-10-21 — M6]`.
- `README.md` — higher-layer module list adds `std_physics`; Standard Library
  section stamped `[updated: 2026-10-21 — M6]`.
- `docs/sf/QUICK_REF.md` — current seed v109 → v110, archive md5
  `f9e7221c603fa85ef117c45e7c0edb6b`, 39-file manifest
  `b51e02d50e85e915aeef6ac18a64da86`, binary/fixed point unchanged; module
  inventory 37+1 → 38+1, install recipe adds `std_physics.zig`, new
  `std_physics` bullet; seed section stamped `[updated: 2026-10-21 — M6]`.
- `scripts/seed/archive_seed.sh` — header lib list and `SEED_README`/install/
  changelog prose move 38 → 39 and list `std_physics.zig`. The copy loop
  already contained `std_physics.zig` from Task 1.
- `scripts/seed/build_from_seed.sh` — std-lib comment 38 → 39. The install
  line already contained `std_physics.zig` from Task 1.

## Seed rotation (verified)

Fresh self-emission used for the archive: `/tmp/m6_t2_dump` (50 module+support
`.c`, 49 `.h`; module file md5s identical to `/tmp/m5_seed/gen`). The
compiler-independent module C is unchanged because the fixed point did not
move.

```
$ bash scripts/seed/archive_seed.sh /tmp/m5_seed/zig1_5_clean \
    /tmp/m6_t2_dump release/seed/zig1-seed.tgz --update-changelog
[archive] gcc-only rebuild of archive C md5 (fixed point): 21c957730d268f1e7883176fa5413b65
[archive] wrote release/seed/zig1-seed.tgz (archive md5 f9e7221c603fa85ef117c45e7c0edb6b)
...
| lib manifest | `lib/manifest.md5` (39 std files; md5 `b51e02d50e85e915aeef6ac18a64da86`) |
| archive md5 | `f9e7221c603fa85ef117c45e7c0edb6b` |
[archive] prepended entry to /workspace/znineeight/release/seed/CHANGELOG.md
```

- Seed: v109 → **v110** (HEAD `dc99f30c`).
- Archive md5: `e4338befc2a95daeca2b103d00da37c3` → **`f9e7221c603fa85ef117c45e7c0edb6b`**.
- Manifest: **39 std files**, md5 `b51e02d50e85e915aeef6ac18a64da86`
  (v109: 38 files, `e390dff49f843bda62f221ef6184a1de`).
- Archived binary md5: **`21c957730d268f1e7883176fa5413b65`** (unchanged).
- Self-emission fixed point from the archive C:
  **`21c957730d268f1e7883176fa5413b65`** (unchanged).
- `gen/`: 46 `.c` + 47 `.h`, 10,307,965 bytes (unchanged).
- `release/seed/CHANGELOG.md`: v110 entry prepended by the script.

## Archive verification

```
$ tar -xzf release/seed/zig1-seed.tgz -C /tmp/m6_t2_verify
$ md5sum /tmp/m6_t2_verify/zig1-seed/zig1
21c957730d268f1e7883176fa5413b65
$ ls /tmp/m6_t2_verify/zig1-seed/lib/*.zig | wc -l
39
$ md5sum /tmp/m6_t2_verify/zig1-seed/lib/manifest.md5
b51e02d50e85e915aeef6ac18a64da86
$ grep -c 'std_physics.zig' /tmp/m6_t2_verify/zig1-seed/lib/manifest.md5
1
$ md5sum /tmp/m6_t2_verify/zig1-seed/lib/std_physics.zig sf/src/std_physics.zig
b65ba5da3aa0527c2ce4d4c03e2f07a6  /tmp/m6_t2_verify/zig1-seed/lib/std_physics.zig
b65ba5da3aa0527c2ce4d4c03e2f07a6  sf/src/std_physics.zig
$ grep -n "39 std\|std_physics" /tmp/m6_t2_verify/zig1-seed/SEED_README.txt
24:zig1-seed/lib/        the 39 std .zig (std.zig, std_io.zig, std_fmt.zig,
34:                      std_num.zig, std_pathfind.zig, std_physics.zig)
35:zig1-seed/lib/manifest.md5  per-file md5 of every lib/*.zig (39 std files,
111:std install: the produced binary needs the std lib next to it (lib/ with the 39
```

## Full gate (post-rotation)

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m5_seed/zig1_5_clean
...
run_fixtures: 309 PASS / 0 FAIL over 309 dirs
== std-lib crosscheck gate ==
PASS std_physics (1 vectors)
run_crosscheck: 8 PASS / 0 FAIL over 8 modules
STDLIB GATE OK
RC=0
```

## Rebuild from the rotated archive

```
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m6_t2_build
[seed] hop1 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] hop2 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] two-hop closure OK: hop1 == hop2 == 21c957730d268f1e7883176fa5413b65
=== [seed] Done: /tmp/m6_t2_build ===
RC=0
```

Import resolvability through the rebuilt compiler's `lib/`:

```
$ md5sum /tmp/m6_t2_build/lib/std_physics.zig sf/src/std_physics.zig
b65ba5da3aa0527c2ce4d4c03e2f07a6  /tmp/m6_t2_build/lib/std_physics.zig
b65ba5da3aa0527c2ce4d4c03e2f07a6  sf/src/std_physics.zig
```

Targeted physics fixtures against the rebuilt compiler:

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m6_t2_build/zig1_5_clean \
    repro/mi_matrix/stdlib_physics_basic_xmod \
    repro/mi_matrix/stdlib_physics_cross_xmod \
    repro/mi_matrix/stdlib_physics_panic_xmod \
    repro/mi_matrix/stdlib_physics_panic_distance_xmod \
    stdlib_test/physics_usage
PASS repro/mi_matrix/stdlib_physics_basic_xmod
PASS repro/mi_matrix/stdlib_physics_cross_xmod
PASS repro/mi_matrix/stdlib_physics_panic_xmod
PASS repro/mi_matrix/stdlib_physics_panic_distance_xmod
PASS stdlib_test/physics_usage
run_fixtures: 5 PASS / 0 FAIL over 5 dirs
```

The two panic fixtures print the expected SIGTRAP messages to the terminal and
pass with empty stdout + rc `133`.

## Determinism (3 runs, byte-identical)

Fresh dump+build of `stdlib_physics_basic_xmod` with the rebuilt compiler, same
seed:

```
run1 rc=0
run2 rc=0
run3 rc=0
cmp12=0 cmp13=0
bb0dbb27876579168cb87c5e765a3bff  /tmp/m6_det/run1.out
bb0dbb27876579168cb87c5e765a3bff  /tmp/m6_det/run2.out
bb0dbb27876579168cb87c5e765a3bff  /tmp/m6_det/run3.out
bb0dbb27876579168cb87c5e765a3bff  repro/mi_matrix/stdlib_physics_basic_xmod/expected.txt
```

The harness itself also runs every fixture three times.

## Concerns

- The archive's recorded HEAD is `dc99f30c` (the implementation base), because
  rotation ran before the docs/seed commits. The compiler source is identical
  to the closeout state: the only later commits are docs, scripts, the seed,
  and this report, and the fixed point stayed
  `21c957730d268f1e7883176fa5413b65`.
- No `sf/src` change was made in this task.
- The plan/spec files remain modified by the controller and are intentionally
  uncommitted.
- `run.err` was left untouched (untracked).

## Fix round 1

Docs-only corrections; no `sf/src` or seed change. The product doc is a separate
commit (`docs(std_lib): physics projection truth-up`), followed by this report
commit (`docs(sdd): M6 T2 fix round 1`).

### Important — projection formula and skip rules

Added a `### Projection formula and skip rules` section to
`sf/docs/std_lib/physics.md` that states, matching spec §6.8 and source:

```
corr = (len - rest) / len * stiffness
pos[a] += dx * corr * wa / (wa + wb)      (likewise dy, dz)
pos[b] -= dx * corr * wb / (wa + wb)      (likewise dy, dz)
```

with `wa = inv_mass[a]`, `wb = inv_mass[b]`, and explicit skip rules: skip when
`len == 0` or `wa + wb == 0`, before `corr` is formed. This makes the earlier
report's claim accurate.

### Minor — RNG draws, quick-start lengths, spec no-op

- `pbdStep` gotchas and the shuffle paragraph now say the Fisher–Yates shuffle
  and rng draw happen only with `constraint_count >= 2`; one constraint has no
  shuffle draw. Zero constraints integrates and returns.
- The quick-start note now says the link distances stay within f32 rounding of
  rest length `1` (about `1.000024` and `1.0`), not exactly `1`.
- Spec §6.8 truth-up (documentation only, **not committed**):
  `Zero particles/constraints is a no-op.` →
  `Zero particles is a no-op; zero constraints integrates only.`

Verification:

```
$ grep -n "Projection formula\|corr = (len\|wa + wb == 0" sf/docs/std_lib/physics.md
73:### Projection formula and skip rules
80:corr = (len - rest) / len * stiffness
88:**Skip rules:** a constraint is skipped entirely when `len == 0` (no direction
89:to project along) or `wa + wb == 0` (both endpoints pinned). The skip happens
$ git diff --check -- sf/docs/std_lib/physics.md
(no output; rc=0)
```

The plan/spec remain controller-modified and uncommitted; `run.err` is still
untouched.
