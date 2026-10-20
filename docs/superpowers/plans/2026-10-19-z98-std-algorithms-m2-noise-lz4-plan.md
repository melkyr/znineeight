# M2 Codecs-Lite: std_noise + std_lz4 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land OpenSimplex noise (consumes M1 `std_rand`) and the LZ4 block decoder (validates the binary-vector cross-check).

**Architecture:** `std_noise.zig` L5 (512 B state, f64 math, permutation seeded by xoshiro Fisher–Yates); `std_lz4.zig` L4 stateless decoder (vendored `LZ4_decompress_safe` as ref).

**Tech Stack:** Z98 → C89; gcc C89 refs; host `lz4` CLI for vector generation (setup-time only).

**Spec:** `docs/superpowers/specs/2026-10-19-z98-std-algorithms-design.md` (§5, §6.3, §6.5)

## Global Constraints

M1 plan Global Constraints bind verbatim (std-only gates, R6 determinism, seed rotation at closeout, copy-list edits, Z98 subset, defects → torrent doc).

## Review Focus

1. OpenSimplex reference behavior — pin the actual 2014 algorithm; blueprint’s zero-at-lattice claim is superseded (only `(0,0)` is zero).
2. Skew/unskew constants exact — wrong literals give seam artifacts the range test can't see.
3. LZ4 length-extension loops (15→+255…) — the classic off-by-255 corruption source.
4. Match-offset LE u16 + end rules (5 literals / 12-byte) — violations must be `error.Corrupt`, not OOB reads.
5. f64 purity in noise — an f32 shortcut survives unit tests and fails the visual golden.

---

### Task 1: `std_noise` — OpenSimplex 2D/3D + fBm

**Files:**
- Create: `sf/src/std_noise.zig`
- Create: `scripts/stdlib/ref/std_noise/ref.c` (port of 2014 OpenSimplex, `github.com/KdotJPG/OpenSimplexNoise`, attribution header)
- Create: `scripts/stdlib/vectors/std_noise/*.{in,expected}`
- Create: `repro/mi_matrix/stdlib_noise_{basic,cross}_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`, seed copy lists (`build_from_seed.sh:146`, `archive_seed.sh:115`)

**Interfaces:**
- Consumes: M1 `std_rand.xoshiroInit`/`xoshiroNext`/`xoshiroBounded` (§6.1 names).
- Produces: `std_noise.{OpenSimplex,opensimplexInit,noise2d,noise3d,noiseFbm2d}` — §6.5 signatures verbatim.

- [ ] **Step 1: 2014 reference pre-check (pin, no STOP).** Port ref first; record ref `noise2d(0,0)`, `(1,0)`, `(0,1)`, `(1,1)` for seed 0. The 2014 reference is authoritative: `(0,0)` is zero and the other three are nonzero; blueprint §5.5 zero-at-lattice is superseded. Pin these values in vectors/docs.
- [ ] **Step 2: Write failing fixtures.** `stdlib_noise_basic_xmod`: range test 100k samples in [-1,1]; continuity `|n(x,y)-n(x+0.0001,y)| < 0.001`; determinism (two inits same seed ⇒ identical 1k samples); `octaves=0 ⇒ 0.0`; committed visual golden (256×256 PGM from `noiseFbm2d`, byte-hash in `expected.txt`).
- [ ] **Step 3: Implement `std_noise.zig`** — 2014 algorithm: skew `(sqrt(3)-1)/2` / unskew `(3-sqrt(3))/6` literals; 8 gradients 2D / **24 rhombicuboctahedron** 3D (`perm_grad[i] = (perm[i] % 24) * 3`); `perm`/`perm_grad` via xoshiro Fisher–Yates; f64 throughout; `opensimplexInit` 512 B state.
- [ ] **Step 4: Crosscheck green.** `.in` lines are `2 <seed> <x> <y>` or `3 <seed> <x> <y> <z>` (decimal). `stdlib_noise_cross_xmod --crosscheck` re-inits `opensimplexInit(seed)` per line and prints exactly one line: the 16 lowercase hex digits of the IEEE-754 f64 bit pattern returned by `noise2d`/`noise3d`; always exits 0. Ref uses the same line format. `noiseFbm2d` is covered by the basic fixture/visual golden, not crosscheck. Vectors = seeds × coordinate grid.
- [ ] **Step 5: Gates + commit.** Full §4 RUN set; 3× determinism; import-resolvability. `feat(std_noise): OpenSimplex 2D/3D + fBm (M2)`.

