# Physics — `std_physics`

| | |
|---|---|
| **Modules** | `std_physics` |
| **Layers** | `L5` — pure algorithm layer: Position-Based Dynamics (PBD); world state is arena-owned |
| **Import (by path)** | `const std_physics = @import("std_physics.zig");` |
| **Consumes** | `std_arena` (world storage), `std_mem` (zeroing), `std_math` (`sqrt`), `std_rand` (seeded constraint shuffle) |

`std_physics` is not re-exported through `std`; import it by path.

## Module overview

`std_physics` is a small **Position-Based Dynamics** solver (Müller et al.,
"Position Based Dynamics", *Journal of Visual Communication and Image
Representation* 18(2), 2007) for particles and distance constraints. It is the
classic cloth / soft-body / rope formulation: each step integrates particles
with Verlet, then repeatedly projects the distance constraints to pull the
system back toward its rest lengths. The world holds every allocation: particle
array, constraint array, and the per-iteration projection order.

Contract (spec §6.8): alloc arena at `pbdInit` | errors exactly
`error.OutOfMemory` | coroutine no. `PbdWorld.particles`,
`PbdWorld.constraints`, and `PbdWorld.order` are **capacities**; the live entry
counts are `particle_count` and `constraint_count`. The caller sizes the world
once at `pbdInit` and adds up to those capacities. Nothing is freed
individually; the arena outlives the world.

