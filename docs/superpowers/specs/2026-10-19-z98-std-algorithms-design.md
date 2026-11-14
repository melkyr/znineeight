# Z98 Standard Library: Modern Algorithm Additions — Program Design

**Date:** 2026-10-19 (amended 2026-10-19 after builder-check + operator rulings)
**Status:** binding spec for the std-algorithms milestone series (M1–M7)
**Source blueprint:** `docs/sf/std_additions.txt` (operator-provided; this spec
adapts it to the landed std-lib architecture)
**Companion plans:** `docs/superpowers/plans/2026-10-19-z98-std-algorithms-m{1..7}-*.md`
(one per milestone; each plan is the authority for its own task steps)

---

## 0. Intent and why

The era's programmers hand-rolled hash tables, RNGs, and sorts in every
project. Z98's std should carry the post-1998 algorithm set that shows up in
more than one project — tested once, checked by the compiler, shared across
game/simulation/CLI code. This program adds those algorithms to the existing
std (the L0–L6 layered library from
`docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md`), in
strictly forward-dependent milestones so no milestone ever reworks an earlier
one's surface.

## 1. Inclusion tests (from blueprint §0, binding)

Every addition must pass all four:

1. **Published after 1998** — else the era had it.
2. **Well-understood today** — stable formulation + reference implementation.
3. **Fits the target** — 16–32 MB RAM, Pentium II/III, C89 output, no unwinder,
   no GC, no threads.
4. **Cross-project** — a game, a simulation, and a CLI tool each benefit.

Failures excluded regardless of interest: neural nets (4), arbitrary-precision
(3), real-time ray tracing (2).

## 2. Scope and reconciliation with the landed std

The blueprint was written against a hypothetical library. Decisions where it
collides with what already exists (operator-confirmed 2026-10-19):

| Blueprint | Decision | Why |
|---|---|---|
| §9 `std.sort` introsort | **RETIRE — no work.** Already landed as `sf/src/std_sort.zig` (297 ln; median-of-3, `2*log2(n)` depth limit, heapsort fallback, insertion cutoff, `binarySearchU32`). Superset of the ask. | Nothing to add. |
| §3 `std.heap` Robin Hood | **In-place `std_map.zig` internals upgrade.** Names/API (`Map32x32`/`Map32Ptr`/`MapStrPtr`, `map32x32{Init,Get,Put,Remove,Len}` family) unchanged. Blueprint's `RobinHoodMap`/`rh_*` names discarded. `std_heap.zig` (min-heap) keeps its name. | No `std.heap` collision; zero caller churn; the deletion-churn + probe-variance win lands where the maps live. |
| §3 Swiss table (SIMD) | **INTENTIONALLY OUT of this program — deferred to a future asm-backend program** (operator ruling 2026-10-19). Rationale: (a) Swiss's real win is the 16-way SIMD probe; C89 output cannot emit it; (b) target PII/PIII lacks SSE2 entirely — blueprint's cited `_mm_cmpeq_epi8` is SSE2 = Pentium 4+, so the blueprint's own justification contradicts its target; PII/PIII SIMD = MMX `pcmpeqb`, which still requires an asm backend; (c) scalar-simulated Swiss (16-byte ctrl groups scanned with a loop) only wins on lookup-heavy maps large enough that dense ctrl metadata beats per-slot probes — niche vs Robin Hood, which already serves test 4. The M1 ctrl-byte encoding keeps the future Swiss path open without a reshape. | No usual case until asm exists. |
| §1 testing `tests/<module>/{vectors,ref,run.sh,...}` | **Adapt the landed harness**, don't fork a second tree: `scripts/stdlib/run_fixtures.sh` + `verify_stdlib.sh` + `expected_dirs.txt` pin stay the one gate; add `vectors/` + `ref/` + `run_crosscheck.sh` (§5). `run_win.sh`/`run_win98.md` = written convention only (all new modules are pure logic; no per-module Win tiers). | One pin gate; the genuinely new piece is the C89-reference cross-check. |
| §2.5 statistical tests (chi-squared, serial correlation) | **INCLUDE** (operator ruling) — one fixture `stdlib_rand_stat_xmod` (fixed seed, hardcoded thresholds; §6.1). Known-answer/seeding/advance tests land as the M1 unit fixtures. | Blueprint names them Tier 1. |
| §8 `std.compress` LZ4 block | **New `std_lz4.zig`**, decoder-only (compress offline with host `lz4`). `std_rle.zig` untouched (different codec). | Blueprint-exact. |
| (not in blueprint) zstd | **Added `std_zstd.zig`** (operator): decoder-only, RFC 8878 subset, window cap **caller-overridable** (§6.4). | 2013+/RFC-stable; real-world `.zst` assets. |
| §2.3 snake_case fns | House style camelCase (`pcg32Init`, `noise2d`, …). Files `std_<name>.zig`. | Match landed std. |
| §2.5/§1 `Z98_SEED` | **Caller-side convention, never inside std.** R6 (no clock/env in std) is binding; std APIs take explicit `seed: u64`. Harness exports fixed `Z98_SEED`; test/demo programs read it via `std_os.env` and pass it down; fallback fixed default when absent. Production caller derives a seed (e.g. clock) in user code. | R6 wins; blueprint's own signatures already take seeds. |
| Example adoption | **Std-only program** (operator ruling): no example (z9play/z9torr/…) adopts new modules here; affected-example tiers are empty by construction. Adoption is a future example-side choice. | Keeps milestones lean; std gates cover the modules. |

