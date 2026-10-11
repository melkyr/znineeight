// dsp_test.zig — deterministic unit harness for z9play dsp.zig (M3 Task 1).
//
// Checks, all under `-fsafe`, with the output exiting 0 on success / 1 on the
// first failure:
//   1. imdct: a block of `n` samples from a single non-zero spectral
//      coefficient equals the analytic MDCT basis
//      cos( (pi/(2n)) (2i+1+n/2) (2k+1) ) (several k, including k=0 and the
//      top coefficient); two coefficients are checked for linearity, and a
//      negative coefficient for sign.
//   2. window: the full block window equals the closed form
//      sin( (pi/2) sin^2( (pi/(2 len)) (i+0.5) ) ) on the left half, mirrored
//      on the right half; and the Princen-Bradley/TDAC identity
//      w[i]^2 + w[i+n/2]^2 == 1 holds.
//   3. libvorbis spot-check: the n=64 window slope equals the reference
//      `vwin64` table (xiph/vorbis lib/window.c) entries to f32 precision.
//   4. overlapAdd: out == prev + cur elementwise.
//   5. determinism: imdct and window produce bit-identical results on a re-run.
//
// The analytic values use the SAME pi bit pattern and std.math.sin/cos as
// dsp.zig, so the identity checks are tight (they would still pass under a
// reused correctly-rounded value).
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/dsp_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog

const std = @import("std");
const dsp = @import("../dsp.zig");

const PI_BITS: u64 = 0x400921FB54442D18;

fn b2d(b: u64) f64 {
    var p: *f64 = @ptrCast(*f64, &b);
    return p.*;
}

var arena_buf: [256 * 1024]u8 = undefined;

