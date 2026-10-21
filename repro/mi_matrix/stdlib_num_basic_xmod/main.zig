// stdlib_num_basic_xmod — std_num (L5) Dormand-Prince RK45 GREEN fixture.
//
// Checks:
//   - exponential decay dy/dt=-y, y(0)=1 to t=1 within 1e-6 of 1/e;
//   - harmonic oscillator (x'=v, v'=-x) for 10 periods, |energy drift| < 1e-4;
//   - Van der Pol (mu=2, x(0)=2, v(0)=0) to t=10 matches the committed
//     reference endpoint within 1e-5;
//   - a smooth constant-derivative problem grows dt monotonically 1.5x per
//     accepted step, capped at max_step;
//   - an unreachable tolerance drives dt below min_step => error.StepTooSmall.
//
// GREEN (contract): byte-exact stdout `expected.txt` (RUNRC=0). A mismatch
// calls @panic.
const std = @import("std");
const num = @import("std_num.zig");

const EXP_REF: f64 = 0.36787944117144233;
const VDP_X_REF: f64 = 0.8415536481607456;
const VDP_V_REF: f64 = -1.0890478618868018;
const TEN_PERIODS: f64 = 62.83185307179586;

fn absF64(x: f64) f64 {
    if (x < 0.0) return -x;
    return x;
}

fn maxF64(a: f64, b: f64) f64 {
    if (a > b) return a;
    return b;
}

fn expRhs(t: f64, y: []const f64, out: []f64) void {
    _ = t;
    out[0] = -y[0];
}

fn oscRhs(t: f64, y: []const f64, out: []f64) void {
    _ = t;
    out[0] = y[1];
    out[1] = -y[0];
}

fn vdpRhs(t: f64, y: []const f64, out: []f64) void {
    _ = t;
    var mu: f64 = 2.0;
    out[0] = y[1];
    var one: f64 = 1.0;
    var x2: f64 = y[0] * y[0];
    out[1] = mu * (one - x2) * y[1] - y[0];
}

fn constRhs(t: f64, y: []const f64, out: []f64) void {
    _ = t;
    _ = y;
    out[0] = 0.5;
}

fn stiffRhs(t: f64, y: []const f64, out: []f64) void {
    _ = t;
    out[0] = 1000.0 * y[0];
}

fn cfgOf(atol: f64, rtol: f64, mn: f64, mx: f64, max_steps: u32) num.Rk45Config {
    return num.Rk45Config{
        .abs_tol = atol,
        .rel_tol = rtol,
        .min_step = mn,
        .max_step = mx,
        .max_steps = max_steps,
    };
}

fn checkExponential() void {
    var y: [1]f64 = .{1.0};
    var dy: [1]f64 = .{0.0};
    expRhs(0.0, y[0..], dy[0..]);
    var st = num.Rk45State{ .t = 0.0, .y = y[0..], .dy = dy[0..], .cfg = cfgOf(1e-9, 1e-9, 1e-12, 0.1, 1000) };
    var dt: f64 = 0.01;
    while (st.t < 1.0) {
        if (st.t + dt > 1.0) dt = 1.0 - st.t;
        rkStepOrPanic(&st, expRhs, &dt, "exponential step");
    }
    var e: f64 = absF64(st.y[0] - EXP_REF);
    if (e >= 1e-6) @panic("exponential accuracy");
    std.io.write("exponential ok\n");
}

fn rkStepOrPanic(st: *num.Rk45State, f: fn (f64, []const f64, []f64) void, dt: *f64, what: []const u8) void {
    num.rk45Step(st, f, dt) catch |err| {
        _ = err;
        @panic(what);
    };
}

fn checkHarmonic() void {
    var y: [2]f64 = .{1.0, 0.0};
    var dy: [2]f64 = .{0.0, 0.0};
    oscRhs(0.0, y[0..], dy[0..]);
    var st = num.Rk45State{ .t = 0.0, .y = y[0..], .dy = dy[0..], .cfg = cfgOf(1e-9, 1e-9, 1e-12, 0.1, 1000) };
    var e0: f64 = 0.5 * (y[0] * y[0] + y[1] * y[1]);
    var worst: f64 = 0.0;
    var dt: f64 = 0.001;
    while (st.t < TEN_PERIODS) {
        if (st.t + dt > TEN_PERIODS) dt = TEN_PERIODS - st.t;
        rkStepOrPanic(&st, oscRhs, &dt, "harmonic step");
        var en: f64 = 0.5 * (st.y[0] * st.y[0] + st.y[1] * st.y[1]);
        var d: f64 = absF64(en - e0);
        if (d > worst) worst = d;
    }
    if (worst >= 1e-4) @panic("harmonic energy drift");
    std.io.write("harmonic ok\n");
}

fn checkVdp() void {
    var y: [2]f64 = .{2.0, 0.0};
    var dy: [2]f64 = .{0.0, 0.0};
    vdpRhs(0.0, y[0..], dy[0..]);
    var st = num.Rk45State{ .t = 0.0, .y = y[0..], .dy = dy[0..], .cfg = cfgOf(1e-9, 1e-9, 1e-12, 0.1, 2000) };
    var dt: f64 = 0.001;
    while (st.t < 10.0) {
        if (st.t + dt > 10.0) dt = 10.0 - st.t;
        rkStepOrPanic(&st, vdpRhs, &dt, "vdp step");
    }
    var ex: f64 = absF64(st.y[0] - VDP_X_REF);
    var ev: f64 = absF64(st.y[1] - VDP_V_REF);
    var e: f64 = maxF64(ex, ev);
    if (e >= 1e-5) @panic("vdp endpoint");
    std.io.write("vdp ok\n");
}

fn checkStepGrowth() void {
    var y: [1]f64 = .{0.0};
    var dy: [1]f64 = .{0.0};
    constRhs(0.0, y[0..], dy[0..]);
    var st = num.Rk45State{ .t = 0.0, .y = y[0..], .dy = dy[0..], .cfg = cfgOf(1e-12, 1e-12, 1e-12, 0.1, 100) };
    var dt: f64 = 0.001;
    var prev: f64 = dt;
    var reached: bool = false;
    var i: u32 = 0;
    while (i < 30) : (i += 1) {
        rkStepOrPanic(&st, constRhs, &dt, "growth step");
        if (dt < prev) @panic("growth monotonic");
        var want: f64 = prev * 1.5;
        if (want > 0.1) want = 0.1;
        if (dt != want) @panic("growth factor");
        if (dt == 0.1) reached = true;
        prev = dt;
    }
    if (!reached) @panic("growth cap");
    std.io.write("stepgrowth ok\n");
}

fn checkMinStep() void {
    var y: [1]f64 = .{1.0};
    var dy: [1]f64 = .{0.0};
    stiffRhs(0.0, y[0..], dy[0..]);
    var st = num.Rk45State{ .t = 0.0, .y = y[0..], .dy = dy[0..], .cfg = cfgOf(1e-15, 1e-15, 0.1, 0.1, 50) };
    var dt: f64 = 0.1;
    var hit: bool = false;
    num.rk45Step(&st, stiffRhs, &dt) catch |err| {
        if (err == error.StepTooSmall) hit = true;
    };
    if (!hit) @panic("min_step not hit");
    std.io.write("minstep ok\n");
}

pub fn main() void {
    checkExponential();
    checkHarmonic();
    checkVdp();
    checkStepGrowth();
    checkMinStep();
    std.io.write("num basic ok\n");
}
