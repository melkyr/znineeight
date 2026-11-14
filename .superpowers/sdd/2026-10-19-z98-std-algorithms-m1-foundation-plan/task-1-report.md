# M1 Task 1 report — testing substrate

**Status:** DONE
**Commit (feat):** `5d4bdde4` — `feat(scripts): std crosscheck harness + smoke fixture`
**Plan:** `docs/superpowers/plans/2026-10-19-z98-std-algorithms-m1-foundation-plan.md` Task 1
**Spec:** `docs/superpowers/specs/2026-10-19-z98-std-algorithms-design.md` §5, §3–§4
**Environment:** repo root `/workspace/znineeight`; seed compiler `/tmp/m7_t5_seed2/zig1_5_clean` (v102, fixed point `b299b4b435e624d0ddbd2edde681cbc3`).

## What changed

- **Create `scripts/stdlib/run_crosscheck.sh`** — standalone + gate cross-check:
  - discovers `scripts/stdlib/ref/<module>/` (or takes explicit module names),
  - builds the driver once (`zig1 -ffast -o <tmp>` → gcc binding flags → `build_target.sh linux`),
  - builds `scripts/stdlib/ref/<module>/ref.c` once with `gcc -std=c89 -O0`,
  - for every `scripts/stdlib/vectors/<module>/*.in`, feeds stdin to the driver in `--crosscheck` mode and to the ref,
  - requires both exit 0 and three-way byte equality (Z98 == ref, Z98 == committed `.out`, ref == committed `.out`),
  - text mismatches print `diff -u`; binary mismatches print `cmp -l`,
  - exports `Z98_SEED=1`.
  - Driver lookup accepts both `stdlib_<module>_cross_xmod` (future-module convention from the plan Interfaces) and `stdlib_cross_<module>_xmod` (the exact Task 1 smoke path).
- **Modify `scripts/stdlib/verify_stdlib.sh`** — after `run_fixtures.sh` succeeds, runs `run_crosscheck.sh` over all `ref/` modules; any failure is `STDLIB GATE FAILED`.
- **Modify `scripts/stdlib/run_fixtures.sh`** — exports fixed `Z98_SEED=1`.
- **Create smoke fixture `repro/mi_matrix/stdlib_cross_smoke_xmod/`**:
  - `main.zig`: default mode prints `cross smoke ok\n`; `--crosscheck` reads `a b` per stdin line and prints `a+b`.
  - `expected.txt` = `cross smoke ok\n`; `expected.rc` = `0`.
- **Create `scripts/stdlib/ref/smoke/ref.c`** — C89 `scanf("%ld %ld")` / `printf("%ld\n")` same-sum reference.
- **Create `scripts/stdlib/vectors/smoke/{a,b,c}.{in,out}`** — `1 2→3`, `0 0→0`, `40 2→42`.
- **Modify `scripts/stdlib/expected_dirs.txt`** — pin `repro/mi_matrix/stdlib_cross_smoke_xmod`.

## Step evidence

### Step 1 — write failing smoke fixture + ref
Created all files listed above. Fixture and ref implement the same stdin sum; the three committed vectors are the `1+2`, `0+0`, `40+2` pairs.

### Step 2 — fixture gate expected FAIL (pin absent)
Command:
```
bash scripts/stdlib/verify_stdlib.sh /tmp/m7_t5_seed2/zig1_5_clean
```
Observed (tail):
```
FAIL unpinned-stdlib-dir (repro/mi_matrix/stdlib_cross_smoke_xmod exists but is not in /workspace/znineeight/scripts/stdlib/expected_dirs.txt)
STDLIB GATE FAILED (run_fixtures rc=1)
PIPE_RC=1
```
Matches the required failing state.

### Step 3 — implement harness + wiring
`run_crosscheck.sh` implemented as described; `run_fixtures.sh` and `run_crosscheck.sh` export `Z98_SEED=1`; `verify_stdlib.sh` runs the crosscheck after fixtures.

Syntax gate:
```
bash -n scripts/stdlib/run_crosscheck.sh
bash -n scripts/stdlib/run_fixtures.sh
bash -n scripts/stdlib/verify_stdlib.sh
=> BASH_N_OK
```

### Step 4 — gates green

Targeted smoke fixture:
```
bash scripts/stdlib/run_fixtures.sh /tmp/m7_t5_seed2/zig1_5_clean repro/mi_matrix/stdlib_cross_smoke_xmod
=> PASS repro/mi_matrix/stdlib_cross_smoke_xmod
=> run_fixtures: 1 PASS / 0 FAIL over 1 dirs
=> FIXTURE_RC=0
```

