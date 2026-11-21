# M4 Task 2 report — docs + seed rotation

Status: COMPLETE
Base: `62ba15a0` (Task 1 complete ledger)
Branch: `zig1_improvements`

## Step 1 — Docs (verified)

Created `sf/docs/std_lib/num.md` documenting:

- API: `Rk45Config`, `Rk45State`, `rk45Step` signatures and field semantics.
- Tolerance semantics: scaled RMS norm
  `err = sqrt(mean((h*e_i/(atol+rtol*max(|y_i|,|y5_i|)))^2))`,
  accept `err <= 1`, reject `0.9*err^(-1/5)`.
- FSAL: caller seeds `dy = f(t,y)`; on accept `dy` becomes the 7th stage;
  rejected attempts leave state/`dy` unchanged.
- Stiff-system caveat: explicit method, stiff problems may exhaust
  `min_step`/`max_steps` and return `error.StepTooSmall`.
- `RK45_MAX_DIM = 64` fixed scratch cap (caller precondition; `n == 0` or
  `n > 64` panics).
- Accept-growth threshold: `1.5x` applied only when `err < 0.5`, capped at
  `max_step`; `0.5 <= err <= 1` keeps `dt` unchanged.
- In/out `dt` semantics (`state.t` advances by the taken step; `dt` returns the
  next suggestion), endpoint clamping is the caller's job.

Post-commit correction (carried in the `docs(sdd)` commit): the callback `f`
is invoked six times per attempted step (stages 2–7), not seven; the first
stage is the caller-provided `dy` (FSAL). The doc now states that precisely.

Truth-ups to 37 std files / `std_num` (no `sf/src` changes):

- `scripts/seed/archive_seed.sh`: module-list comment, archive `lib/` layout
  text, manifest count, std-install text, changelog template manifest row.
- `scripts/seed/build_from_seed.sh`: header std-lib count.
- `docs/sf/QUICK_REF.md`: std-set count `36 std_*.zig + std.zig = 37`,
  inventory list + `std_num`, installs all 37, install command, `std_num` note
  with doc link. (The v107 seed block stays period-accurate until rotation.)
- `README.md`: higher-layer module list + `std_num`.
- `STD_README.MD`: L5 row (codecs + numerics), job table row, domain-doc index
  row.

## Gate — before rotation (verified)

Command:

```
bash scripts/stdlib/verify_stdlib.sh /tmp/m4_t1_build/zig1_5_clean
```

Observed tail:

```
run_fixtures: 301 PASS / 0 FAIL over 301 dirs
PASS std_num (1 vectors)
run_crosscheck: 6 PASS / 0 FAIL over 6 modules
STDLIB GATE OK
```

Compiler under test: `/tmp/m4_t1_build/zig1_5_clean`, md5
`21c957730d268f1e7883176fa5413b65`.

## Step 2 — Seed rotation (verified)

Command:

```
bash scripts/seed/archive_seed.sh /tmp/m4_t1_build/zig1_5_clean \
  /tmp/m4_t1_build/gen release/seed/zig1-seed.tgz --update-changelog
```

Observed:

```
[archive] gcc-only rebuild of archive C md5 (fixed point): 21c957730d268f1e7883176fa5413b65
[archive] wrote release/seed/zig1-seed.tgz (archive md5 f73943f4ce5170e3c776fb985a24cb43)
[archive] prepended entry to /workspace/znineeight/release/seed/CHANGELOG.md
```

Recorded values (seed v108, HEAD `4929f70e`):

- archive md5: `f73943f4ce5170e3c776fb985a24cb43` (moved from v107
  `5ec6e497bb962ff0fdf3145311acc4a1`)
- `lib/manifest.md5`: `f98a25b905994f17c72a39d4507c3d7e` (37 files; moved from
  v107 `aac8a4bf651d8d616c2b4ee3400c58f3`)
- std file count: 37 `.zig` (36 `std_*.zig` + `std.zig`), including
  `lib/std_num.zig`
- seed binary md5: `21c957730d268f1e7883176fa5413b65` (UNCHANGED)
- self-emission fixed point: `21c957730d268f1e7883176fa5413b65` (UNCHANGED)
- `gen/`: 46 `.c` + 47 `.h`, 10,307,965 bytes

Verification of the packed archive:

```
tar -tzf release/seed/zig1-seed.tgz | grep '^zig1-seed/lib/'
# 39 entries = 37 .zig + manifest.md5 + lib/ dir
tar -xOzf ... zig1-seed/lib/manifest.md5 | wc -l          # 37
md5sum extracted manifest                                # f98a25b905994f17c72a39d4507c3d7e
tar -xOzf ... zig1-seed/zig1 | md5sum                    # 21c957730d268f1e7883176fa5413b65
```

Import-resolvability check against the freshly packed archive:

```
tar -xzf release/seed/zig1-seed.tgz -C /tmp/m4_t2_seedcheck
bash scripts/stdlib/run_fixtures.sh /tmp/m4_t2_seedcheck/zig1-seed/zig1 \
  repro/mi_matrix/stdlib_num_basic_xmod repro/mi_matrix/stdlib_num_cross_xmod
# 2 PASS / 0 FAIL
```

`docs/sf/QUICK_REF.md` current-seed block truth-up: v107 → v108, 36 → 37,
archive `f73943f4…`, manifest `f98a25b9…`, `std_num` mentioned. Historical seed
notes left period-accurate.

## Gate — after rotation (verified)

Command:

```
bash scripts/stdlib/verify_stdlib.sh /tmp/m4_t1_build/zig1_5_clean
```

Observed tail:

```
run_fixtures: 301 PASS / 0 FAIL over 301 dirs
PASS std_num (1 vectors)
run_crosscheck: 6 PASS / 0 FAIL over 6 modules
STDLIB GATE OK
```

## Commits

- `docs(std_lib): num docs (M4)` — `4929f70e`
- `chore(seed): rotate (M4)` — `d1f52621`
- `docs(sdd): M4 T2 report` — committed after this file was finalized

## Concerns

- None affecting the task. The untracked `run.err` at repo root predated this
  task and was left untouched/uncommitted.

