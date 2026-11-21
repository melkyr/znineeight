// std_num.zig — Z98 std lib L5: Dormand-Prince adaptive RK45 step.
//
// Contract (spec §6.6): alloc none | errors {StepTooSmall} | coroutine no.
// Caller supplies y and dy; no arena. Explicit method: stiff ODEs are out of
// scope and may reject down to min_step.
//
// Tableau: Dormand & Prince, "A family of embedded Runge-Kutta formulae",
// Journal of Computational and Applied Mathematics 6(1), 1980, pp. 19-26.
// The coefficients below are the published 7-stage 5(4) pair (the same pair
// used by MATLAB's ode45):
//
//   c2=1/5
//   a21=1/5
//   c3=3/10   a31=3/40   a32=9/40
//   c4=4/5    a41=44/45  a42=-56/15 a43=32/9
//   c5=8/9    a51=19372/6561 a52=-25360/2187 a53=64448/6561 a54=-212/729
//   c6=1      a61=9017/3168 a62=-355/33 a63=46732/5247 a64=49/176
//             a65=-5103/18656
//   c7=1      a71=35/384 a73=500/1113 a74=125/192 a75=-2187/6784 a76=11/84
//   5th-order weights = a7 (FSAL: k7 = f(t+h, y_{n+1}))
//   4th-order weights b4 = 5179/57600, 0, 7571/16695, 393/640,
//                         -92097/339200, 187/2100, 1/40
//   error weights e = b5 - b4
//
// Coefficients are built from their exact IEEE-754 bit patterns because the
// Z98 decimal-float literal path is not correctly rounded. y/dy are caller
// supplied; dy must hold f(t,y) on entry and holds f(t_new,y_new) on return
// (the FSAL stage).
//
// dt is in/out: on entry it is the requested step (clamped to max_step); on
// return it is the adaptive step size to use next (grown 1.5x after an
// accurate accepted step, capped at max_step). state.t advances by the step
// actually taken.

pub const Rk45Config = struct {
    abs_tol: f64,
    rel_tol: f64,
    min_step: f64,
    max_step: f64,
    max_steps: u32,
};

pub const Rk45State = struct {
    t: f64,
    y: []f64,
    dy: []f64,
    cfg: Rk45Config,
};

// Fixed scratch bound: no allocation and C89 has no VLA. 64 doubles per stage
// is 3.5 KiB of stack; larger systems are a caller precondition violation.
const RK45_MAX_DIM: usize = 64;

fn d2f(b: u64) f64 {
    var p: *f64 = @ptrCast(*f64, &b);
    return p.*;
}

fn absF64(x: f64) f64 {
    if (x < 0.0) return -x;
    return x;
}

fn maxAbs(a: f64, b: f64) f64 {
    var aa: f64 = absF64(a);
    var bb: f64 = absF64(b);
    if (aa > bb) return aa;
    return bb;
}

// Scaled Newton square root. Scaling keeps the iteration in [1/4,4]; both the
// Z98 module and the C89 reference use this identical operation order so the
// crosscheck is bit-exact.
fn sqrtF64(x: f64) f64 {
    if (x <= 0.0) return 0.0;
    var v: f64 = x;
    var scale: f64 = 1.0;
    while (v > 4.0) {
        v = v * 0.25;
        scale = scale * 2.0;
    }
    while (v < 0.25) {
        v = v * 4.0;
        scale = scale * 0.5;
    }
    var g: f64 = v;
    var i: u32 = 0;
    while (i < 16) : (i += 1) {
        var q: f64 = v / g;
        var s: f64 = g + q;
        g = 0.5 * s;
    }
    return g * scale;
}

// Fifth root by scaled Newton: y <- y - (y^5 - v)/(5 y^4).
fn fifthRootF64(x: f64) f64 {
    if (x <= 0.0) return 0.0;
    var v: f64 = x;
    var scale: f64 = 1.0;
    while (v > 32.0) {
        v = v / 32.0;
        scale = scale * 2.0;
    }
    while (v < 0.03125) {
        v = v * 32.0;
        scale = scale * 0.5;
    }
    var g: f64 = 1.0;
    var i: u32 = 0;
    while (i < 20) : (i += 1) {
        var g2: f64 = g * g;
        var g4: f64 = g2 * g2;
        var y5: f64 = g4 * g;
        var num: f64 = y5 - v;
        var den: f64 = 5.0 * g4;
        var corr: f64 = num / den;
        g = g - corr;
    }
    return g * scale;
}

