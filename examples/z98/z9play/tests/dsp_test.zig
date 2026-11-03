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
const dec = @import("../decode.zig");

const PI_BITS: u64 = 0x400921FB54442D18;

fn b2d(b: u64) f64 {
    var p: *f64 = @ptrCast(*f64, &b);
    return p.*;
}

var arena_buf: [256 * 1024]u8 = undefined;

var spec_buf: [1024]f64 = undefined;
var ref_buf: [2048]f64 = undefined;
var got_buf: [2048]f64 = undefined;
var win_buf: [2048]f64 = undefined;
var blk_buf: [2048]f64 = undefined;
var fwd_buf: [1024]f64 = undefined;
var slope_buf: [1024]f64 = undefined;
var exp_buf: [2048]f64 = undefined;

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

// Independent copy of decode.buildWindow's assembly, using dsp.windowSlope.
// Used to check the cached windows in decode.buildWindowCache byte for byte.
fn expectedWindow(n: u32, bs0: u32, blockflag: bool, prev_wf: u32, next_wf: u32, out: []f64, slope: []f64) void {
    var center: u32 = n / 2;
    var l_start: u32 = 0;
    var l_end: u32 = center;
    var l_n: u32 = n / 2;
    if (blockflag and prev_wf == 0) {
        l_start = n / 4 - bs0 / 4;
        l_end = n / 4 + bs0 / 4;
        l_n = bs0 / 2;
    }
    var r_start: u32 = center;
    var r_end: u32 = n;
    var r_n: u32 = n / 2;
    if (blockflag and next_wf == 0) {
        r_start = n * 3 / 4 - bs0 / 4;
        r_end = n * 3 / 4 + bs0 / 4;
        r_n = bs0 / 2;
    }
    var i: u32 = 0;
    while (i < l_start) : (i += 1) out[@intCast(usize, i)] = 0.0;
    dsp.windowSlope(l_n, slope[0..@intCast(usize, l_n)]);
    i = 0;
    while (i < l_n) : (i += 1) out[@intCast(usize, l_start + i)] = slope[@intCast(usize, i)];
    i = l_end;
    while (i < r_start) : (i += 1) out[@intCast(usize, i)] = 1.0;
    dsp.windowSlope(r_n, slope[0..@intCast(usize, r_n)]);
    i = 0;
    while (i < r_n) : (i += 1) out[@intCast(usize, r_end - 1 - i)] = slope[@intCast(usize, i)];
    i = r_end;
    while (i < n) : (i += 1) out[@intCast(usize, i)] = 0.0;
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

    // --- 6. imdctFft vs the exact dsp.imdct reference, every block size ---
    {
        var sizes: [6]u32 = [6]u32{ 64, 128, 256, 512, 1024, 2048 };
        var si: usize = 0;
        while (si < 6) : (si += 1) {
            var n: u32 = sizes[si];
            var sz: usize = @intCast(usize, n);
            var half: usize = sz / 2;
            var t: dsp.ImdctTables = dsp.imdctTablesInit(&arena, n) catch {
                fail("imdctTablesInit failed");
                return;
            };
            var i: usize = 0;
            while (i < half) : (i += 1) {
                var q: i32 = @intCast(i32, (i * 37 + 11) % 97) - 48;
                spec_buf[i] = @intToFloat(f64, q) * 0.05;
            }
            dsp.imdct(&arena, n, spec_buf[0..half], ref_buf[0..sz]);
            dsp.imdctFft(t, spec_buf[0..half], got_buf[0..sz]);
            var maxd: f64 = 0.0;
            i = 0;
            while (i < sz) : (i += 1) {
                var d: f64 = absF(got_buf[i] - ref_buf[i]);
                if (d > maxd) maxd = d;
            }
            if (maxd > 1.0e-9) fail("imdctFft accuracy mismatch");
            var lab: []const u8 = "imdctFft n=";
            std.io.write(lab);
            std.io.printInt(@intCast(i32, n));
            var lab2: []const u8 = " maxdelta_x1e12=";
            std.io.write(lab2);
            std.io.printInt(@intCast(i32, maxd * 1.0e12 + 0.5));
            var nl: []const u8 = "\n";
            std.io.write(nl);
        }
    }

    // --- 7. TDAC: two consecutive windows + overlap -> constant signal ---
    {
        var n: u32 = 64;
        var sz: usize = @intCast(usize, n);
        var m: usize = sz / 2;
        var t: dsp.ImdctTables = dsp.imdctTablesInit(&arena, n) catch {
            fail("imdctTablesInit failed (tdac)");
            return;
        };
        dsp.window(n, win_buf[0..sz]);
        var k: usize = 0;
        while (k < m) : (k += 1) {
            var sum: f64 = 0.0;
            var tt: usize = 0;
            while (tt < sz) : (tt += 1) {
                sum = sum + win_buf[tt] * basis(n, @intCast(u32, tt), @intCast(u32, k));
            }
            fwd_buf[k] = sum;
        }
        dsp.imdctFft(t, fwd_buf[0..m], blk_buf[0..sz]);
        var gain: f64 = @intToFloat(f64, @intCast(u32, sz / 4));
        var g: usize = m;
        while (g < sz) : (g += 1) {
            var r: f64 = blk_buf[g] * win_buf[g] + blk_buf[g - m] * win_buf[g - m];
            var v: f64 = r / gain;
            if (absF(v - 1.0) > 1.0e-9) fail("TDAC reconstruction mismatch");
        }
    }

    // --- 8. cached windows match a freshly assembled window byte for byte ---
    {
        var bs0: u32 = 64;
        var bs1: u32 = 256;
        var cache: dec.WindowCache = dec.buildWindowCache(&arena, bs0, bs1) catch {
            fail("buildWindowCache failed");
            return;
        };
        expectedWindow(bs0, bs0, false, 1, 1, exp_buf[0..@intCast(usize, bs0)], slope_buf);
        var i: usize = 0;
        while (i < @intCast(usize, bs0)) : (i += 1) {
            if (cache.short[i] != exp_buf[i]) fail("cached short window mismatch");
        }
        var p: u32 = 0;
        while (p < 4) : (p += 1) {
            expectedWindow(bs1, bs0, true, p / 2, p % 2, exp_buf[0..@intCast(usize, bs1)], slope_buf);
            var row: []f64 = cache.long[@intCast(usize, p)];
            i = 0;
            while (i < @intCast(usize, bs1)) : (i += 1) {
                if (row[i] != exp_buf[i]) fail("cached long window mismatch");
            }
        }
    }

    var ok: []const u8 = "dsp_test: PASS imdct=analytic window=closed+tdac vwin64=ok overlap=ok deterministic=ok imdctfft=ref tdac=ola windows=cached\n";
    std.io.write(ok);
    std.os.exit(0);
}
