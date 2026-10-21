# Noise — `std_noise`

| | |
|---|---|
| **Modules** | `std_noise` |
| **Layers** | `L5` — pure algorithm layer: deterministic noise; allocates nothing |
| **Import (by path)** | `const std_noise = @import("std_noise.zig");` |
| **Consumes** | `std_rand` (xoshiro256\*\* Fisher–Yates permutation) |

`std_noise` is not re-exported through `std`; import it by path.

## Module overview

`std_noise` is Kurt Spencer's **2014 OpenSimplex Noise v1.1** (October 5, 2014,
`github.com/KdotJPG/OpenSimplexNoise`, preserved in
`OpenSimplexNoise-for-Processing/src/algorithms/noise/OpenSimplexNoiseKS.java`)
— the 2014 algorithm, **NOT OpenSimplex2**. The 2014 reference is authoritative
for the lattice behavior: at seed 0, `(0,0)` is zero while `(1,0)`, `(0,1)`,
`(1,1)` are nonzero (blueprint §5.5 zero-at-integer-lattice is superseded).

Contract (blueprint §3 L5): alloc none | errors none | coroutine no. State is
fixed at **512 bytes** (`perm: [256]u8` + `perm_grad: [256]u8`) built by
`opensimplexInit` with `std_rand`'s xoshiro256\*\* Fisher–Yates permutation
(`perm_grad[i] = (perm[i] % 24) * 3`). No heap, clock, env, PID or address
input — same seed and coordinates always give the same samples.

**f64 throughout.** Do not substitute Perlin gradients or f32 intermediates: an
f32 shortcut survives the unit tests and fails the visual golden. 2D uses the
eight compass gradients; 3D uses the 24 rhombicuboctahedron gradients.

## Canonical constants (pinned)

The 2D skew/squish and 3D stretch constants are the canonical 2014-reference
decimal spellings. Since M2 T1B (correctly-rounded `parseF64`) + T1D (literal
restore) these parse bit-exactly; the earlier adjacent-literal workaround
(`0.3660254037844389` / `-0.16666666666666664`) is **removed** and must not
come back (defect D6 in `examples/torrent_example_defects.md`, FIXED).

| constant | literal | IEEE-754 bits (f64) |
|---|---|---|
| `STRETCH_CONSTANT_2D` | `-0.211324865405187` | `bfcb0cb174df99c3` |
| `SQUISH_CONSTANT_2D` | `0.366025403784439` | `3fd76cf5d0b0995b` |
| `STRETCH_CONSTANT_3D` | `-0.16666666666666666` | `bfc5555555555555` |
| `SQUISH_CONSTANT_3D` | `0.3333333333333333` | `3fd5555555555555` |
| `NORM_CONSTANT_2D` | `47.0` | exact |
| `NORM_CONSTANT_3D` | `103.0` | exact |