pub fn rk45Step(state: *Rk45State, f: fn (f64, []const f64, []f64) void, dt: *f64) !void {
    var n: usize = state.y.len;
    if (n == 0) @panic("rk45Step: empty state vector");
    if (n > RK45_MAX_DIM) @panic("rk45Step: state dimension exceeds 64");

    // Dormand-Prince 5(4) coefficients from the exact bit patterns above.
    var a21: f64 = d2f(0x3fc999999999999a);
    var c2: f64 = d2f(0x3fc999999999999a);
    var a31: f64 = d2f(0x3fb3333333333333);
    var a32: f64 = d2f(0x3fcccccccccccccd);
    var c3: f64 = d2f(0x3fd3333333333333);
    var a41: f64 = d2f(0x3fef49f49f49f49f);
    var a42: f64 = d2f(0xc00dddddddddddde);
    var a43: f64 = d2f(0x400c71c71c71c71c);
    var c4: f64 = d2f(0x3fe999999999999a);
    var a51: f64 = d2f(0x40079eec0fc37181);
    var a52: f64 = d2f(0xc027310bd29520e4);
    var a53: f64 = d2f(0x4023a552363c5290);
    var a54: f64 = d2f(0xbfd29c9eba1e3345);
    var c5: f64 = d2f(0x3fec71c71c71c71c);
    var a61: f64 = d2f(0x4006c52bf5a814b0);
    var a62: f64 = d2f(0xc02583e0f83e0f84);
    var a63: f64 = d2f(0x4021d016a3721e8b);
    var a64: f64 = d2f(0x3fd1d1745d1745d1);
    var a65: f64 = d2f(0xbfd1818970d9cc2f);
    var c6: f64 = d2f(0x3ff0000000000000);
    var a71: f64 = d2f(0x3fb7555555555555);
    var a73: f64 = d2f(0x3fdcc0499a5605fb);
    var a74: f64 = d2f(0x3fe4d55555555555);
    var a75: f64 = d2f(0xbfd4a1cfb2b78c13);
    var a76: f64 = d2f(0x3fc0c30c30c30c31);
    var c7: f64 = d2f(0x3ff0000000000000);

    var e1: f64 = d2f(0x3f54320fedcba987);
    var e2: f64 = d2f(0x0000000000000000);
    var e3: f64 = d2f(0xbf716b5a550abfc4);
    var e4: f64 = d2f(0x3fa2eeeeeeeeeeef);
    var e5: f64 = d2f(0xbfaa0ad1d2ca1858);
    var e6: f64 = d2f(0x3fa5748a7bdaf0e2);
    var e7: f64 = d2f(0xbf9999999999999a);

    var p09: f64 = d2f(0x3feccccccccccccd);
    var p05: f64 = d2f(0x3fe0000000000000);
    var p15: f64 = d2f(0x3ff8000000000000);
    var p10: f64 = d2f(0x3ff0000000000000);

    var h: f64 = dt.*;
    if (h > state.cfg.max_step) h = state.cfg.max_step;
    if (h < state.cfg.min_step) return error.StepTooSmall;

    var kbuf: [7 * RK45_MAX_DIM]f64 = undefined;
    var ynew: [RK45_MAX_DIM]f64 = undefined;
    var arg: [RK45_MAX_DIM]f64 = undefined;

    var attempt: u32 = 0;
    while (true) {
        if (attempt >= state.cfg.max_steps) return error.StepTooSmall;

        var j: usize = 0;
        while (j < n) : (j += 1) {
            kbuf[j] = state.dy[j];
        }

        // stage 2
        j = 0;
        while (j < n) : (j += 1) {
            var acc: f64 = a21 * kbuf[j];
            var tmp: f64 = h * acc;
            arg[j] = state.y[j] + tmp;
        }
        var ts: f64 = state.t + c2 * h;
        var b1: usize = RK45_MAX_DIM;
        var e1s: usize = b1 + n;
        f(ts, arg[0..n], kbuf[b1..e1s]);

        // stage 3
        j = 0;
        while (j < n) : (j += 1) {
            var acc: f64 = a31 * kbuf[j];
            acc = acc + a32 * kbuf[RK45_MAX_DIM + j];
            var tmp: f64 = h * acc;
            arg[j] = state.y[j] + tmp;
        }
        ts = state.t + c3 * h;
        b1 = 2 * RK45_MAX_DIM;
        e1s = b1 + n;
        f(ts, arg[0..n], kbuf[b1..e1s]);

        // stage 4
        j = 0;
        while (j < n) : (j += 1) {
            var acc: f64 = a41 * kbuf[j];
            acc = acc + a42 * kbuf[RK45_MAX_DIM + j];
            acc = acc + a43 * kbuf[2 * RK45_MAX_DIM + j];
            var tmp: f64 = h * acc;
            arg[j] = state.y[j] + tmp;
        }
        ts = state.t + c4 * h;
        b1 = 3 * RK45_MAX_DIM;
        e1s = b1 + n;
        f(ts, arg[0..n], kbuf[b1..e1s]);

        // stage 5
        j = 0;
        while (j < n) : (j += 1) {
            var acc: f64 = a51 * kbuf[j];
            acc = acc + a52 * kbuf[RK45_MAX_DIM + j];
            acc = acc + a53 * kbuf[2 * RK45_MAX_DIM + j];
            acc = acc + a54 * kbuf[3 * RK45_MAX_DIM + j];
            var tmp: f64 = h * acc;
            arg[j] = state.y[j] + tmp;
        }
        ts = state.t + c5 * h;
        b1 = 4 * RK45_MAX_DIM;
        e1s = b1 + n;
        f(ts, arg[0..n], kbuf[b1..e1s]);

        // stage 6
        j = 0;
        while (j < n) : (j += 1) {
            var acc: f64 = a61 * kbuf[j];
            acc = acc + a62 * kbuf[RK45_MAX_DIM + j];
            acc = acc + a63 * kbuf[2 * RK45_MAX_DIM + j];
            acc = acc + a64 * kbuf[3 * RK45_MAX_DIM + j];
            acc = acc + a65 * kbuf[4 * RK45_MAX_DIM + j];
            var tmp: f64 = h * acc;
            arg[j] = state.y[j] + tmp;
        }
        ts = state.t + c6 * h;
        b1 = 5 * RK45_MAX_DIM;
        e1s = b1 + n;
        f(ts, arg[0..n], kbuf[b1..e1s]);

        // stage 7 (FSAL first-same-as-last)
        j = 0;
        while (j < n) : (j += 1) {
            var acc: f64 = a71 * kbuf[j];
            acc = acc + a73 * kbuf[2 * RK45_MAX_DIM + j];
            acc = acc + a74 * kbuf[3 * RK45_MAX_DIM + j];
            acc = acc + a75 * kbuf[4 * RK45_MAX_DIM + j];
            acc = acc + a76 * kbuf[5 * RK45_MAX_DIM + j];
            var tmp: f64 = h * acc;
            arg[j] = state.y[j] + tmp;
        }
        ts = state.t + c7 * h;
        b1 = 6 * RK45_MAX_DIM;
        e1s = b1 + n;
        f(ts, arg[0..n], kbuf[b1..e1s]);

        // 5th-order solution and scaled RMS error norm.
        var errsum: f64 = 0.0;
        j = 0;
        while (j < n) : (j += 1) {
            var acc: f64 = a71 * kbuf[j];
            acc = acc + a73 * kbuf[2 * RK45_MAX_DIM + j];
            acc = acc + a74 * kbuf[3 * RK45_MAX_DIM + j];
            acc = acc + a75 * kbuf[4 * RK45_MAX_DIM + j];
            acc = acc + a76 * kbuf[5 * RK45_MAX_DIM + j];
            var tmp: f64 = h * acc;
            ynew[j] = state.y[j] + tmp;

            var ea: f64 = e1 * kbuf[j];
            ea = ea + e2 * kbuf[RK45_MAX_DIM + j];
            ea = ea + e3 * kbuf[2 * RK45_MAX_DIM + j];
            ea = ea + e4 * kbuf[3 * RK45_MAX_DIM + j];
            ea = ea + e5 * kbuf[4 * RK45_MAX_DIM + j];
            ea = ea + e6 * kbuf[5 * RK45_MAX_DIM + j];
            ea = ea + e7 * kbuf[6 * RK45_MAX_DIM + j];
            var ei: f64 = h * ea;

            var scale: f64 = state.cfg.abs_tol + state.cfg.rel_tol * maxAbs(state.y[j], ynew[j]);
            var scaled: f64 = ei / scale;
            errsum = errsum + scaled * scaled;
        }
        var fn_f: f64 = @intToFloat(f64, @intCast(i32, n));
        var mean: f64 = errsum / fn_f;
        var err: f64 = sqrtF64(mean);

        if (err <= p10) {
            j = 0;
            while (j < n) : (j += 1) {
                state.y[j] = ynew[j];
                state.dy[j] = kbuf[6 * RK45_MAX_DIM + j];
            }
            state.t = state.t + h;
            var next: f64 = h;
            if (err < p05) {
                next = h * p15;
                if (next > state.cfg.max_step) next = state.cfg.max_step;
            }
            dt.* = next;
            return;
        }

        var root: f64 = fifthRootF64(err);
        var invroot: f64 = p10 / root;
        var factor: f64 = p09 * invroot;
        var hnew: f64 = h * factor;
        if (hnew < state.cfg.min_step) return error.StepTooSmall;
        h = hnew;
        attempt = attempt + 1;
    }
}
