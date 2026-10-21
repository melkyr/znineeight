# Numerics — `std_num`

| | |
|---|---|
| **Modules** | `std_num` |
| **Layers** | `L5` — pure algorithm layer: explicit adaptive ODE integration; allocates nothing |
| **Import (by path)** | `const std_num = @import("std_num.zig");` |
| **Consumes** | none |

`std_num` is not re-exported through `std`; import it by path.

## Module overview

`std_num` is a Dormand–Prince **7-stage embedded 5(4) Runge–Kutta** stepper
(the same pair used by MATLAB's `ode45`). It advances a caller-owned state
vector by one adaptive step at a time. Tableau: Dormand & Prince, "A family of
embedded Runge-Kutta formulae", *Journal of Computational and Applied
Mathematics* 6(1), 1980, pp. 19–26.

Contract (spec §6.6): alloc none | errors exactly `error.StepTooSmall` |
coroutine no. The state vector `y` and its derivative buffer `dy` are supplied
by the caller; the stepper never touches an arena or the heap. The 7-stage
scratch lives on the stack inside `rk45Step`.

The implementation is self-contained C89-compatible Z98: the scaled RMS norm
uses a local scaled-Newton `sqrt`, and the rejection exponent uses a local
scaled-Newton fifth root, so neither the Z98 module nor the C89 crosscheck
reference needs libm. Both implementations build the tableau from the same
exact IEEE-754 bit patterns and perform the same operation order, so the
crosscheck is bit-exact rather than tolerance-based.

**Explicit method — stiff systems are out of scope.** There is no implicit
solve and no Jacobian. A stiff ODE (for example `dy/dt = 1000*y`) drives the
step size down until `min_step` or the retry budget is exhausted, and
`rk45Step` returns `error.StepTooSmall`. That is a documented limit, not a
failure of the caller's tolerances. Use an implicit method for stiff problems.

### Fixed scratch cap: `RK45_MAX_DIM = 64`

The module is allocation-free and C89 has no VLA, so each stage buffer is a
fixed `RK45_MAX_DIM = 64` doubles. State dimension `n` must satisfy
`1 <= n <= 64`. `n == 0` or `n > 64` is a caller precondition violation and
panics in `rk45Step` (the 7-stage key buffer alone is 3.5 KiB of stack; the
full working set is about 4.5 KiB). Larger systems need a different
integrator, not a larger buffer.

### `dy` and FSAL

Dormand–Prince is **FSAL** (first-same-as-last): the 7th stage of an accepted
step is `f(t_new, y_new)`, which is exactly the first stage of the next step.
`state.dy` carries that stage:

- **Before the first call**, the caller must fill `dy` with `f(t, y)`.
- **On success**, `rk45Step` writes `dy = f(t_new, y_new)`; pass the same
  `Rk45State` into the next call and that evaluation is reused.
- **On a rejected attempt** the state, `t`, and `dy` are unchanged, and the
  trial is retried with a smaller step using the same first stage.

Recomputing `dy` unnecessarily is harmless but wastes one evaluation; leaving
it stale breaks the method silently.

## Quick start

Integrate `dy/dt = -y`, `y(0) = 1`, to `t = 1` with a caller-owned state and
the canonical in/out `dt`.

```zig
const std = @import("std");
const std_num = @import("std_num.zig");

fn rhs(t: f64, y: []const f64, out: []f64) void {
    _ = t;
    out[0] = -y[0];
}

pub fn main() void {
    var y: [1]f64 = .{1.0};
    var dy: [1]f64 = .{0.0};
    rhs(0.0, y[0..], dy[0..]);                 // FSAL seed: dy = f(t, y)

    var st = std_num.Rk45State{
        .t = 0.0,
        .y = y[0..],
        .dy = dy[0..],
        .cfg = std_num.Rk45Config{
            .abs_tol = 1e-9,
            .rel_tol = 1e-9,
            .min_step = 1e-12,
            .max_step = 0.1,
            .max_steps = 1000,
        },
    };
    var dt: f64 = 0.01;
    while (st.t < 1.0) {
        if (st.t + dt > 1.0) dt = 1.0 - st.t;  // land exactly on the endpoint
        std_num.rk45Step(&st, rhs, &dt) catch |err| {
            if (err == error.StepTooSmall) return;
            return;
        };
    }
    std.io.print("{}\n", .{st.y[0]});           // ≈ 1/e
}
```

The endpoint clamp above is the caller's job: `rk45Step` does not know the
integration interval and never stops at a target time.

## API

### `std_num`

#### `Rk45Config`

**Purpose** — tolerances, step bounds, and per-call retry budget.

**Signature** — `pub const Rk45Config = struct { abs_tol: f64, rel_tol: f64, min_step: f64, max_step: f64, max_steps: u32 };`

**Parameters** (fields)
- `abs_tol` — absolute error scale. Use when a state component may be near
  zero; `1e-9` is a typical starting point for double precision.
- `rel_tol` — relative error scale. Usually equal to `abs_tol`.
- `min_step` — smallest attempted step. A requested or rejected step below
  this returns `error.StepTooSmall`.
- `max_step` — largest step. On entry a requested `dt` above this is clamped
  down to it; on return the suggested `dt` is capped at it.
- `max_steps` — maximum **rejected attempts** inside one `rk45Step` call, not
  a total step count across calls. Exhausting it returns
  `error.StepTooSmall`.

**Returns** — a plain config value.

**Errors** — none; the module does not validate `min_step <= max_step` or
positive tolerances. Supply a coherent configuration.

#### `Rk45State`

**Purpose** — the mutable integration state plus a borrowed config.

**Signature** — `pub const Rk45State = struct { t: f64, y: []f64, dy: []f64, cfg: Rk45Config };`

**Parameters** (fields)
- `t` — current independent variable. Advanced by the accepted step actually
  taken.
- `y` — caller-owned state slice; length `n` is the system dimension.
- `dy` — caller-owned derivative slice, same length as `y`. Must hold
  `f(t, y)` on entry and holds `f(t_new, y_new)` after success (the FSAL
  stage).
- `cfg` — the `Rk45Config` for this and subsequent calls.

**Returns** — a value type holding slices; it does not own or copy the state.

**Errors** — none.

**Gotchas** — the slices must stay valid for the lifetime of the integration.
`y.len` must be in `1..64`; `dy.len` must equal `y.len`.

#### `rk45Step`

**Purpose** — advances the state by one accepted adaptive Dormand–Prince
5(4) step.

**Signature** — `pub fn rk45Step(state: *Rk45State, f: fn (f64, []const f64, []f64) void, dt: *f64) !void`

**Parameters**
- `state` — mutable state; see `Rk45State`.
- `f` — derivative callback `f(t, y, out)`. It must write all `n` entries of
  `out`; `y` is read-only and `n == state.y.len`. It must be a plain function
  (no captured state); pass context through globals or a module-level value.
  It is called 7 times per attempted step.
- `dt` — in/out step size. On entry, the requested step (clamped down to
  `cfg.max_step`). On return after success, the step size **suggested for the
  next call**. On `error.StepTooSmall`, the caller must treat it as invalid.

**Returns** — nothing. On success `state.t`, `state.y`, and `state.dy` are
updated and `dt.*` holds the next suggested step.

**Errors**
- `error.StepTooSmall` — the requested step is below `cfg.min_step`, a
  rejected step would fall below `cfg.min_step`, or `cfg.max_steps` rejected
  attempts were exhausted. This is the module's entire error set.

**Example**
```zig
var dt: f64 = 0.01;
std_num.rk45Step(&st, rhs, &dt) catch |err| {
    if (err == error.StepTooSmall) return;   // shrink min_step or integrate less stiffly
    return;
};
// st.t advanced by the accepted h; dt is already the next suggested h.
```

**Gotchas** — `dt` is an **in/out** parameter and the return value is a
*suggestion*, not the step just taken. The caller must feed it into the next
call to keep the adaptation alive; reusing a stale `dt` defeats step-size
control. To hit a final time exactly, clamp `dt` yourself before the call.
`state.t` advances by the step actually accepted, never by the suggested next
step.

### Tolerance and step-size semantics

For an attempted step of size `h`, the embedded pair produces a 5th-order
solution `y5` and a 4th-order error estimate. For each component:

```
scale_i = abs_tol + rel_tol * max(|y_n,i|, |y5_i|)
err     = sqrt( mean_i ( (h * error_i / scale_i)^2 ) )
```

The norm is a **scaled RMS**, not a max norm: a max norm makes the step size
oscillate; RMS keeps it smooth. The accept/reject policy is:

| condition | action |
|---|---|
| `err <= 1.0` | accept; commit `y5`, set `dy` to the FSAL stage, advance `t` by `h` |
| `err <= 1.0` and `err < 0.5` | also grow the next step: `dt_next = min(1.5 * h, max_step)` |
| `err <= 1.0` and `err >= 0.5` | keep `dt_next = h` |
| `err > 1.0` | reject; retry with `h_new = 0.9 * h * err^(-1/5)`, or `error.StepTooSmall` if below `min_step` |

The `1.5×` growth is therefore applied **only when `err < 0.5`** — a strict
threshold. An accepted step with `0.5 <= err <= 1.0` leaves the step size
unchanged. The reject factor is `0.9 * err^(-1/5)`, using the embedded pair's
order-5 error exponent. These constants are part of the contract; changing
them changes the fixture's step-growth expectations.

## Gates and pins

| gate | command | pin |
|---|---|---|
| basic fixture | `scripts/stdlib/run_fixtures.sh <zig1> repro/mi_matrix/stdlib_num_basic_xmod` | stdout byte-exact `expected.txt`; covers exponential decay, 10-period harmonic energy drift, Van der Pol endpoint, monotonic 1.5× growth to `max_step`, and `error.StepTooSmall` on a stiff problem |
| crosscheck fixture | `scripts/stdlib/run_fixtures.sh <zig1> repro/mi_matrix/stdlib_num_cross_xmod` | default mode prints `num cross ok` |
| crosscheck | `scripts/stdlib/run_crosscheck.sh <zig1> std_num` | Z98 == C89 ref == `scripts/stdlib/vectors/std_num/basic.expected` |
| full std gate | `scripts/stdlib/verify_stdlib.sh <zig1>` | `STDLIB GATE OK` (fixtures + all crosscheck modules) |

Reference implementation: `scripts/stdlib/ref/std_num/ref.c` (same tableau,
same bit patterns, same scaled-Newton helpers). Crosscheck `.in` lines are
`exp <t0> <y0> <dt> <atol> <rtol> <min> <max> <max_steps> <nsteps>`,
`osc <t0> <x0> <v0> ...`, or `vdp <t0> <x0> <v0> <mu> ...`. The driver prints
`<t> <y...> <dt>` with every f64 as 16 lowercase hex digits of its IEEE-754
bit pattern, or `small` when a call returns `error.StepTooSmall`.

## See also

- [`noise.md`](noise.md) — the other allocation-free L5 algorithm module.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