The solver is f32 throughout. Distances are computed in f64 with
`std.math.sqrt` and cast back to f32 — see
[the length rule](#length-rule-f64-sqrt-then-f32-cast) — so the projection is
stable without importing libm or introducing a tolerance.

### Verlet contract

`pbdStep` integrates every particle whose `inv_mass != 0` with

```
new = pos + (pos - prev) * (1 - damping) + gravity * dt*dt
```

then stores `prev = old pos` and `pos = new`. The `dt*dt` scaling is exact: a
step of `dt` always applies `gravity * dt * dt`, never `gravity * dt`. This is
the classic place a PBD port goes wrong (gravity off by orders of magnitude);
the free-fall fixture pins it to the continuous analytic `0.5*g*T²` within 1%.

Pinned particles (`inv_mass == 0`) are not integrated and are never moved by a
projection. Consequently a pin is fixed for the whole simulation, including
`prev`: it contributes `wa = 0` (or `wb = 0`) to the inverse-mass weighting and
the other endpoint absorbs the full correction.

`damping` is used only in the velocity term `(1 - damping)`. `0` means no
damping. It is not validated; keep it in `[0, 1]` for physical behavior.
Constraints are projected after integration, so the constraint forces do not
feed back into `prev` in the same step.

### Length rule: f64 sqrt, then f32 cast

The distance length is computed as

```
len = f32(std_math.sqrt(f64(dx*dx + dy*dy + dz*dz)))
```

That is: the squared length is accumulated in f32 (matching the emitted C),
converted to f64 for `std_math.sqrt` (pure Z98, no libm), and the result is
cast back to f32 before use. Both `pbdAddDistance` (rest length at add time)
and `pbdStep` (current length during projection) use this rule. Do not replace
it with an f32 `sqrt` or a tolerance: the C89 reference follows the same
protocol and the crosscheck is an exact `cmp`.

### Projection formula and skip rules

Each constraint in the shuffled `order` is projected with the current particle
positions. With `dx = pos[b] - pos[a]`, `dy`, `dz` component-wise, `len`
computed by the length rule above, and `wa = inv_mass[a]`, `wb = inv_mass[b]`:

```
corr = (len - rest) / len * stiffness
pos[a] += dx * corr * wa / (wa + wb)      (likewise dy, dz)
pos[b] -= dx * corr * wb / (wa + wb)      (likewise dy, dz)
```

The inverse-mass weights put the correction on the movable endpoint:
`wa/(wa+wb)` for `a` and `wb/(wa+wb)` for `b`. A pinned endpoint has
`inv_mass = 0`, so the other endpoint absorbs the full correction.

**Skip rules:** a constraint is skipped entirely when `len == 0` (no direction
to project along) or `wa + wb == 0` (both endpoints pinned). The skip happens
before `corr` is formed, so neither division sees a zero denominator. Both
conditions are part of the contract and are covered by the crosscheck vector.

### Stiffness, iterations, and damping

`stiffness` is the **per-iteration fraction** of the positional error removed
by a projection, not a material constant:

- `stiffness = 1` removes the error in one projection (exact for a single
  constraint).
- `stiffness = 0.5` moves halfway in one projection.

Because every projection sees the positions left by earlier constraints, the
visible stiffness also depends on `iterations` and on constraint ordering.
Practical starting points:

| material | stiffness | iterations |
|---|---|---|
| cloth / rope | `1.0` | 4–8 |
| soft body | lower (for example `0.1`–`0.5`) | more (10+) |

Cloth is usually modeled with full stiffness plus several iterations; soft
bodies distribute the correction over more iterations with a lower per-step
fraction. `iterations == 0` is valid and integrates only (pure ballistic
motion, no constraint projection). `iterations` is a `u8`; very large values
cost time linearly.

With two or more constraints, the order is shuffled every iteration with the
world's seeded `std_rand.Xoshiro256` generator. That removes the
projection-order bias of a fixed sweep (an 8-seed asymmetric fixture asserts at
least two distinct final positions, which a dead shuffle would not produce).
With a single constraint there is nothing to shuffle and no rng draw is made.

### No collision constraints (v1)

Version 1 has **distance constraints only**. There are no collision,
self-collision, bend, volume, or pin constraints beyond setting `inv_mass = 0`
with `pbdPin`. Cloth can pass through itself and through other geometry; a
caller that needs collisions must layer a collision pass or a later module on
top. This is a documented scope limit, not a bug.

### Determinism

The constraint shuffle is seeded. Given the same `seed`, the same world
contents (including the order in which particles and constraints were added),
and the same sequence of `pbdStep(w, dt)` calls, the trajectory is
**bit-identical** on every run: f32 stores, a seeded xoshiro stream, and no
clock, address, PID, or environment input. Copying a `PbdWorld` value copies
the generator state with it; two independently initialized worlds with the
same seed and adds stay identical in lockstep.

## Quick start

Build a three-particle chain with the first particle pinned, let gravity hang
it for 240 steps, and print the free end's height.

```zig
const std = @import("std");
const std_physics = @import("std_physics.zig");

pub fn main() void {
    var storage: [65536]u8 = undefined;
    var arena = std.arena.init(storage[0..]);
    var w = std_physics.pbdInit(&arena, 3, 2, 42) catch @panic("pbdInit");

    w.gravity[0] = 0.0;
    w.gravity[1] = -9.81;
    w.gravity[2] = 0.0;
    w.iterations = 8;

    _ = std_physics.pbdAddParticle(&w, [3]f32{ 0.0, 2.0, 0.0 }, 1.0);
    _ = std_physics.pbdAddParticle(&w, [3]f32{ 1.0, 2.0, 0.0 }, 1.0);
    _ = std_physics.pbdAddParticle(&w, [3]f32{ 2.0, 2.0, 0.0 }, 1.0);
    std_physics.pbdPin(&w, 0);
    _ = std_physics.pbdAddDistance(&w, 0, 1, 1.0);
    _ = std_physics.pbdAddDistance(&w, 1, 2, 1.0);

    var dt: f32 = @floatCast(f32, 1.0 / 60.0);
    var i: u32 = 0;
    while (i < 240) : (i += 1) {
        std_physics.pbdStep(&w, dt);
    }

    std.io.print("{}\n", .{w.particles[2].pos[1]});
}
```

The pinned particle stays at `y = 2`. With no damping the chain keeps
swinging; after 240 steps the free end prints about `0.6285`, and the link
distances stay within f32 rounding of their rest length `1` (about `1.000024`
and `1.0`).

## API

### `std_physics`

#### `Particle`

**Purpose** — one simulated point mass.

**Signature** — `pub const Particle = struct { pos: [3]f32, prev: [3]f32, inv_mass: f32 };`

**Parameters** (fields)
- `pos` — current world position.
- `prev` — position at the previous integration step (the Verlet velocity
  source).
- `inv_mass` — inverse mass. `0` means pinned/immovable; larger values react
  more to a constraint.

**Returns** — a plain value type stored in the world's `particles` array.

**Errors** — none.

**Gotchas** — read `particles[i].pos` after a step; there is no separate output
buffer. `prev` is solver state, not a caller input. Adding a particle sets both
`pos` and `prev` to the supplied position.

#### `DistanceConstraint`

**Purpose** — a distance constraint between two live particle indices.

**Signature** — `pub const DistanceConstraint = struct { a: u32, b: u32, rest: f32, stiffness: f32 };`

**Parameters** (fields)
- `a` — index of the first particle.
- `b` — index of the second particle; must differ from `a`.
- `rest` — rest length, captured at `pbdAddDistance` time.
- `stiffness` — per-iteration fraction of the length error removed by a
  projection (`1` = exact in one projection).

**Returns** — a plain value type stored in the world's `constraints` array.

**Errors** — none.

**Gotchas** — `rest` is a snapshot of the positions when the constraint is
added. If you move particles before adding the constraint, that moved distance
becomes the rest length. Setting `stiffness = 0` leaves the constraint inert.

#### `PbdWorld`

**Purpose** — the arena-owned simulation state.

**Signature** — `pub const PbdWorld = struct { particles: []Particle, constraints: []DistanceConstraint, order: []u32, particle_count: u32, constraint_count: u32, gravity: [3]f32, damping: f32, iterations: u8, rng: std_rand.Xoshiro256 };`

**Parameters** (fields)
- `particles` — capacity slice allocated by `pbdInit`.
- `constraints` — capacity slice allocated by `pbdInit`.
- `order` — capacity slice used for the per-iteration shuffled projection
  order; `order.len == constraints.len`.
- `particle_count` — number of live particles (advanced by
  `pbdAddParticle`).
- `constraint_count` — number of live constraints (advanced by
  `pbdAddDistance`).
- `gravity` — acceleration vector in world units per second squared.
- `damping` — velocity retention adjustment in `[0, 1]`; `0` is none.
- `iterations` — projection iterations per `pbdStep`; `0` means integrate
  only.
- `rng` — seeded xoshiro256\*\* state used to shuffle `order`.

**Returns** — a value type returned by `pbdInit`; it borrows arena storage.

**Errors** — none from the type itself.

**Gotchas** — the slice lengths are capacities, not live counts. Do not read
`particles[particle_count..]` or treat every capacity slot as simulated.
`gravity` and `damping` are plain fields; assign elements individually
(`w.gravity[1] = -9.81`) rather than assigning the whole `[3]f32` array in
Z98. Copying the world copies the rng state and all slices (shallowly); it does
not copy the arena.

#### `pbdInit`

**Purpose** — allocates and initializes an empty world.

**When to use** — once per simulation, after the caller's arena exists.

**Signature** — `pub fn pbdInit(arena: *std_arena.Arena, particle_count: u32, constraint_count: u32, seed: u64) !PbdWorld`

**Parameters**
- `arena` — caller arena; all three arrays are allocated from it and never
  freed individually.
- `particle_count` — particle capacity.
- `constraint_count` — constraint capacity (also the `order` length).
- `seed` — seed for the deterministic constraint-shuffle generator.

**Returns** — a zeroed world with `particle_count = 0`,
`constraint_count = 0`, `gravity = {0,0,0}`, `damping = 0`, `iterations = 4`,
and `rng = xoshiroInit(seed)`. The capacity ranges start zeroed.

**Errors**
- `error.OutOfMemory` — one of the three arena allocations failed.

**Example**
```zig
var w = std_physics.pbdInit(&arena, 128, 256, 0xDEADBEEF) catch return;
```

**Gotchas** — `pbdInit` does not add any particles or constraints; it only
reserves capacity. Overlapping lifetimes all draw from the same arena, which
is never reclaimed.

#### `pbdAddParticle`

**Purpose** — appends a live particle to the world.

**Signature** — `pub fn pbdAddParticle(w: *PbdWorld, pos: [3]f32, inv_mass: f32) u32`

**Parameters**
- `w` — mutable world.
- `pos` — initial position; also becomes `prev`.
- `inv_mass` — inverse mass; `0` pins the particle.

**Returns** — the slot index (the previous `particle_count`), then increments
`particle_count`.

**Errors** — none. Precondition violations panic (see below).

**Example**
```zig
const i = std_physics.pbdAddParticle(&w, [3]f32{ 0.0, 2.0, 0.0 }, 1.0);
```

**Gotchas** — the index is a `u32` slot, valid until the world is discarded.
Adding past the `pbdInit` capacity or passing a negative `inv_mass` is a caller
bug and calls `@panic`.

#### `pbdAddDistance`

**Purpose** — appends a distance constraint and captures its rest length from
the current positions.

**Signature** — `pub fn pbdAddDistance(w: *PbdWorld, a: u32, b: u32, stiffness: f32) u32`

**Parameters**
- `w` — mutable world.
- `a` — first particle index; must be `< particle_count`.
- `b` — second particle index; must be `< particle_count` and differ from
  `a`.
- `stiffness` — per-iteration projection fraction (`1` = exact in one
  projection).

**Returns** — the constraint index (the previous `constraint_count`), then
increments `constraint_count`.

**Errors** — none. Precondition violations panic (see below).

**Example**
```zig
_ = std_physics.pbdAddDistance(&w, 0, 1, 1.0);
```

**Gotchas** — add particles first; both indices must refer to live particles.
The rest length is computed now, using the f64-sqrt/f32-cast rule, and does not
track later changes.

#### `pbdPin`

**Purpose** — pins a live particle by setting `inv_mass = 0`.

**Signature** — `pub fn pbdPin(w: *PbdWorld, i: u32) void`

**Parameters**
- `w` — mutable world.
- `i` — live particle index (`< particle_count`).

**Returns** — nothing.

**Errors** — none. An out-of-range index panics.

**Example**
```zig
std_physics.pbdPin(&w, 0);
```

**Gotchas** — pinning is permanent for that `PbdWorld`; there is no unpin
helper (`inv_mass` is a public field if the caller needs to restore it).
Pinning records no anchor: the particle stays at its current `pos`.

#### `pbdStep`

**Purpose** — advances the world by one time step: Verlet integration followed
by iterative distance projection.

**Signature** — `pub fn pbdStep(w: *PbdWorld, dt: f32) void`

**Parameters**
- `w` — mutable world.
- `dt` — time step in seconds; used as `dt*dt` in the gravity term.

**Returns** — nothing; the results are written in place to
`w.particles[i].pos`.

**Errors** — none.

**Example**
```zig
var dt: f32 = @floatCast(f32, 1.0 / 60.0);
std_physics.pbdStep(&w, dt);
```

**Gotchas** — call it with a consistent `dt`; the solver does not adapt the
step or subdivide. With `iterations == 0` it integrates only. With two or more
live constraints, every iteration identity-fills and shuffles
`order[0..constraint_count]` before projecting, so the rng advances each
iteration even when the constraint set is unchanged. With one constraint the
Fisher–Yates loop does not run and no rng draw occurs. Zero particles is a
no-op; zero constraints integrates and returns. A `dt` of `0` still runs the
projection (and the shuffle when `constraint_count >= 2`), so avoid zero-dt
steps when reproducing a trajectory.

### Preconditions and panics

Signatures cannot return these as errors; they are caller-bug preconditions
and call `@panic`:

| operation | panic condition |
|---|---|
| `pbdAddParticle` | `particle_count >= particles.len` (over capacity) |
| `pbdAddParticle` | `inv_mass < 0` |
| `pbdAddDistance` | `constraint_count >= constraints.len` (over capacity) |
| `pbdAddDistance` | `a == b` |
| `pbdAddDistance` | `a >= particle_count` or `b >= particle_count` |
| `pbdPin` | `i >= particle_count` |

The panic fixtures assert an empty stdout and exit code `133` (SIGTRAP) for
the over-capacity particle and distance cases.

## Gates and pins

| gate | command | pin |
|---|---|---|
| basic fixture | `scripts/stdlib/run_fixtures.sh <zig1> repro/mi_matrix/stdlib_physics_basic_xmod` | byte-exact stdout; covers free fall, pinned convergence, stiffness 1/0.5, 10-particle chain, no-force and pinned bit identity, 8-seed spread |
| cross fixture | `scripts/stdlib/run_fixtures.sh <zig1> repro/mi_matrix/stdlib_physics_cross_xmod` | default mode prints `physics cross ok` |
| panic fixtures | `scripts/stdlib/run_fixtures.sh <zig1> repro/mi_matrix/stdlib_physics_panic{x,_distance}_xmod` | empty stdout, exit code `133` |
| crosscheck | `scripts/stdlib/run_crosscheck.sh <zig1> std_physics` | Z98 == C89 ref on `scripts/stdlib/vectors/std_physics/basic.{in,expected}` (exact `cmp`) |
| usage program | `scripts/stdlib/run_fixtures.sh <zig1> stdlib_test/physics_usage` | deterministic stdout ending `physics ok` |
| full std gate | `scripts/stdlib/verify_stdlib.sh <zig1>` | `STDLIB GATE OK` (fixtures + all crosscheck modules) |

Reference implementation: `scripts/stdlib/ref/std_physics/ref.c` (C89, libm
`sqrt`, f32 stores, same xoshiro256\*\* and Fisher–Yates shuffle). Vector
`.in` files are line-oriented: seed, gravity, damping, iterations, steps, dt,
a particle list (`x y z inv_mass` as 8-hex f32 bits), and a constraint list
(`a b stiffness`). Output is one line per particle of `x y z` in 8-hex f32
bits.

## See also

- [`num.md`](num.md) — the other explicit integrator in L5, for ODEs rather
  than constraint systems.
- [`rand.md`](rand.md) — `std_rand.Xoshiro256`, the seeded shuffle source.
- [`memory.md`](memory.md) — `std.arena`, the ownership model for all world
  storage.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
