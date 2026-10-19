# M1 Foundation: Testing Substrate + std_rand + std_map Upgrade — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the cross-check testing substrate, `std_rand` (PCG32 + xoshiro256\*\*), and the Robin Hood `std_map` internals upgrade.

**Architecture:** New `run_crosscheck.sh` three-way harness (Z98 == C89 ref == committed `.expected`) folded into `verify_stdlib.sh`; `std_rand.zig` L5 module (two concrete generators, explicit seeds); `std_map.zig` keeps its API and gains Robin Hood insertion + backward-shift deletion + ctrl-byte state encoding.

**Tech Stack:** Z98 (Zig subset → C89), bash harness, gcc C89 reference builds.

**Spec:** `docs/superpowers/specs/2026-10-19-z98-std-algorithms-design.md` (§5, §6.1, §6.2; contract §3–§4 bind every task)

## Global Constraints

(Spec §3–§4, binding — every task implicitly includes these.)
- Std-only program: gates = `verify_stdlib.sh` + `run_crosscheck.sh` + usage programs + 3× determinism. SKIP: corpus classify, goldens, examples matrix, non-std mi_matrix, pins, markers, hop. Affected-example tiers: none.
- R6 determinism: no clock/env/address inside std; explicit `seed: u64` params; harness exports fixed `Z98_SEED`.
- Seed rotation at closeout (archive md5 moves; `lib/manifest.md5` recorded; binary md5 + fixed point MUST hold unchanged). Copy lists `build_from_seed.sh:146` + `archive_seed.sh:115` gain new files.
- Z98 subset (AGENTS.md §1.3): no generics, free functions, arena allocation, `error.OutOfMemory` at fixed capacity. Commit convention `refactor/fix/feat(<file>): …` + `docs(sdd): … report`; `progress.md` ledger controller-owned.
- Compiler defects → `examples/torrent_example_defects.md` (next free slot). No `sf/src` compiler-pipeline edits.

## Review Focus

1. Rejection-sampling bias in `pcg32Bounded`/`xoshiroBounded` — a `% bound` shortcut passes casual tests; only the bucket-band check over 1M draws catches it.
2. xoshiro SplitMix64 seeding byte-exactness vs reference — one bit off diverges every vector.
3. Backward-shift deletion correctness — a wrong shift leaves keys unreachable; the delete-reinsert fixture is the canary.
4. Crosscheck harness non-vacuity — a compare that can't fail proves nothing; the mutated-`.expected` control must fail.
5. Golden drift in the map fixtures — anything beyond summary-line movement is a STOP.

---

### Task 1: Testing substrate (`run_crosscheck.sh` + conventions)

**Files:**
- Create: `scripts/stdlib/run_crosscheck.sh`
- Modify: `scripts/stdlib/verify_stdlib.sh` (crosscheck pass after fixtures)
- Modify: `scripts/stdlib/run_fixtures.sh` (export fixed `Z98_SEED`)
- Create: `scripts/stdlib/vectors/smoke/{a,b,c}.{in,expected}` (3 tiny pairs)
- Create: `scripts/stdlib/ref/smoke/ref.c`
- Create: `repro/mi_matrix/stdlib_cross_smoke_xmod/{main.zig,expected.txt,expected.rc}`

**Interfaces:**
- Consumes: `run_fixtures.sh` discovery + `expected_dirs.txt` pin convention.
- Produces: `run_crosscheck.sh <zig1> [<module>…]` for every later milestone; vector layout `scripts/stdlib/vectors/<module>/<name>.{in,expected}`; ref layout `scripts/stdlib/ref/<module>/ref.c`; driver fixture `stdlib_<module>_cross_xmod` with `--crosscheck` stdin mode.