**Lattice pin (2014 reference, seed 0):** `noise2d(0,0) == 0` (bits
`0000000000000000`); `noise2d(1,0) = 0.42680000932807705` (bits
`3fdb50b0fc7fc810`); `noise2d(0,1) = -0.061333742599571035` (bits
`bfaf6722e5367f41`); `noise2d(1,1) = -0.62215238898136926` (bits
`bfe3e8ac2079b43d`). These are the authoritative 2014-reference values
(blueprint §5.5's zero-at-integer-lattice claim is superseded). The crosscheck
grid (`scripts/stdlib/vectors/std_noise/grid.expected`, md5
`94314ebd32053089b226387770c0cd5d`) is the reference output and must stay
unchanged when the compiler or parser moves.

## Quick start

Seed a generator, sample 2D/3D noise, and sum an fBm octave stack.

```zig
const std = @import("std");
const std_noise = @import("std_noise.zig");

pub fn main() void {
    var n = std_noise.opensimplexInit(0xDEADBEEF);
    std.io.print("{}\n", .{std_noise.noise2d(&n, 1.25, -0.5)});
    std.io.print("{}\n", .{std_noise.noise3d(&n, 1.25, -0.5, 0.25)});
    std.io.print("{}\n", .{std_noise.noiseFbm2d(&n, 1.25, -0.5, 4, 2.0, 0.5)});
}
```

## API

### `std_noise`

#### `OpenSimplex`

**Purpose** — the 2014 OpenSimplex permutation state.

**Signature** — `pub const OpenSimplex = struct { perm: [256]u8, perm_grad: [256]u8 };`

**Parameters** (fields)
- `perm` — xoshiro Fisher–Yates permutation of `0..255`.
- `perm_grad` — gradient index table: `perm_grad[i] = (perm[i] % 24) * 3`.

**Returns** — a plain 512-byte value type; `opensimplexInit` returns one by value.

**Errors** — none.

**Gotchas** — initialize with `opensimplexInit`; a hand-written `perm` skips the
seeded shuffle. Copying the struct copies the generator (same samples).

#### `opensimplexInit`

**Purpose** — seeds a 2014 OpenSimplex state via `std_rand` xoshiro256\*\*
Fisher–Yates.

**Signature** — `pub fn opensimplexInit(seed: u64) OpenSimplex`

**Parameters**
- `seed` — any `u64`; drives the permutation only.

**Returns** — an `OpenSimplex` ready for `noise2d`/`noise3d`/`noiseFbm2d`.

**Errors** — none.

#### `noise2d`

**Purpose** — 2D OpenSimplex noise at `(x, y)`.

**Signature** — `pub fn noise2d(n: *const OpenSimplex, x: f64, y: f64) f64`

**Parameters**
- `n` — seeded state.
- `x`, `y` — sample coordinates (f64).

**Returns** — `f64` in `[-1, 1]`; bit-reproducible for the same state and
coordinates.

**Errors** — none.

#### `noise3d`

**Purpose** — 3D OpenSimplex noise at `(x, y, z)` (24 rhombicuboctahedron
gradients).

**Signature** — `pub fn noise3d(n: *const OpenSimplex, x: f64, y: f64, z: f64) f64`

**Parameters**
- `n` — seeded state.
- `x`, `y`, `z` — sample coordinates (f64).

**Returns** — `f64` in `[-1, 1]`.

**Errors** — none.

#### `noiseFbm2d`

**Purpose** — fractal Brownian motion over `noise2d`: an octave stack with
per-octave frequency and amplitude scaling.

**Signature** — `pub fn noiseFbm2d(n: *const OpenSimplex, x: f64, y: f64, octaves: u8, lacunarity: f64, gain: f64) f64`

**Parameters**
- `n` — seeded state.
- `x`, `y` — base coordinates.
- `octaves` — octave count; `0` returns exactly `0.0`.
- `lacunarity` — per-octave frequency multiplier.
- `gain` — per-octave amplitude multiplier.

**Returns** — `f64` sum `Σ amplitude_i * noise2d(x*freq_i, y*freq_i)`.

**fBm parameters (exact stack)** — the loop starts at `frequency = 1.0` and
`amplitude = 1.0`; for each of `octaves` iterations it adds
`amplitude * noise2d(x*frequency, y*frequency)`, then multiplies
`frequency *= lacunarity` and `amplitude *= gain`. The sum is **not**
normalized by the total amplitude (`Σ gain^i`), so larger `gain` values raise
the output magnitude; keep the composed value in `[-1, 1]` yourself when a
bounded signal is required. `lacunarity` and `gain` are plain `f64` (no
clamping), and `octaves == 0` returns exactly `0.0` before touching either.

**Errors** — none.

**Gotchas** — negative `lacunarity`/`gain` are accepted and applied verbatim;
they are not validated. Choose `lacunarity > 1` and `0 < gain < 1` for the
conventional octave stack.

## Gates and pins

| gate | command | pin |
|---|---|---|
| crosscheck grid | `scripts/stdlib/run_crosscheck.sh <zig1> std_noise` | Z98 == C89 ref == `scripts/stdlib/vectors/std_noise/grid.expected` (md5 `94314ebd32053089b226387770c0cd5d`) |
| basic fixture | `scripts/stdlib/run_fixtures.sh <zig1> repro/mi_matrix/stdlib_noise_basic_xmod` | stdout byte-exact; PGM visual golden `pgm fnv1a64 4921c94f3ec08543` (256×256 from `noiseFbm2d`) |
| cross fixture | `scripts/stdlib/run_fixtures.sh <zig1> repro/mi_matrix/stdlib_noise_cross_xmod` | stdout byte-exact |
| usage program | `scripts/stdlib/run_fixtures.sh <zig1> stdlib_test/noise_lz4_usage` | stdout byte-exact, ends `noise_lz4 ok` |
| full std gate | `scripts/stdlib/verify_stdlib.sh <zig1>` | `STDLIB GATE OK` (fixtures + all crosscheck modules) |

Reference implementation: `scripts/stdlib/ref/std_noise/ref.c` (2014
OpenSimplex port, attribution header). Crosscheck `.in` lines are
`2 <seed> <x> <y>` or `3 <seed> <x> <y> <z>` (decimal); the driver prints the
16 lowercase hex digits of the returned f64 bit pattern and always exits 0.
`noiseFbm2d` is covered by the basic fixture/visual golden, not the crosscheck.