**Status (2026-10-19): BLOCKED.** The implementing commit `10fd69c0` and report `72297f98` are held, not complete. The lexer f64 rounding defect (`D6`) invalidated the ULP workaround. Do not review or close Task 1; resume after Task 1D.

### Task 1A: Lexer f64 rounding — investigation (derivative of blocked Task 1)

**Files:**
- Create: `.superpowers/sdd/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan/task-1a-report.md`
- No source, fixture, seed, or tracked-file edits.

**Interfaces:**
- Consumes: `sf/src/lexer.zig` `parseF64`; current compiler `/tmp/t4_review/zig1_5_clean`.
- Produces: root cause, minimal repro, correct IEEE-754 bit table, full affected-file inventory, and migration list for Task 1B/1C/1D.

- [ ] **Step 1: Root-cause the parser.** Confirm the mantissa fraction loop and the exponent `power *= 10.0` path both contribute to incorrect rounding. Do not limit the investigation to literals with a decimal point: `1e300` is also wrong.
- [ ] **Step 2: Minimal repro.** Record a minimal Z98 program and the exact `--dump-c89` command showing `0.366025403784439` emits `3.660254037844391e-1` and `-0.16666666666666666` emits `1.6666666666666669e-1`.
- [ ] **Step 3: Correct-value table.** Establish round-to-nearest-even values against an independent oracle (`gcc -m32 -std=c89` `strtod` and/or Python `float`), including at least:
  - `0.366025403784439` -> `3fd76cf5d0b0995b`
  - `-0.16666666666666666` -> `bfc5555555555555`
  - `1e300` / `1.0e300` -> `7e37e43c8800759c`
  - `1e-308` -> `000730d67819e8d2`
  - `0.3` -> `3fd3333333333333`
  - `0.75` -> `3fe8000000000000`
  - `1.75` -> `3ffc000000000000`
- [ ] **Step 4: Inventory.** Scan decimal float literals under `sf/src`, `examples/z98`, `repro/mi_matrix`, and `stdlib_test`; list every mismatch with file:line, literal, current bits, correct bits, and impact class. Baseline to confirm: 1,061 literals, 240 mismatches, 13 files (recompute, do not trust this summary).
- [ ] **Step 5: Migration list.** Identify every fixture, golden, exact pin, dump pin, app source, and seed artifact that must change in Tasks 1C/1D. Separate definite failures from rerun-only cases.
- [ ] **Step 6: Commit report.** `docs(sdd): M2 T1A investigation report`. No code changes.

### Task 1AEx: Decimal→f64 Algorithm Methodology Decision (derivative of blocked Task 1)

**Files:**
- Create: `.superpowers/sdd/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan/task-1aex-report.md`
- No source, fixture, seed, or tracked-file edits.

**Interfaces:**
- Consumes: Task 1A root cause + bit table; `sf/src/lexer.zig` `parseF64` (current algorithm).
- Produces: selected algorithm with full tradeoff analysis, implementation blueprint for Task 1B.

- [ ] **Step 1: Survey modern approaches.** Study at minimum: (a) Clinger fast path + bignum fallback (glibc `strtod`, musl `strtod`); (b) Eisel-Lemire 2020 (Rust `str::parse::<f64>`, Go `ParseFloat`); (c) simple big-integer (digits→limbs, exact `significand × 10^exp`, single rounding); (d) x87 80-bit extended (PII/PIII native); (e) Steele & White / Dragon inverse. RECOMMEND the best available modern approach — no need era-accurate; leverage modern techniques.
- [ ] **Step 2: PII/PIII tradeoffs.** For each approach: code size (Z98→C89, no u128/generics/libc), stack/arena usage (worst-case 800-digit literals), speed (fast-path hit rate vs fallback on 200–400 MHz), precision guarantee (must be correctly rounded for ALL f64), implementation complexity in Z98 (no `@bitCast` for f64, limited integer types).
- [ ] **Step 3: How C solves it.** Trace glibc `strtod` and musl `strtod` — identify exact algorithm, which parts depend on libc/platform.
- [ ] **Step 4: How Zig solves it.** Trace `std.fmt.parseFloat` — is it correctly rounded? What does it guarantee?
- [ ] **Step 5: Conclusion.** One algorithm recommended with: justification for PII/PIII + 16–32 MB RAM; proof sketch of correct rounding (or explicit "correct for all f64" argument); implementation blueprint for Task 1B (data structures, edge cases, estimated code size); why no further rounding fixes will be needed.
- [ ] **Step 6: Commit report.** `docs(sdd): M2 T1AEx methodology report`. No code changes.

### Task 1Bp: Lexer f64 fix — pre-implementation edit plan (derivative of blocked Task 1)