Excluded/deferred (each one line, not silently): `sort_f32`/`sort_by` extras
(YAGNI; `Sortable` vtable covers custom order), pdqsort refinement (blueprint
§9 "later"; introsort landed), HPA* is **in scope** (M7), Swiss table (above),
zstd dictionaries (§6.4), PBD collision constraints (blueprint §6.4 v1 skip),
LZ4/zstd compressors (decoder-only by design).

## 3. Global constraints

- **Layering (R3 amendment).** New pure-algorithm modules join a new **L5
  band**. L5 may import L0–L4 freely and other L5 modules **only along the
  program dependency order** (§7) — a DAG, never a cycle. `std_lz4`/`std_zstd`
  join **L4 codecs** (import L0–L2 only, like `std_rle`). `std.zig` is NOT
  modified (Ruling F1 pattern: import by path).
- **Determinism (R6).** No output may depend on addresses, wall clock, PID, or
  env from inside std. Same input + same seed ⇒ same output, every run.
- **No generics.** Concrete instantiations only (`Map32x32` pattern); free
  functions; no method syntax; no vtables unless the caller wants one
  (`Sortable` pattern).
- **Allocation.** Caller-supplied `*std_arena.Arena` at init where tables are
  sized (map pattern); no hidden heap; `error.OutOfMemory` when a fixed
  capacity is exhausted (existing map semantics preserved). Decoder modules
  (`std_lz4`, `std_zstd`) allocate nothing — function-local scratch only.
- **Target.** C89 output, 32-bit (`usize` = 4 B), 16–32 MB RAM, PII/PIII.
  State sizes: `Pcg32` 16 B, `Xoshiro256` 32 B, `OpenSimplex` 512 B.
- **Z98 constraints.** Subset per `docs/sf/AGENTS.md` §1.3; proven shapes used:
  array struct fields (`std_crypto.zig:49`), fn-ptr fields/params
  (`player.zig:69`, `fnptr_opt_aggregate_*` fixtures). No new compiler
  features; no `sf/src` compiler-pipeline edits.
