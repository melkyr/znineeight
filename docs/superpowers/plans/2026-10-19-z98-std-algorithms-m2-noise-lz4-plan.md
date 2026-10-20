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