**Files:**
- Create: `.superpowers/sdd/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan/task-1bp-report.md`
- No source, fixture, seed, or tracked-file edits.

**Interfaces:**
- Consumes: Task 1A bit table; Task 1AEx algorithm blueprint (§5).
- Produces: exact edit plan for Task 1B — what to change, where, how, with full code sketches.

- [ ] **Step 1: Read `parseF64` at `sf/src/lexer.zig:610-668`.** Identify every variable, every accumulation step, every rounding point. Map each to its replacement in the 1AEx algorithm.
- [ ] **Step 2: Specify the new algorithm in full detail.** For each helper function (digit accumulation, integer multiply by 5^k, integer divide by 5^k, RNE rounding, f64 bit assembly): exact Z98 signature, exact data structures (u64 limb pairs, u32 arrays), exact control flow. Include edge cases: zero, subnormal, overflow to inf, underflow to zero, denormal boundary, tie-to-even, 800-digit truncation.
- [ ] **Step 3: Specify the exact edit to `sf/src/lexer.zig`.** Which lines to delete, which to insert, where helpers go (before or after `parseF64`). Include the full replacement code for `parseF64` body.
- [ ] **Step 4: Specify the fixture.** Exact `main.zig` content (literal list, expected bit checks, output format `lexer float round ok`), exact `expected.txt`, exact `expected.rc`.
- [ ] **Step 5: Specify verification commands.** Exact commands and expected outputs for: fixture RED before fix, fixture GREEN after fix, `lexer_float_exponent_xmod`, compiler self-build.
- [ ] **Step 6: Commit report.** `docs(sdd): M2 T1Bp edit plan`. No code changes.

### Task 1B: Lexer f64 rounding — fix (minimal repro + correct values)

**Files:**
- Modify: `sf/src/lexer.zig`
- Create: `repro/mi_matrix/lexer_float_rounding_xmod/{main.zig,expected.txt,expected.rc}`
- Create: `.superpowers/sdd/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan/task-1b-report.md`

**Interfaces:**
- Consumes: Task 1Bp edit plan (exact code sketches and edit locations).
- Produces: correctly rounded decimal `f64` parsing; the new fixture is the permanent regression pin.

- [ ] **Step 1: Write the failing fixture.** `lexer_float_rounding_xmod` checks the exact bit patterns from Task 1A, including the mantissa and exponent cases, and prints `lexer float round ok` with rc 0 only when all match. Run it before the fix and record the failure.
- [ ] **Step 2: Fix `parseF64`.** Implement correctly rounded decimal-to-f64 for both mantissa and exponent, round-to-nearest-even, with no libc `strtod`, no platform-specific dependency, and no new language surface. Do not just compensate with adjacent literals.
- [ ] **Step 3: Verify.** Fixture passes; existing `lexer_float_exponent_xmod` still passes; compiler self-build succeeds. Record exact commands and bits.
- [ ] **Step 4: Commit** `fix(lexer): correctly round decimal f64 literals`, then `docs(sdd): M2 T1B report`.

### Task 1F: formatF64 non-finite emission + precision digits (operator-authorized)

**Files:**
- Modify: `sf/src/util/format.zig` (`formatF64`)
- Modify: `repro/mi_matrix/lexer_float_rounding_xmod/` (restore inf rows)
- Create: `.superpowers/sdd/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan/task-1f-report.md`

**Interfaces:**
- Consumes: Task 1B fixed `parseF64` (correctly returns ±inf on overflow).
- Produces: `formatF64` emits C89-valid inf/nan; fixture validates overflow end-to-end.

- [ ] **Step 1: Fix `formatF64` non-finite emission.** Map `+inf` → `HUGE_VAL`, `-inf` → `-HUGE_VAL`, NaN → `NAN` (or `0.0/0.0` fallback). These are C89 `<math.h>` constants. If `<math.h>` not available in emitted code, use `__builtin_inf()`/`__builtin_nan()` as fallback. The comment "There is no valid C89 literal for inf/nan" is wrong — `HUGE_VAL` exists.
- [ ] **Step 2: Verify precision digits.** Confirm `formatF64` generates enough decimal digits to round-trip f64 (17 significant digits). If it already does, record evidence. If not, fix.
- [ ] **Step 3: Restore inf rows in fixture.** Re-add `1e309` → `7ff0000000000000` and `-1e309` → `fff0000000000000` to `lexer_float_rounding_xmod` (replacing the max-finite workaround rows). Verify fixture GREEN with inf rows.
- [ ] **Step 4: Verify.** Fixture passes with all rows including inf; `lexer_float_exponent_xmod` passes; compiler self-build succeeds. Record exact commands and bits.
- [ ] **Step 5: Commit** `fix(format): emit C89 HUGE_VAL/NAN for non-finite f64`, then `docs(sdd): M2 T1F report`.