Targeted crosscheck:
```
bash scripts/stdlib/run_crosscheck.sh /tmp/m7_t5_seed2/zig1_5_clean smoke
=> PASS smoke (3 vectors)
=> run_crosscheck: 1 PASS / 0 FAIL over 1 modules
=> CROSS_RC=0
```

Full gate (fixtures then crosscheck):
```
bash scripts/stdlib/verify_stdlib.sh /tmp/m7_t5_seed2/zig1_5_clean
=> run_fixtures: 287 PASS / 0 FAIL over 287 dirs
=> == std-lib crosscheck gate ==
=> PASS smoke (3 vectors)
=> run_crosscheck: 1 PASS / 0 FAIL over 1 modules
=> STDLIB GATE OK
=> VERIFY_RC=0
```
Observed wall time for this full run: ~1m51s.

Non-vacuity control (scratch tree, not the committed tree):
```
scratch="$(mktemp -d /tmp/stdlib_crosscheck_scratch.XXXXXX)"
# copy scripts/stdlib/{run_crosscheck.sh,ref,vectors} + repro/.../stdlib_cross_smoke_xmod
cp scratch vectors/smoke/a.out -> scratch vectors/smoke/c.out   # mutate expected 42 -> 3
bash "$scratch/scripts/stdlib/run_crosscheck.sh" /tmp/m7_t5_seed2/zig1_5_clean smoke
=> FAIL smoke (Z98-NE-EXPECTED:c)
=> run_crosscheck: 0 PASS / 1 FAIL over 1 modules
=> MUTATED_RC=1
# restore c.out from the repo copy
bash "$scratch/scripts/stdlib/run_crosscheck.sh" /tmp/m7_t5_seed2/zig1_5_clean smoke
=> PASS smoke (3 vectors)
=> RESTORED_RC=0
```
The harness fails on a mutated `.out`, so the compare is non-vacuous.

### Step 5 — commit (a)
```
git commit -m "feat(scripts): std crosscheck harness + smoke fixture"
=> 5d4bdde4
```
Tracked paths: `scripts/stdlib/run_crosscheck.sh`, `scripts/stdlib/verify_stdlib.sh`, `scripts/stdlib/run_fixtures.sh`, `scripts/stdlib/expected_dirs.txt`, `scripts/stdlib/vectors/smoke/*`, `scripts/stdlib/ref/smoke/ref.c`, `repro/mi_matrix/stdlib_cross_smoke_xmod/*`.

## Deviations / notes

1. **Smoke driver name.** The plan Interfaces line says `stdlib_<module>_cross_xmod`; the Task 1 Files line and Step 1 pin the smoke path as `stdlib_cross_smoke_xmod`. I used the Task 1 exact path and made the harness accept both spellings so later modules can use `stdlib_<module>_cross_xmod` (`rand`, etc.) without renaming smoke.
2. **Vector `.out` files are gitignored** by the repo's `*.out` rule. They were intentionally committed with `git add -f` (committed vectors are the point of the substrate); no other ignored files were force-added.
3. **Binary/text compare.** Equality is always `cmp -s` (byte-exact for both text and binary). Diagnostics choose `diff -u` for NUL-free files and `cmp -l` for files containing NUL. This satisfies the "cmp for binary, diff for text" intent; there is no separate text-normalizing compare.
4. **Ref build flags.** `ref.c` is built exactly as specified (`gcc -std=c89 -O0`) without `-m32`; the Z98 driver uses the binding `-m32` flag set, matching `run_fixtures.sh`.

## Concerns

- The C89 ref build is host-width (no `-m32`). The smoke sums fit either width; later refs should avoid printing host-width-dependent values unless the spec is amended to add `-m32` for refs.
- `run_crosscheck.sh` treats an empty `ref/` discovery as an error (`exit 2`), not a vacuous pass. This is deliberate but means the script cannot be used as a no-op on a tree without refs.
- `verify_stdlib.sh` always runs the full crosscheck discovery even when explicit fixture dirs are supplied; this is intentional (gate coverage does not shrink with targeted fixture runs), but it does add crosscheck time to targeted fixture invocations.

## Final status

DONE — all Task 1 gates green; commit (a) `5d4bdde4`; report committed as (b).

## Fix round 1

Base reviewed: `17d34b97`. Operator rulings applied: vector expectations use `.expected`, and refs build `gcc -m32 -std=c89 -O0`.

### Item 1 — rename vectors `.out` → `.expected`
Command:
```
git mv scripts/stdlib/vectors/smoke/a.out scripts/stdlib/vectors/smoke/a.expected
git mv scripts/stdlib/vectors/smoke/b.out scripts/stdlib/vectors/smoke/b.expected
git mv scripts/stdlib/vectors/smoke/c.out scripts/stdlib/vectors/smoke/c.expected
```
Observed:
```
R  scripts/stdlib/vectors/smoke/a.out -> scripts/stdlib/vectors/smoke/a.expected
R  scripts/stdlib/vectors/smoke/b.out -> scripts/stdlib/vectors/smoke/b.expected
R  scripts/stdlib/vectors/smoke/c.out -> scripts/stdlib/vectors/smoke/c.expected
```
No `.gitignore` edit.