- **Preconditions** (signatures can't carry these as errors): `bound == 0` in
  `pcg32Bounded`/`xoshiroBounded` and `pbdAddParticle`/`pbdAddDistance` over
  init counts = caller bug → `@panic`. `noiseFbm2d` with `octaves == 0`
  returns `0.0`. `rk45Step` error set is exactly `error.StepTooSmall`.

## 4. Gate and seed-rotation contract (operator-ruled 2026-10-19)

The compiler does not import `std_*` (`main.zig` import graph is compiler-only)
— std changes cannot move self-emission. Therefore:

**RUN per milestone gate:**
1. `bash scripts/stdlib/verify_stdlib.sh <zig1>` — full fixture set green,
   `expected_dirs.txt` pin updated for new fixtures (existing ones stay
   byte-identical; see §6.2 for the map-golden default).
2. `bash scripts/stdlib/run_crosscheck.sh <zig1>` — every module with a
   `ref/` cross-checks green (§5). Also runs as part of `verify_stdlib.sh`
   (discovery: any `scripts/stdlib/ref/<module>/` dir).
3. Usage programs `stdlib_test/<module>_usage/` (R7b pattern) build + run.
4. Determinism: affected randomized tests re-run 3× byte-identical.
5. **Affected-example tiers: none** (std-only program, §2). The mechanism
   stays available for defense (any future example importing changed std).

**SKIP (zero coupling, stated here so tasks never re-litigate):** corpus
classify / frozen-1124 md5, goldens 5/5, full examples 26/26 matrix, non-std
mi_matrix `*_xmod` fixtures, the 8 `--dump-c89` pins, markers telemetry, seed
hop/closure measurement.

**Seed rotation: YES at each milestone closeout.** The archive packs compiler
src + std as one artifact (`zig1-seed.tgz` = `gen/` + `runtime/` + `lib/`);
a std change is an archive change (M7-precedent: v102 archive md5 moved,
binary/fixed point held). Each closeout runs
`bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`
and records:
- archive md5 (moves),
- **`lib/manifest.md5` (NEW)** — per-file md5 of every `lib/*.zig`, generated
  into the archive and listed in the CHANGELOG entry (the std attribution
  pin),
- binary md5 + self-emission fixed point (must be UNCHANGED — the
  zero-coupling proof).

**Script touch per milestone:** the std copy lists in
`scripts/seed/build_from_seed.sh:146` and `scripts/seed/archive_seed.sh:115`
gain each new `std_*.zig` (script-only; produced compiler's `lib/` then
resolves `@import("std_<new>.zig")` binary-relatively). Milestone gate
includes an import-resolvability check proving it.

**Compiler defects** found while writing std code go to
`examples/torrent_example_defects.md` (D3/D4/D5 open; next free slot), not to
ad-hoc fixes.

## 5. Testing substrate (adapted, lands in M1)

Blueprint §1's cross-check pattern, folded into the landed harness:

- **`vectors/`** — committed input/output pairs (`<name>.in` + `<name>.expected`),
  never regenerated by a test run. Location: `scripts/stdlib/vectors/<module>/`.
  Text for scalar modules; raw binary for codecs (compared with `cmp`).
- **`ref/`** — reference implementation in C89, compiled once at setup with
  `gcc -m32 -std=c89 -O0`. Location: `scripts/stdlib/ref/<module>/ref.c`. The ref
  is not the authority; **agreement between the two implementations is** —
  enforced as a three-way compare: Z98 stdout == ref stdout == committed
  `.expected`. Exception (§6.4): `std_zstd` has no `ref/` — the host `zstd` CLI is
  the reference at vector-generation time; committed `.expected` files are the
  frozen agreement.
- **Crosscheck driver** — one fixture per cross-checked module:
  `repro/mi_matrix/stdlib_<module>_cross_xmod/`. Default mode = golden
  self-test (fixture gate); `--crosscheck` reads stdin, prints one result line
  per input line. Registered in `expected_dirs.txt`.
- **`run_crosscheck.sh <zig1> [<module>...]`** — new script in
  `scripts/stdlib/`: builds each driver + ref once, feeds every
  `vectors/<module>/*.{in,expected}`, three-way compares, both processes must
  exit 0. Wired into `verify_stdlib.sh` (fixtures pass, then crosscheck pass);
  also runnable standalone.
- **Determinism rule.** Randomized modules take explicit `seed: u64` params.
  `Z98_SEED` is a user-program convention: `run_fixtures.sh` and
  `run_crosscheck.sh` export a fixed `Z98_SEED` on every invocation; usage
  programs fall back to a fixed default when the env is absent. Fixture
  programs hard-code seeds so `expected.txt` is byte-stable.
- **Win tiers.** Convention documented (`run_win.sh` = mingw/Wine smoke for
  OS-dependent modules; `run_win98.md` = manual VM procedure); no new-module
  needs them (all pure logic) — no per-module Win artifacts are built.

## 6. Module contracts

Signatures are binding; plan tasks implement exactly these. Struct field
names binding where later milestones read them.

### 6.1 `std_rand.zig` (M1, L5) — PCG32 + xoshiro256\*\*

```
pub const Pcg32 = struct { state: u64, inc: u64 };
pub const Xoshiro256 = struct { s: [4]u64 };

pub fn pcg32Init(seed: u64, stream: u64) Pcg32       // inc = (stream << 1) | 1 — odd by construction
pub fn pcg32Next(r: *Pcg32) u32                       // LCG + permutation output
pub fn pcg32Bounded(r: *Pcg32, bound: u32) u32        // rejection sampling, never % bound; bound==0 → @panic
pub fn pcg32Advance(r: *Pcg32, delta: u64) void       // O(log delta) LCG advance; ≡ delta× pcg32Next
pub fn xoshiroInit(seed: u64) Xoshiro256              // SplitMix64 expansion, exact reference match
pub fn xoshiroNext(r: *Xoshiro256) u64                // xoshiro256** core
pub fn xoshiroBounded(r: *Xoshiro256, bound: u64) u64 // rejection sampling; bound==0 → @panic
```

Two concrete types, free functions, no vtable (blueprint §2.3). Watch-fors
(blueprint §2.4, binding): rejection not modulo; `inc` odd by construction;
xoshiro single-seed expansion MUST match the reference byte-for-byte or test
vectors diverge.

Testing (blueprint §2.5, binding — operator inclusion ruling):
- Known-answer: seed `0xDEADBEEF`, 100 outputs each generator, committed hex
  vectors vs reference-implementation output.
- Seeding: same seed ⇒ identical output (two instances).
- Advance: `pcg32Advance(1000)` state == 1000 calls of `pcg32Next`.
- Bounded: rejection-bias bound check over 1M draws (chi-squared per bucket
  band), plus `stdlib_rand_stat_xmod` = chi-squared on byte frequencies
  (256 bins, 4M bytes from 1M u32s, fixed seed; pass iff `chi2 < 310.5`,
  the df=255 p=0.01 critical value committed as a constant) and serial
  correlation (Pearson r over consecutive u32s, pass iff `|r| < 0.01`).

### 6.2 `std_map.zig` upgrade (M1, L4) — Robin Hood internals

API byte-stable (existing callers: `stdlib_test/map_sort_heap_usage`, 6
`stdlib_map_*` fixtures). Internals change:

- Open addressing with **Robin Hood** insertion (swap on greater probe
  distance) and **backward-shift deletion** (no tombstone decay; deleted
  slot never left observable — `0xFE` reserved, unreachable in steady state).
- Layout: keep AoS `entries` with field names `state`/`key`/`val` (fixtures
  read them: `stdlib_map_determinism_xmod`); `state` byte uses the ctrl
  encoding `0x80` empty, `0xFE` deleted-reserved, `0x00..0x7F` = 7-bit hash
  fragment.
- Probe distance stored as `u32` (operator ruling 2026-10-19, option C):
  exact for any 32-bit table (max distance `≤ capacity-1 ≤ 2^32-2`); no wrap.
  The blueprint's u8 'provably < 255' claim is false under same-home
  clustering. Entries: 16 / 16 / 20 bytes for Map32x32 / Map32Ptr /
  MapStrPtr.
- Load factor ≤ 0.75; `Put` still `error.OutOfMemory` at caller `capacity`
  (semantics preserved: `Init`'s `capacity` = max entries; internal slots =
  next pow2 ≥ `capacity`/0.75); hash keeps existing `mix32`/string mix; index
  by mask.
- Determinism (R6): slot placement a pure function of key/capacity/ops
  sequence. **Goldens default: byte-identical** (they are assert-summary
  strings, no slot dumps). Multiset re-record is last resort only — any
  golden movement that is not `map_sort_heap_usage`-family summary lines =
  STOP-present.
- `stdlib_map_determinism_xmod` header comment truth-up (order is
  slot-ascending, not insertion-index) — comment-only fixture edit.

Watch-fors (blueprint §3.4, binding): backward-shift is not "set empty";
load factor never exceeds 0.75; ctrl encoding exact.

### 6.3 `std_lz4.zig` (M2, L4) — LZ4 block decoder

```
pub fn lz4DecompressBlock(src: []const u8, dst: []u8) !u32   // bytes written
```
Errors: `error.Corrupt` (format/truncated/invalid match), `error.OutputTooSmall`
(dst exhausted — caller sizing, distinct from corruption). Stateless;
match offset little-endian u16; length-extension loops (15→+255…); enforce
"last 5 bytes literals" + "last match not within last 12 bytes" (blueprint
§8.4) in unit fixtures (`error.Corrupt`). Ref = vendored `LZ4_decompress_safe`
(BSD, attribution header) at `scripts/stdlib/ref/std_lz4/ref.c`; crosscheck =
host-`lz4`-generated valid blocks + truncations (ref negative rc maps to one
canonical fail line). Compress offline with host `lz4` tool.

### 6.4 `std_zstd.zig` (M3, L4) — zstd frame decoder, window override

```
pub const ZSTD_DEFAULT_WINDOW_LOG: u8 = 21;   // 2 MiB — safe on 16–32 MB target

pub fn zstdDecompress(src: []const u8, dst: []u8, max_window_log: u8) !u32
```
Errors: `error.Corrupt`, `error.OutputTooSmall`, `error.WindowTooBig`
(frame's window_log > caller `max_window_log`).

- RFC 8878 subset: frame magic + raw/RLE/compressed blocks; predefined and
  custom Huffman; FSE (both literals and sequences); **no dictionaries**;
  skippable frames skipped per RFC MUST (payload never surfaced).
- **Window override (operator ruling):** the cap is a caller parameter — a
  256 MB machine passes 24–28; the default constant documents the small-box
  value. Decoder allocates nothing beyond caller `dst` (single-shot into
  `dst`; history = output; Huffman/FSE tables in function-local arrays,
  ~2–4 KB stack, no heap).
- No `ref/` crosscheck: host `zstd` CLI is the reference at vector-generation
  time; vectors + `.expected` committed once (frozen agreement). Tool acquisition
  script pattern = M8 `get_flac_tools.sh`.
- Compress offline with host `zstd` CLI.

### 6.5 `std_noise.zig` (M2, L5) — OpenSimplex

```
pub const OpenSimplex = struct { perm: [256]u8, perm_grad: [256]u8 };

pub fn opensimplexInit(seed: u64) OpenSimplex                       // perm via xoshiro Fisher–Yates
pub fn noise2d(n: *const OpenSimplex, x: f64, y: f64) f64           // [-1, 1]
pub fn noise3d(n: *const OpenSimplex, x: f64, y: f64, z: f64) f64
pub fn noiseFbm2d(n: *const OpenSimplex, x: f64, y: f64, octaves: u8, lacunarity: f64, gain: f64) f64
```
f64 internally (f32 skews produce artifacts); skew `(sqrt(3)-1)/2` and
unskew `(3-sqrt(3))/6` as precomputed literals (no runtime sqrt needed);
2D gradients = 8 compass directions, 3D = 24 rhombicuboctahedron gradients
(`perm_grad[i] = (perm[i] % 24) * 3`); do not substitute Perlin gradients
(blueprint §5.4). `octaves == 0` → `0.0`.
Ref = Kurt Spencer's **2014 OpenSimplex** (`github.com/KdotJPG/OpenSimplexNoise`
— NOT OpenSimplex2; blueprint §5 names the 2014 algorithm and the
`perm`/`perm_grad` state is that implementation's shape), ported to
`scripts/stdlib/ref/std_noise/ref.c`; vectors pin it. The 2014 reference is
authoritative: at seed 0, `(0,0)` is zero but `(1,0)`, `(0,1)`, `(1,1)` are
nonzero. Blueprint §5.5's zero-at-integer-lattice claim is superseded.

### 6.6 `std_num.zig` (M4, L5) — Dormand–Prince RK45

```
pub const Rk45Config = struct { abs_tol: f64, rel_tol: f64, min_step: f64, max_step: f64, max_steps: u32 };
pub const Rk45State = struct { t: f64, y: []f64, dy: []f64, cfg: Rk45Config };

pub fn rk45Step(state: *Rk45State, f: fn (f64, []const f64, []f64) void, dt: *f64) !void
```
Error set exactly `error.StepTooSmall` (cannot converge). FSAL (7th stage
reused); scaled RMS error norm (not max); step reject `dt *= 0.9*err^(-1/5)`,
accept grow `*1.5` capped; tableau transcribed from the Dormand–Prince
reference and verified against `dy/dt = -y` (blueprint §7.4). Explicit
method — stiff ODEs documented as out of scope. State vector caller-supplied
(not arena).

### 6.7 `std_pathfind.zig` (M5, L5) — Jump Point Search and JPS+

```
pub const Point = struct { x: u32, y: u32 };
pub const Grid = struct { tiles: []u8, width: u32, height: u32 };   // 0 = blocked, 1 = walkable

pub fn jpsFind(arena: *std_arena.Arena, grid: *const Grid, start: Point, goal: Point, out: []u32) !u32
```
Returns the full path tile count. `out` is a capacity; writes at most
`out.len/2` `(x,y)` pairs in forward order including start and goal, ignores
an odd trailing slot, and never overflows; caller detects truncation via
`2*return > out.len`. `error.NoPath`, `error.OutOfMemory`. Movement is
8-connected on a uniform-cell-cost grid: cardinal cost 10, diagonal cost 14
(integer octile); heuristic `10*max(dx,dy)+4*min(dx,dy)`; a diagonal move is
legal only when both adjacent cardinal cells are walkable (strict
corner-cutting disallowed; Harabor & Grastien, *The JPS Pathfinding System*,
SoCS 2012). `tiles` is row-major (`idx = y*width+x`); out-of-bounds or
blocked start/goal, or zero-sized grid, returns `error.NoPath`;
`start==goal` walkable returns 1. Jump as loop, not recursion (bounded
stack); open set = existing `std_heap` min-heap with composite `i64` key
`(f<<32)|(~g)` (f-tie → higher g first; no `std_heap` change). L5→L4 import
of `std_heap` is sanctioned (DAG rule §3).

```
pub const JpsPlus = struct {
    dist: []i32,   // width*height*8; order N,NE,E,SE,S,SW,W,NW
    width: u32,
    height: u32,
};

pub fn jpsPlusBuild(arena: *std_arena.Arena, grid: *const Grid) !JpsPlus
pub fn jpsPlusFind(arena: *std_arena.Arena, map: *const JpsPlus, grid: *const Grid, start: Point, goal: Point, out: []u32) !u32
```
Optional preprocessed path for static grids. `dist` stores eight signed
distances per cell: positive = next jump point, negative = wall, `0` =
blocked; direction order N, NE, E, SE, S, SW, W, NW. Preprocessing is O(8N),
arena only (32 bytes/cell), and uses the same strict no-corner-cut movement
as `jpsFind`. `jpsPlusBuild` errors `OutOfMemory`; `jpsPlusFind` has the same
`NoPath`/`OutOfMemory` errors and `out` contract as `jpsFind`. The map is
static: rebuild if `Grid.tiles` changes. `jpsPlusFind` validates
`map.width/height` and `dist.len` against `grid` (mismatch -> `NoPath`) and
uses `jpsFind`'s heap/path/out semantics. `jpsFind` remains the dynamic-grid
path.

### 6.8 `std_physics.zig` (M6, L5) — Position-Based Dynamics

```
pub const Particle = struct { pos: [3]f32, prev: [3]f32, inv_mass: f32 };   // inv_mass 0 = pinned
pub const DistanceConstraint = struct { a: u32, b: u32, rest: f32, stiffness: f32 };
pub const PbdWorld = struct {
    particles: []Particle, constraints: []DistanceConstraint, order: []u32,
    particle_count: u32, constraint_count: u32,
    gravity: [3]f32, damping: f32, iterations: u8,
    rng: std_rand.Xoshiro256,
};

pub fn pbdInit(arena: *std_arena.Arena, particle_count: u32, constraint_count: u32, seed: u64) !PbdWorld
pub fn pbdStep(w: *PbdWorld, dt: f32) void
pub fn pbdAddParticle(w: *PbdWorld, pos: [3]f32, inv_mass: f32) u32
pub fn pbdAddDistance(w: *PbdWorld, a: u32, b: u32, stiffness: f32) u32
pub fn pbdPin(w: *PbdWorld, i: u32) void
```
`particles.len`/`constraints.len`/`order.len` are capacities; `particle_count`/`constraint_count`
are used counts, and `order.len == constraints.len`. `pbdInit` allocates all three from
`arena`, zeroes them, seeds `rng = xoshiroInit(seed)`, and sets `gravity = {0,0,0}`,
`damping = 0`, `iterations = 4`. It returns `arena` OOM unchanged.
`pbdAddParticle` sets `prev = pos`, returns the slot index, and increments
`particle_count`; over capacity or negative `inv_mass` is a caller bug -> `@panic`.
`pbdAddDistance` requires `a != b` and both indices `< particle_count` (else
`@panic`), computes `rest` from the current positions at add time as
`f32(std_math.sqrt(f64(dx*dx + dy*dy + dz*dz)))`, returns the constraint index,
and increments `constraint_count`; over capacity -> `@panic`. `pbdPin` sets
`inv_mass = 0` for a live index; out of range -> `@panic`.
`pbdStep` integrates every non-pinned particle with
`new = pos + (pos-prev)*(1-damping) + g*dt²` (`dt²` scaling exact — blueprint
§6.4), then stores `prev = old pos` and `pos = new`. With `iterations == 0` it
integrates only. Each projection iteration identity-fills `order[0..constraint_count]`,
shuffles it with Fisher–Yates using `xoshiroBounded(rng, i+1)` for
`i = constraint_count-1 down to 1`, then projects constraints in `order` sequence:
`len = f32(std_math.sqrt(f64(dx*dx + dy*dy + dz*dz)))`;
`corr = (len-rest)/len * stiffness`; with `wa = inv_mass[a]`, `wb = inv_mass[b]`,
`pos[a] += dx * corr * wa/(wa+wb)` and `pos[b] -= dx * corr * wb/(wa+wb)`.
Skip a constraint when `len == 0` or `wa+wb == 0`. Zero particles is a no-op;
zero constraints integrates only. v1: no collision constraints. Stiffness is
the per-iteration fraction (1 = exact in one projection). Caller reads
`particles[i].pos` after a step.


### 6.9 `std_hpa.zig` (M7, L5) — HPA\*

```
pub const Cluster = struct { x0: u32, y0: u32, w: u32, h: u32 };
pub const AbstractNode = struct { x: u32, y: u32, cluster: u32 };
pub const AbstractEdge = struct { to: u32, cost: u32 };
pub const AbstractMap = struct {
    width: u32, height: u32, cluster_w: u32, cluster_h: u32,
    cluster_cols: u32, cluster_rows: u32,
    clusters: []Cluster, node_start: []u32,
    nodes: []AbstractNode, edge_start: []u32, edges: []AbstractEdge,
};

pub fn hpaBuild(arena: *std_arena.Arena, grid: *const std_pathfind.Grid, cluster_w: u32, cluster_h: u32) !AbstractMap
pub fn hpaFind(arena: *std_arena.Arena, m: *const AbstractMap, grid: *const std_pathfind.Grid, start: Point, goal: Point, out: []u32) !u32
```

HPA\* (Botea et al. 2004) partitions the grid into clipped
`cluster_w × cluster_h` clusters. Cluster ids are row-major; the final row and
column are clipped to the grid. `cluster_w == 0` or `cluster_h == 0` is a
caller bug (`@panic`), and `grid.tiles.len >= width*height` is a precondition.
A zero-sized grid builds an empty map.

The v1 abstract graph is exact: a **transition tile** is a walkable tile with
at least one legal 8-neighbour move to a walkable tile in a different cluster
(diagonal legality uses the strict no-corner-cut rule). One `AbstractNode` is
created per transition tile. Node ids are cluster-major, then row-major inside
the cluster; `node_start[c]..node_start[c+1]` is cluster `c`'s node range.
Every legal cross-cluster adjacency becomes directed `AbstractEdge`s both ways
with cost 10 (cardinal) or 14 (diagonal). For every pair of transition nodes in
the same cluster, `hpaBuild` computes the exact cluster-restricted
shortest-path cost with `jpsFind` on a compact cluster-local `Grid`; reachable
pairs become directed edges both ways. Fully blocked clusters contribute no
nodes. Edges are ordered by `to` ascending; `edge_start[n]..edge_start[n+1]`
is node `n`'s adjacency range. The map is arena-owned and static: rebuild it
after any `Grid.tiles` change.

`hpaFind` adds temporary `S`/`G` nodes: `S` connects to every transition node
reachable from `start` inside its cluster, every transition node reachable to
`goal` connects to `G`, and a same-cluster pair also gets a direct `S -> G`
edge. A\* uses the octile heuristic and the M5 composite heap key
`(f<<32)|(~g)`. The selected abstract path is refined by concatenating exact
cluster-local `jpsFind` paths for same-cluster segments and the single legal
step for cross-cluster edges; duplicate boundary tiles are dropped. The result
is the full tile path, including start and goal. `out` is a capacity in u32
slots: write at most `out.len/2` `(x,y)` pairs, ignore an odd trailing slot,
never overflow, and return the full tile count (caller detects truncation via
`2*return > out.len`). Blocked/out-of-bounds endpoints, `start==goal` with a
walkable tile, map/grid mismatch, and unreachable goals follow `jpsFind`
semantics (`start==goal` returns 1). `hpaFind` errors are exactly `NoPath` and
`OutOfMemory`; `hpaBuild` errors are exactly `OutOfMemory`.

`hpaBuild` leaves only map allocations in the build arena (temporary build
scratch is released before return; an OOM may consume the arena). `hpaFind`'s
`arena` is query scratch and may be reset by the caller after each call; it
must not be the arena that owns `m` if the caller resets it. A\* and refinement
are deterministic: fixed cluster/node/edge order, stable heap insertion order,
and fixed local search. Build cost is `O(sum_c k_c^2 * A_c)` worst case for
the pairwise cluster-local `jpsFind` precompute, for `k_c` transition tiles and
cluster area `A_c`; memory is arena-owned and proportional
to clusters, nodes, and edges. Classic Botea entrance-segment compression is a
future optimization; it is not part of this exact-cost v1.


## 7. Milestone division (forward-only; no back-and-forth)

| # | Content | Consumes | Why self-contained |
|---|---|---|---|
| **M1 foundation** | §5 testing substrate + `std_rand` + `std_map` upgrade (incl. `stdlib_rand_stat_xmod`) | — | Substrate first (everything else plugs in); rand is the noise/physics root; map upgrade retires existing debt while its 6 fixtures are the substrate's first customer. |
| **M2 codecs-lite** | `std_noise` + `std_lz4` | M1 (rand for noise) | Two small pure modules; independent of each other; noise validates rand under a real consumer, lz4 validates the binary-vector cross-check. |
| **M3 zstd** | `std_zstd` | M1 substrate | Big and self-contained; window-override API frozen here; nothing later depends on it. |
| **M4 numerics** | `std_num` | M1 substrate | Pure; fn-ptr callback surface frozen here. |
| **M5 pathfinding** | `std_pathfind` | M1 + existing `std_heap` | JPS; heap dependency already landed. |
| **M6 physics** | `std_physics` | M1 (rand) | PBD; endpoint of the algorithm DAG. |
| **M7 HPA\*** | `std_hpa` | M5 | Hierarchical refinement of JPS; last because it is the blueprint's only "large map" refinement still in scope. |

Deferred outside this program: Swiss table (§2 — asm-backend future),
pdqsort, `sort_f32`/`sort_by`, zstd dictionaries, PBD collisions, compressors.

No-back-and-forth argument: (a) all APIs frozen in §6 at program start; (b)
substrate complete in M1 (crosscheck/vectors/ref/determinism) — later
milestones add fixtures only; (c) dependency edges point strictly forward
(§ table); (d) gate/rotation contract (§4) is identical every milestone; (e)
map internals upgrade lands exactly once, in M1.

## 8. Resources (blueprint references, binding provenance)

- O'Neill, *PCG* (2014), pcg-random.org/paper.html — PCG32 reference.
- Blackman & Vigna, *Scrambled Linear PRNGs* (2018), arxiv 1805.01407 —
  xoshiro256\*\*; reference code xoshiro.di.unimi.it.
- Goossaert, *Robin Hood Hashing* (2013), codecapsule.com — backward-shift
  deletion.
- Collet, *LZ4 Block Format*, github.com/lz4/lz4 `doc/lz4_Block_format.md` —
  and `LZ4_decompress_safe` source (BSD) as the lz4 ref.
- RFC 8878 — zstd format; host `zstd` CLI = generation-time reference.
- Spencer, *OpenSimplex Noise* (2014), `github.com/KdotJPG/OpenSimplexNoise` —
  the 2014 algorithm (not OpenSimplex2).
- Dormand & Prince (1980) — RK45 tableau.
- Harabor & Grastien, *Online Graph Pruning* (AAAI 2011) — JPS (+ the
  authors' no-corner-cut pruning rules); Botea et al. (2004) — HPA\* (M7).
- Müller et al., *Position Based Dynamics* (2007); Jakobsen, GDC 2001.

## 9. Risks and STOP conditions

- **OpenSimplex reference behavior** (§6.5) — the 2014 reference is
  authoritative; its seed-0 `(0,0)` is zero but `(1,0)`, `(0,1)`, `(1,1)` are
  nonzero. Blueprint §5.5's zero-at-integer-lattice claim is superseded by the
  pinned reference vectors.
- **Map golden movement** — default byte-identical (§6.2); any movement not
  in the summary-line family = STOP-present.
- **zstd complexity** — Huffman+FSE is the largest single item in the
  program; M3's plan gates it behind the subset in §6.4; anything outside the
  subset (dictionaries, window > caller cap) is `error.*`, never UB.
- **Determinism traps** — any module reading clock/env/address inside std is
  a spec violation; caught by the 3× re-run gate.
- **Seed script lists** — forgetting the copy-list edit makes new modules
  un-importable from the produced compiler's `lib/`; every milestone plan
  carries the edit + an import-resolvability check.
- **Swiss re-entry** — if an asm backend ever lands, revisit the §2 deferral;
  M1's ctrl-byte encoding is the only prerequisite kept warm.