### Task 1C: Migrate z9play to corrected rounding + full battery + seed rotation

**Files:**
- Modify only as measured: z9play exact goldens/pins (`examples/z98/z9play/testdata/expected/*.pcm`, `tests/tier_decode.sh`, `tests/tier_stream.sh`), z9play docs dump pins (`README.md`, `NOTES.md`, `docs/sf/QUICK_REF.md`), and `scripts/seed/archive_seed.sh` interim count `33` -> `34`.
- Create: `.superpowers/sdd/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan/task-1c-report.md`
- Seed: `release/seed/zig1-seed.tgz`, `release/seed/CHANGELOG.md` (via archive script).

**Interfaces:**
- Consumes: Task 1B fixed compiler.
- Produces: z9play artifacts consistent with the corrected `floor.zig` table; first lexer-fix seed rotation.

- [ ] **Step 1: Rebuild.** Build a fresh compiler from the fixed source; record its binary md5 and fixed point.
- [ ] **Step 2: Full battery.** Run the full compiler battery (corpus class, goldens 5/5, mi_matrix 25+oob, examples 26/26 build+run, stdlib, seed hop, 8 pins, markers) plus all z9play tiers (`info`, `setup`, `cli`, `tui`, `audio`, `decode`, `flac`, `stream`, `win9x`). Record every mover old -> new.
- [ ] **Step 3: Migrate z9play.** Update only artifacts proven to move: exact PCM/WAV goldens and pins, `--dump-c89` pins, and docs. Do not edit `floor.zig` unless Task 1A proves a workaround literal; the table is already the spec decimal text.
- [ ] **Step 4: Interim seed count.** Update `archive_seed.sh` hardcoded count/prose to 34 (std_noise is already in the copy list); Task 3 later takes it to 35.
- [ ] **Step 5: Rotate seed.** `bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`; record archive md5, manifest, binary md5, fixed point.
- [ ] **Step 6: Commit** `example(z9play): migrate to correctly rounded f64 literals`, `chore(seed): rotate v104 (lexer f64)`, then `docs(sdd): M2 T1C report`.

### Task 1D: Restore canonical std_noise + re-baseline + second seed rotation

**Files:**
- Modify: `sf/src/std_noise.zig` (canonical literals), `repro/mi_matrix/stdlib_noise_basic_xmod/expected.txt` (PGM hash), `sf/docs/std_lib/noise.md`, `examples/torrent_example_defects.md` (D6 status), `docs/sf/QUICK_REF.md`/seed docs as needed.
- Verify unchanged: `scripts/stdlib/vectors/std_noise/grid.expected` (should stay the reference output).
- Seed: `release/seed/zig1-seed.tgz`, `release/seed/CHANGELOG.md` (via archive script).
- Create: `.superpowers/sdd/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan/task-1d-report.md`

**Interfaces:**
- Consumes: Task 1B fixed lexer; Task 1C rotated seed v104.
- Produces: canonical `std_noise`; unblocked Task 1.

- [ ] **Step 1: Restore canonical literals.** Replace the workaround `0.3660254037844389` and `-0.16666666666666664` with `0.366025403784439` and `-0.16666666666666666`; remove the compensating comment.
- [ ] **Step 2: Re-baseline noise.** Run `verify_stdlib` and `run_crosscheck std_noise` 3x; confirm `grid.expected` is unchanged and re-capture only the `stdlib_noise_basic` PGM hash.
- [ ] **Step 3: Truth-up.** Mark D6 FIXED in `examples/torrent_example_defects.md`; update noise docs and QUICK_REF counts/pins. “Rebase” here means re-baseline fixtures/pins, never `git rebase`.
- [ ] **Step 4: Rotate seed again.** Rotate v105 with the canonical std_noise; record archive md5, manifest, binary md5, fixed point (must equal Task 1C’s fixed point).
- [ ] **Step 5: Unblock.** After the gate is green, mark Task 1 complete in the ledger and resume Task 2. Commit `fix(std_noise): restore canonical f64 literals after lexer fix`, `chore(seed): rotate v105 (std_noise canonical)`, then `docs(sdd): M2 T1D report`.

### Task 2: `std_lz4` — LZ4 block decoder