- [ ] **Step 1: Write the failing smoke fixture + ref.** `stdlib_cross_smoke_xmod/main.zig`: reads `a b` per line on stdin in `--crosscheck` mode, prints `a+b`; default mode prints fixed `cross smoke ok`. `ref.c` = same sum on stdin (C89, `long` parse). Vectors: `a=1 b=2 → 3`, `a=0 b=0 → 0`, `a=40 b=2 → 42`.
- [ ] **Step 2: Run fixture gate — expect FAIL (fixture absent from `expected_dirs.txt`).**
- [ ] **Step 3: Implement `run_crosscheck.sh`** — build driver (`zig1 -ffast` → `build_target.sh linux`) + `gcc -m32 -std=c89 -O0` ref once per module; feed each `.in` to both; three-way compare (Z98 stdout == ref stdout == `.expected`, `cmp` for binary, `diff` for text); both exit 0; wire into `verify_stdlib.sh` after the fixtures pass. `run_fixtures.sh`/`run_crosscheck.sh` export `Z98_SEED=1`.
- [ ] **Step 4: Run gates green.** `verify_stdlib.sh` full set green incl. smoke; non-vacuity control: mutate one `.expected` copy in a scratch run → run_crosscheck FAILS (restore after).
- [ ] **Step 5: Commit.** `feat(scripts): std crosscheck harness + smoke fixture`.

### Task 2: `std_rand` — PCG32 + xoshiro256\*\*

**Files:**
- Create: `sf/src/std_rand.zig`
- Create: `repro/mi_matrix/stdlib_rand_kat_xmod/{main.zig,expected.txt,expected.rc}`
- Create: `repro/mi_matrix/stdlib_rand_advance_xmod/{main.zig,expected.txt,expected.rc}`
- Create: `repro/mi_matrix/stdlib_rand_stat_xmod/{main.zig,expected.txt,expected.rc}`
- Create: `repro/mi_matrix/stdlib_rand_cross_xmod/{main.zig,expected.txt,expected.rc}`
- Create: `scripts/stdlib/ref/std_rand/ref.c`, `scripts/stdlib/vectors/std_rand/*.{in,expected}`
- Modify: `scripts/stdlib/expected_dirs.txt`, `scripts/seed/build_from_seed.sh:146`, `scripts/seed/archive_seed.sh:115`

**Interfaces:**
- Consumes: Task 1 harness. Spec §6.1 signatures (verbatim).
- Produces: `std_rand.{Pcg32,Xoshiro256,pcg32Init,pcg32Next,pcg32Bounded,pcg32Advance,xoshiroInit,xoshiroNext,xoshiroBounded}` — M2 noise + M6 physics consume these names.

- [ ] **Step 1: Write failing KAT fixture.** Seed `0xDEADBEEF`; 100 `pcg32Next` + 100 `xoshiroNext` printed as hex; `expected.txt` = reference-implementation output (generate with `ref.c` at setup, commit). Seeding test inside: two instances same seed ⇒ identical 10 values (assert).
- [ ] **Step 2: Run — FAIL (module absent).**
- [ ] **Step 3: Implement `std_rand.zig`** — PCG32 LCG + permuted output per O'Neill; `inc = (stream<<1)|1`; bounded = rejection (threshold `=-bound % bound` loop); advance = LCG matrix power in log2(delta) steps; xoshiro256\*\* core + SplitMix64 seeding per Vigna reference. `bound==0` → `@panic`.
- [ ] **Step 4: Run KAT + advance fixtures green.** `stdlib_rand_advance_xmod`: `pcg32Advance(1000)` state == 1000× `pcg32Next` (compare both states); same for `xoshiro` via 1000× next equality.
- [ ] **Step 5: Write failing stat fixture; make it pass.** `stdlib_rand_stat_xmod`: 1M u32s (fixed seed), byte-frequency chi-squared (256 bins, 4M bytes) with committed critical constant `310.5` (df=255, p=0.01) and serial Pearson `|r| < 0.01`; print `rand stat ok` on pass. Bounded-bias band: 1M `pcg32Bounded(7)` draws, bucket counts within chi-squared band.
- [ ] **Step 6: Crosscheck green.** `stdlib_rand_cross_xmod --crosscheck` vs `ref.c` over 20 vector lines (`seed,count → first outputs`).
- [ ] **Step 7: Run full gates.** verify_stdlib (incl. crosscheck) green; 3× determinism on all 4 fixtures; import-resolvability: fixture built against produced compiler's `lib/` resolves `@import("std_rand.zig")`.
- [ ] **Step 8: Commit.** `feat(std_rand): PCG32 + xoshiro256** (M1)` + fixtures.