### Item 2 — `run_crosscheck.sh` expectation path + messages + `-m32`
Changed `out_file="$vec_dir/$name.expected"`, header/user-facing messages from `.out` to `.expected`, and the ref build to `gcc -m32 -std=c89 -O0` (temporary `z.out`/`r.out` capture files are unchanged internals).

Evidence:
```
grep -n "\.out\|\.expected\|gcc .*O0" scripts/stdlib/run_crosscheck.sh
2:# Cross-check gate for std modules: Z98 == C89 reference == committed .expected.
15:#   2. build `scripts/stdlib/ref/<module>/ref.c` once: `gcc -m32 -std=c89 -O0`.
18:#      three ways: Z98 == ref, Z98 == committed .expected, ref == committed .expected.
133:    gcc -m32 -std=c89 -O0 "$ref_dir/ref.c" -o "$tmp/ref" ...
148:        out_file="$vec_dir/$name.expected"
```
(Remaining `.out` lines are only `z.out`/`r.out` temporary capture files.)

### Item 3 — spec §5/§6.4
Applied `<name>.out` → `<name>.expected`, `committed .out` → `committed .expected`, `*.{in,out}` → `*.{in,expected}`, and ref flag `gcc -std=c89 -O0` → `gcc -m32 -std=c89 -O0`.

Evidence:
```
grep -n "{in,out}\|\.out\|gcc -std=c89" docs/superpowers/specs/2026-10-19-z98-std-algorithms-design.md
=> NO_REMAINING
```

### Item 4 — plans M1–M7
Applied every `{in,out}` → `{in,expected}`, every `.out` → `.expected`, and M1 Step 3 ref flags → `gcc -m32 -std=c89 -O0`.

Evidence:
```
grep -rn "{in,out}\|\.out\|gcc -std=c89 -O0" docs/superpowers/specs/...design.md docs/superpowers/plans/...m*-*.md
=> NO_REMAINING
```
M1 now shows `{a,b,c}.{in,expected}`, `<name>.{in,expected}`, `*.{in,expected}`, `mutated-.expected`, and `gcc -m32 -std=c89 -O0`; M2–M7 show `*.{in,expected}`.

### Item 5 — gates

Syntax:
```
bash -n scripts/stdlib/*.sh
=> BASH_N_OK
```

Smoke crosscheck:
```
bash scripts/stdlib/run_crosscheck.sh /tmp/m7_t5_seed2/zig1_5_clean smoke
=> PASS smoke (3 vectors)
=> run_crosscheck: 1 PASS / 0 FAIL over 1 modules
=> CROSS_RC=0
```

Full gate:
```
bash scripts/stdlib/verify_stdlib.sh /tmp/m7_t5_seed2/zig1_5_clean
=> run_fixtures: 287 PASS / 0 FAIL over 287 dirs
=> == std-lib crosscheck gate ==
=> PASS smoke (3 vectors)
=> run_crosscheck: 1 PASS / 0 FAIL over 1 modules
=> STDLIB GATE OK
=> VERIFY_RC=0
```

Non-vacuity (scratch copy; mutate `c.expected` from `42` to `3`, then restore):
```
cp scratch vectors/smoke/a.expected -> scratch vectors/smoke/c.expected
bash "$scratch/scripts/stdlib/run_crosscheck.sh" /tmp/m7_t5_seed2/zig1_5_clean smoke
=> z98 vs committed .expected: ... -42 +3
=> FAIL smoke (Z98-NE-EXPECTED:c)
=> run_crosscheck: 0 PASS / 1 FAIL over 1 modules
=> MUTATED_RC=1

cp repo vectors/smoke/c.expected -> scratch vectors/smoke/c.expected
bash "$scratch/scripts/stdlib/run_crosscheck.sh" /tmp/m7_t5_seed2/zig1_5_clean smoke
=> PASS smoke (3 vectors)
=> RESTORED_RC=0
```
Harness still fails on a mutated expectation, so the control is non-vacuous with `.expected`.

### Item 6 — commit (a)
```
git commit -m "refactor(scripts): vector expectations .expected; refs -m32"
=> aab2ddef
```
Commit (a) tracks only vectors, `run_crosscheck.sh`, spec, and plans; report is committed separately as (b).

### Fix round 1 status

DONE — both operator findings applied and gated; commit (a) `aab2ddef`.

