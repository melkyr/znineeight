# Random — `std_rand`

| | |
|---|---|
| **Modules** | `std_rand` |
| **Layers** | `L5` — pure algorithm layer: deterministic pseudorandom generators; allocates nothing |
| **Import (by path)** | `const std_rand = @import("std_rand");` |

`std_rand` is not re-exported through `std`; import it by its bare module name.

## Module overview

`std_rand` provides two concrete, allocation-free pseudorandom generators:
**PCG32** (O'Neill, 2014) and **xoshiro256\*\*** (Blackman & Vigna, 2018).
There are no generics and no vtables: each generator is a plain state struct and
its operations are free functions taking a pointer to that state.

Both generators take explicit seeds. Per rule **R6**, nothing inside `std_rand`
reads the wall clock, the process id, the environment, or an address, and the
module keeps no global state — same input and same seed always produce the same
sequence, every run. `Z98_SEED` is a **user-program convention**, not a std
feature: a program that wants an environment-controlled seed reads it through
`std_os.env` and passes the resulting `u64` to `pcg32Init`/`xoshiroInit`;
production code derives a seed (for example from a clock) in user code. The
module itself never looks at `Z98_SEED`.

Bounded draws use **rejection sampling**, never a bare `% bound`: values below a
computed threshold are discarded so every result in `[0, bound)` is equally
likely. A `bound` of `0` is a caller bug and traps via `@panic`. PCG32's advance
operation jumps the LCG state forward in `O(log delta)` so it is equivalent to
calling `pcg32Next` `delta` times without the loop.

State sizes are fixed: `Pcg32` is 16 bytes and `Xoshiro256` is 32 bytes. Copying
a state struct copies the sequence; the caller owns all storage.

## Quick start

Seed both generators explicitly, draw bounded values, and print them.

```zig
const std = @import("std");
const std_rand = @import("std_rand");

pub fn main() void {
    var pcg = std_rand.pcg32Init(0xDEADBEEF, 54);
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        var v: u32 = std_rand.pcg32Bounded(&pcg, 100);
        std.io.printInt(@intCast(i32, v));
        std.io.writeByte('\n');
    }

    var xs = std_rand.xoshiroInit(0xDEADBEEF);
    var u: u64 = std_rand.xoshiroBounded(&xs, 100);
    std.io.printInt(@intCast(i32, @intCast(u32, u)));
    std.io.writeByte('\n');
}
```

## API

### `std_rand`

#### `Pcg32`

**Purpose** — the PCG32 generator state: a 64-bit LCG state and an odd stream
increment.

**When to use** — for a compact 32-bit generator with a selectable stream. For
64-bit output use `Xoshiro256`.

**Signature** — `pub const Pcg32 = struct { state: u64, inc: u64 };`

**Parameters** (fields)
- `state` — the current LCG state; advanced by `pcg32Next`, `pcg32Bounded`, and
  `pcg32Advance`.
- `inc` — the odd stream increment chosen at `pcg32Init`; it controls which
  sequence the generator walks.

**Returns** — a plain value type; `pcg32Init` returns one by value.

**Errors** — none.

**Example**
```zig
var rng = std_rand.pcg32Init(0xDEADBEEF, 54);
```

**Gotchas** — treat the fields as opaque; initialize with `pcg32Init` rather
than writing them by hand, because `inc` must be odd. Copying the struct copies
the generator position.

#### `Xoshiro256`

**Purpose** — the xoshiro256\*\* generator state: four 64-bit words.

**When to use** — for 64-bit output and a larger period; seed it with
`xoshiroInit`.

**Signature** — `pub const Xoshiro256 = struct { s: [4]u64 };`

**Parameters** (fields)
- `s` — the four state words; initialized from a single `u64` by `xoshiroInit`
  and updated in place by `xoshiroNext`/`xoshiroBounded`.

**Returns** — a plain value type; `xoshiroInit` returns one by value.

**Errors** — none.

**Example**
```zig
var rng = std_rand.xoshiroInit(0xDEADBEEF);
```

**Gotchas** — initialize with `xoshiroInit`; an arbitrary `s` value is not a
validly expanded seed. Copying the struct copies the generator position.

#### `pcg32Init`

**Purpose** — seeds a PCG32 generator from a seed and a stream selector.

**When to use** — the entry point for PCG32; use distinct `stream` values when
you need independent sequences from related seeds.

**Signature** — `pub fn pcg32Init(seed: u64, stream: u64) Pcg32`

**Parameters**
- `seed` — the starting state mixed into the generator.
- `stream` — selects the sequence; the increment is `(stream * 2) | 1`, so it is
  odd by construction.

**Returns** — a `Pcg32` ready for `pcg32Next`, `pcg32Bounded`, or
`pcg32Advance`.

**Errors** — none.

**Example**
```zig
var rng = std_rand.pcg32Init(0xDEADBEEF, 54);
```

**Gotchas** — identical `(seed, stream)` pairs produce identical sequences.
Different streams are necessary to decorrelate generators initialized with the
same seed.

#### `pcg32Next`

**Purpose** — advances the PCG32 LCG and returns one 32-bit output.

**When to use** — for an unbounded 32-bit draw; prefer `pcg32Bounded` when the
result must fall in a range.

**Signature** — `pub fn pcg32Next(r: *Pcg32) u32`

**Parameters**
- `r` — the generator; its `state` is advanced.

**Returns** — the next `u32` from the permutation output.

**Errors** — none.

**Example**
```zig
var bits: u32 = std_rand.pcg32Next(&rng);
```

**Gotchas** — the returned value is the full 32-bit word; reducing it with `%`
yourself introduces modulo bias. Use `pcg32Bounded`.

#### `pcg32Bounded`

**Purpose** — returns a uniformly distributed value in `[0, bound)` using
rejection sampling.

**When to use** — any time a PCG32 draw must be less than a caller-chosen
bound (dice rolls, array indices, simulation ranges).

**Signature** — `pub fn pcg32Bounded(r: *Pcg32, bound: u32) u32`

**Parameters**
- `r` — the generator; advanced once per candidate draw.
- `bound` — the exclusive upper limit; must be nonzero.

**Returns** — a `u32` in `[0, bound)`.

**Errors** — none in the error-union sense. `bound == 0` is a precondition
violation: it calls `@panic("pcg32Bounded: bound must be nonzero")` and traps.

**Example**
```zig
var roll: u32 = std_rand.pcg32Bounded(&rng, 6);
```

**Gotchas** — rejection is used, never a bare modulo, so the distribution is
unbiased. The number of underlying `pcg32Next` calls per result varies with the
bound; that variation is part of the deterministic sequence.

#### `pcg32Advance`

**Purpose** — advances the PCG32 LCG state by `delta` steps in `O(log delta)`.

**When to use** — to jump ahead in a sequence without looping, or to reproduce
the state after a known number of draws.

**Signature** — `pub fn pcg32Advance(r: *Pcg32, delta: u64) void`

**Parameters**
- `r` — the generator; `state` is updated, `inc` is unchanged.
- `delta` — the number of `pcg32Next`-equivalent steps to advance.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std_rand.pcg32Advance(&rng, 1000);
```

**Gotchas** — the resulting state is identical to having called `pcg32Next`
`delta` times; `delta == 0` leaves the state unchanged.

#### `xoshiroInit`

**Purpose** — seeds a xoshiro256\*\* generator by expanding a single `u64` with
SplitMix64.

**When to use** — the entry point for xoshiro256\*\*.

**Signature** — `pub fn xoshiroInit(seed: u64) Xoshiro256`

**Parameters**
- `seed` — the single `u64` expanded into the four state words.

**Returns** — a `Xoshiro256` ready for `xoshiroNext` or `xoshiroBounded`.

**Errors** — none.

**Example**
```zig
var rng = std_rand.xoshiroInit(0xDEADBEEF);
```

**Gotchas** — the expansion matches the reference SplitMix64 sequence exactly;
substituting a different expansion breaks the known-answer vectors. The same
seed always yields the same four words.

#### `xoshiroNext`

**Purpose** — advances the xoshiro256\*\* state and returns one 64-bit output.

**When to use** — for an unbounded 64-bit draw; prefer `xoshiroBounded` when the
result must fall in a range.

**Signature** — `pub fn xoshiroNext(r: *Xoshiro256) u64`

**Parameters**
- `r` — the generator; its four state words are updated.

**Returns** — the next `u64` from the xoshiro256\*\* core.

**Errors** — none.

**Example**
```zig
var bits: u64 = std_rand.xoshiroNext(&rng);
```

**Gotchas** — the returned value is the full 64-bit word; reducing it with `%`
yourself introduces modulo bias. Use `xoshiroBounded`.

#### `xoshiroBounded`

**Purpose** — returns a uniformly distributed value in `[0, bound)` using
rejection sampling.

**When to use** — any time a 64-bit xoshiro draw must be less than a
caller-chosen bound.

**Signature** — `pub fn xoshiroBounded(r: *Xoshiro256, bound: u64) u64`

**Parameters**
- `r` — the generator; advanced once per candidate draw.
- `bound` — the exclusive upper limit; must be nonzero.

**Returns** — a `u64` in `[0, bound)`.

**Errors** — none in the error-union sense. `bound == 0` is a precondition
violation: it calls `@panic("xoshiroBounded: bound must be nonzero")` and traps.

**Example**
```zig
var roll: u64 = std_rand.xoshiroBounded(&rng, 6);
```

**Gotchas** — rejection is used, never a bare modulo, so the distribution is
unbiased. The number of underlying `xoshiroNext` calls per result varies with
the bound; that variation is part of the deterministic sequence.

## See also

- `std_rand` — the module in this doc.
- [`bits_math.md`](bits_math.md) — `std.bits` rotate helpers are the generic
  equivalents of the module-private word rotations.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