**Files:**
- Create: `sf/src/std_lz4.zig`
- Create: `scripts/stdlib/ref/std_lz4/ref.c` (vendored `LZ4_decompress_safe`, BSD attribution)
- Create: `scripts/stdlib/vectors/std_lz4/*.{in,expected}` (`.in` = raw block bytes; expected text; host `lz4` generated)
- Create: `repro/mi_matrix/stdlib_lz4_{basic,cross}_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`, seed copy lists

**Interfaces:**
- Consumes: none (L4, imports L0–L2 only).
- Produces: `std_lz4.lz4DecompressBlock(src: []const u8, dst: []u8) !u32` — `error.Corrupt` / `error.OutputTooSmall`.

- [ ] **Step 1: Write failing fixtures.** `stdlib_lz4_basic_xmod`: round-trip vs host-`lz4` corpus (text/binary/already-compressed), empty block → 0, all-literals block, truncations + bit-flips → `error.Corrupt`, dst-too-small → `error.OutputTooSmall`, end-rule violations (last-match <12 from end) → `error.Corrupt`.
- [ ] **Step 2: Run — FAIL (module absent).**
- [ ] **Step 3: Implement decoder** — token split 4+4; literal/match length extension loops (15→+255…); match offset LE u16; overlap-safe copy; bounds checks before every write/read.
- [ ] **Step 4: Crosscheck green.** `.in` = raw LZ4 block bytes. `stdlib_lz4_cross_xmod --crosscheck` reads all stdin, decodes into a fixed 64 KiB destination, and prints exactly one line: `ok <bytes_written>` on success or `corrupt` on `error.Corrupt`; it always exits 0. The vendored ref wrapper uses the same 64 KiB destination and maps a negative `LZ4_decompress_safe` result to `corrupt`, also exiting 0. Vectors = valid host-`lz4` blocks + truncations; `error.OutputTooSmall` is covered only by the unit fixture (dst smaller than the decoded size).
- [ ] **Step 5: Gates + commit.** `feat(std_lz4): LZ4 block decoder (M2)`.

### Task 3: M2 closeout — usage, docs, truth-ups, seed rotation

**Files:**
- Create: `stdlib_test/noise_lz4_usage/{main.zig,expected.txt,expected.rc}`
- Create: `sf/docs/std_lib/noise.md`; Modify: `sf/docs/std_lib/codecs.md` (lz4 section)
- Modify: `STD_README.MD` (domain table + doc-index rows for `std_rand`, `std_noise`, `std_lz4`)
- Modify: `README.md` (higher-layer module list: `std_noise`, `std_lz4`)
- Modify: `docs/sf/QUICK_REF.md` (current std set/count and install recipe: `std_noise`, `std_lz4`)
- Modify: `scripts/seed/archive_seed.sh` (hardcoded `33` text → `35`; module comment/list)
- Modify: `scripts/seed/build_from_seed.sh` (stale `32` std-lib comment → `35`)
- Modify: `scripts/stdlib/expected_dirs.txt` (new usage + fixture dirs)
- Modify: `release/seed/CHANGELOG.md` (via archive script)

- [ ] **Step 1: Usage program.** `stdlib_test/noise_lz4_usage` uses `std_rand.xoshiroInit` to seed `std_noise.opensimplexInit`, asserts `noise2d`/`noise3d` are in `[-1, 1]`, asserts two identical inits produce identical samples, asserts `noiseFbm2d(..., octaves=0) == 0.0`, and decodes one embedded valid all-literals LZ4 block with `std_lz4.lz4DecompressBlock` (fixed seed/inputs; no clock/env). It prints deterministic summary lines ending `noise_lz4 ok`; commit `expected.txt`/`expected.rc` captured from the passing program.
- [ ] **Step 2: Docs** — noise API + fBm params + pinned 2014 reference behavior (seed-0 lattice values; blueprint zero-at-lattice claim superseded); lz4 contract + offline-compress workflow.
- [ ] **Step 3: Truth-ups.** Update `STD_README.MD` domain table and doc-index list with `std_rand`/`rand.md`, `std_noise`/`noise.md`, `std_lz4`/`codecs.md`; update root `README.md` higher-layer list; update `docs/sf/QUICK_REF.md` current std count/install recipe; update the hardcoded `33` texts in `scripts/seed/archive_seed.sh` to `35`, its module comment/list, and the stale `32` comment in `scripts/seed/build_from_seed.sh`.
- [ ] **Step 4: Rotate seed** — archive + manifest (35 files); binary md5 + fixed point unchanged.
- [ ] **Step 5: Full gate re-run + commits** (`docs(std_lib): noise + lz4 docs (M2)`, `chore(seed): rotate (M2)`).