fn fail(msg: []const u8) void {
    var p: []const u8 = "dsp_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

fn absF(x: f64) f64 {
    if (x < 0.0) return -x;
    return x;
}

fn checkNear(got: f64, want: f64, tol: f64, msg: []const u8) void {
    if (absF(got - want) > tol) fail(msg);
}

// Analytic MDCT basis for a block of `n` samples, output index `i`, spectral
// index `k`.
fn basis(n: u32, i: u32, k: u32) f64 {
    var nf: f64 = @intToFloat(f64, n);
    var scale: f64 = b2d(PI_BITS) / (2.0 * nf);
    var a: f64 = @intToFloat(f64, 2 * i + 1 + n / 2);
    var b: f64 = @intToFloat(f64, 2 * k + 1);
    return std.math.cos(scale * a * b);
}

// Independent closed form of one half-window slope sample of length `len`.
fn slopeWant(len: u32, i: u32) f64 {
    var lenf: f64 = @intToFloat(f64, len);
    var inner: f64 = (b2d(PI_BITS) / (2.0 * lenf)) * (@intToFloat(f64, i) + 0.5);
    var s: f64 = std.math.sin(inner);
    var s2: f64 = s * s;
    return std.math.sin(0.5 * b2d(PI_BITS) * s2);
}

// Full symmetric window value for block `n` at index `i` (mirror the slope).
fn windowWant(n: u32, i: u32) f64 {
    var half: u32 = n / 2;
    if (i >= half) return slopeWant(half, n - 1 - i);
    return slopeWant(half, i);
}

fn checkImdctSingle(arena: *std.arena.Arena, n: u32, k: u32) void {
    var spectra: [64]f64 = undefined;
    var out: [64]f64 = undefined;
    var i: u32 = 0;
    while (i < n) : (i += 1) spectra[i] = 0.0;
    spectra[k] = 1.0;
    dsp.imdct(arena, n, spectra[0 .. n / 2], out[0..n]);
    i = 0;
    while (i < n) : (i += 1) {
        if (absF(out[i] - basis(n, i, k)) > 1.0e-12) fail("imdct single-coefficient mismatch");
    }
}

pub fn main() void {
    var arena = std.arena.init(arena_buf[0..]);

    // --- 1. IMDCT vs analytic basis ---
    checkImdctSingle(&arena, 16, 0);
    checkImdctSingle(&arena, 16, 3);
    checkImdctSingle(&arena, 16, 7);
    checkImdctSingle(&arena, 64, 5);

    // Two coefficients: linearity of the transform.
    {
        var n: u32 = 16;
        var spectra: [8]f64 = undefined;
        var out: [16]f64 = undefined;
        var i: u32 = 0;
        while (i < 8) : (i += 1) spectra[i] = 0.0;
        spectra[2] = 1.5;
        spectra[6] = -0.75;
        dsp.imdct(&arena, n, spectra[0..8], out[0..16]);
        i = 0;
        while (i < 16) : (i += 1) {
            var want: f64 = 1.5 * basis(n, i, 2) + (-0.75) * basis(n, i, 6);
            if (absF(out[i] - want) > 1.0e-12) fail("imdct linearity mismatch");
        }
    }

    // --- 2. window vs closed form + TDAC ---
    {
        var n: u32 = 16;
        var w: [16]f64 = undefined;
        dsp.window(n, w[0..16]);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            checkNear(w[i], windowWant(n, i), 1.0e-15, "window closed-form mismatch");
        }
        i = 0;
        while (i < n / 2) : (i += 1) {
            var v: f64 = w[i] * w[i] + w[i + n / 2] * w[i + n / 2];
            checkNear(v, 1.0, 1.0e-12, "window TDAC identity mismatch");
        }
    }

    // --- 3. libvorbis vwin64 spot-check (xiph/vorbis lib/window.c) ---
    {
        var w64: [64]f64 = undefined;
        dsp.window(64, w64[0..64]);
        checkNear(w64[0], 0.0009460463, 2.0e-7, "vwin64[0] mismatch");
        checkNear(w64[1], 0.0085006468, 2.0e-7, "vwin64[1] mismatch");
        checkNear(w64[15], 0.6793382689, 2.0e-7, "vwin64[15] mismatch");
        checkNear(w64[31], 0.9999995525, 2.0e-7, "vwin64[31] mismatch");
    }

    // --- 4. overlapAdd ---
    {
        var prev: [4]f64 = undefined;
        var cur: [4]f64 = undefined;
        var out: [4]f64 = undefined;
        prev[0] = 1.0;
        prev[1] = 2.0;
        prev[2] = 3.0;
        prev[3] = 4.0;
        cur[0] = 10.0;
        cur[1] = 20.0;
        cur[2] = 30.0;
        cur[3] = 40.0;
        dsp.overlapAdd(prev[0..4], cur[0..4], out[0..4]);
        checkNear(out[0], 11.0, 0.0, "overlapAdd[0] mismatch");
        checkNear(out[1], 22.0, 0.0, "overlapAdd[1] mismatch");
        checkNear(out[2], 33.0, 0.0, "overlapAdd[2] mismatch");
        checkNear(out[3], 44.0, 0.0, "overlapAdd[3] mismatch");
    }

    // --- 5. deterministic re-run (bit-identical) ---
    {
        var n: u32 = 16;
        var spectra: [8]f64 = undefined;
        var a: [16]f64 = undefined;
        var b: [16]f64 = undefined;
        var i: u32 = 0;
        while (i < 8) : (i += 1) spectra[i] = @intToFloat(f64, i) - 3.5;
        dsp.imdct(&arena, n, spectra[0..8], a[0..16]);
        dsp.imdct(&arena, n, spectra[0..8], b[0..16]);
        i = 0;
        while (i < n) : (i += 1) {
            if (a[i] != b[i]) fail("imdct not deterministic");
        }

        var wa: [16]f64 = undefined;
        var wb: [16]f64 = undefined;
        dsp.window(n, wa[0..16]);
        dsp.window(n, wb[0..16]);
        i = 0;
        while (i < n) : (i += 1) {
            if (wa[i] != wb[i]) fail("window not deterministic");
        }
    }

    var ok: []const u8 = "dsp_test: PASS imdct=analytic window=closed+tdac vwin64=ok overlap=ok deterministic=ok\n";
    std.io.write(ok);
    std.os.exit(0);
}