### Task 3: `std_map` Robin Hood internals upgrade

**Files:**
- Modify: `sf/src/std_map.zig` (internals only; API/field names `entries`/`state`/`key`/`val` kept; add `dist: u8`)
- Modify: `repro/mi_matrix/stdlib_map_determinism_xmod/main.zig` (header comment only)
- Test: existing `stdlib_map_{map32x32,map32ptr,mapstrptr,oom,stress,determinism}_xmod` + `stdlib_test/map_sort_heap_usage`

**Interfaces:**
- Consumes: none.
- Produces: same `std_map` API (§6.2) — no downstream milestone depends on internals.

- [ ] **Step 1: Write failing invariants fixture** `stdlib_map_robinhood_xmod`: reverse-insertion (1000 keys), delete-reinsert (500), delete-half-verify-rest, overwrite-no-duplicate, fill→`error.OutOfMemory`, churn stress (10k put/remove cycles, all survivors findable).
- [ ] **Step 2: Run — the delete-reinsert and churn legs FAIL on tombstone code (or pass but reveal unreachable keys).** Record.
- [ ] **Step 3: Implement Robin Hood internals** — insertion swaps on greater probe distance; backward-shift deletion (shift while `dist > 0`); state byte `0x80` empty / `0x00..0x7F` hash fragment (`0xFE` reserved); slots = next pow2 ≥ `capacity`/0.75; mask indexing; `dist: u8`; `Put` OOM at caller `capacity` unchanged.
- [ ] **Step 4: All map fixtures green with goldens byte-identical.** If a golden moves: STOP-present (§6.2). `map_sort_heap_usage` output unchanged.
- [ ] **Step 5: Determinism 3× + header truth-up** (slot-ascending wording in `stdlib_map_determinism_xmod`).
- [ ] **Step 6: Commit.** `refactor(std_map): Robin Hood + backward-shift deletion (M1)`.

### Task 4: M1 closeout — docs + seed rotation

**Files:**
- Create: `sf/docs/std_lib/rand.md` (per `_template.md`)
- Modify: `sf/docs/std_lib/collections.md` (map internals section)
- Modify: `scripts/seed/archive_seed.sh` (generate `lib/manifest.md5` into archive + CHANGELOG line)
- Modify: `release/seed/CHANGELOG.md` (via `archive_seed.sh --update-changelog`)

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: rotation procedure + manifest convention reused verbatim by M2–M7.

- [ ] **Step 1: Docs** — `rand.md` (API, seeds, Z98_SEED convention, rejection rule), `collections.md` (Robin Hood/ctrl bytes/backward-shift; Swiss deferred note per spec §2).
- [ ] **Step 2: `archive_seed.sh` manifest** — `md5sum lib/*.zig > lib/manifest.md5` inside the archive; record manifest in the CHANGELOG entry.
- [ ] **Step 3: Rotate seed** — `bash scripts/seed/archive_seed.sh … --update-changelog`; verify: archive md5 recorded, `lib/manifest.md5` lists 33 files, binary md5 + fixed point **unchanged** (zero-coupling proof).
- [ ] **Step 4: Full gate re-run** (§4 RUN set) + commit `docs(std_lib): rand + map docs (M1)` / `chore(seed): rotate (M1)` per convention.
