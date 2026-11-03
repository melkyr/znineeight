// dsp.zig — Vorbis window + inverse MDCT + overlap-add (z9play M3 Task 1).
//
// Pure Z98: free functions, no generics/anytype/@Type, strict @intCast, no
// @cImport, no switch. The transcendental work (sin/cos) comes from the M2
// `std.math` f64 surface, which is reachable through the std root import and
// links no libm; pi is a LOCAL constant (built from its exact IEEE-754 bit
// pattern, like std_math does, because the lexer's decimal-float parser is not
// guaranteed correctly rounded).
//
// Conventions (binding for the decode layer, M3 Task 4):
//
//   imdct(arena, n, spectra, out)
//     `n` is the TRANSFORM BLOCK SIZE in time samples (a power of two); there
//     are `n/2` spectral coefficients in `spectra` and `n` output samples in
//     `out`. This is the UNNORMALIZED Vorbis inverse MDCT (Vorbis I spec
//     section 4.3.7 / the MDCT of [1]):
//
//         out[i] = sum_{k=0}^{n/2-1} X[k] * cos( (pi/(2n)) (2i+1+n/2) (2k+1) )
//
//     for 0 <= i < n. No extra scale factor is applied here; any global PCM
//     normalization belongs to the decode stage (the reference libvorbis folds
//     a `4/n` factor into its MDCT — see lib/mdct.c `lookup->scale` — so the
//     caller must reconcile the global scale against the golden PCM).
//
//   windowSlope(len, out)
//     `out.len == len` is the HALF-window slope length (a block of size `2*len`
//     laps two of these). The Vorbis slope function (Vorbis I spec section
//     1.3.2 / 4.3.6, generated over the half window of length `len`):
//
//         out[i] = sin( (pi/2) * sin^2( (pi/(2*len)) * (i + 0.5) ) )
//
//     for 0 <= i < len. At i = len-1 this is ~1, so the slope rises 0 -> 1;
//     `window` places it on the left half of a block and mirrors it on the
//     right half. (This is exactly libvorbis's `vwin*[i]` generation; the
//     table for a block of size 64 has 32 entries.)
//
//   window(n, out)
//     `out.len == n` is the FULL block window (block size `n`, hence slope
//     length `n/2`), symmetric:
//         out[i] = slope[i]           for 0 <= i < n/2
//         out[n-1-i] = slope[i]       for 0 <= i < n/2
//
//   overlapAdd(prev, cur, out)
//     The previous block's WINDOWED RIGHT-HALF tail (`prev`) added to the
//     current block's WINDOWED LEFT-HALF head (`cur`): out[i] = prev[i]+cur[i].
//     All three slices have the same overlap length (n/2 for equal-size
//     blocks). A decoder keeps one such tail buffer per channel; the finished
//     samples it returns are exactly `out`.

const std = @import("std");
const fft_mod = @import("std_fft.zig");

// pi = 0x1.921fb54442d18p+1, the correctly-rounded IEEE-754 double.
const PI_BITS: u64 = 0x400921FB54442D18;

fn b2d(b: u64) f64 {
    var p: *f64 = @ptrCast(*f64, &b);
    return p.*;
}

fn piVal() f64 {
    return b2d(PI_BITS);
}

// Unnormalized Vorbis inverse MDCT. See the file header for the exact formula
// and the `n` / `spectra.len` / `out.len` contract. `arena` is accepted for
// contract stability with the other decoder stages (no allocation is needed by
// this direct O(n^2/2) form).
pub fn imdct(arena: *std.arena.Arena, n: u32, spectra: []const f64, out: []f64) void {
    _ = arena;
    var half: u32 = n / 2;
    var nf: f64 = @intToFloat(f64, n);
    var scale: f64 = piVal() / (2.0 * nf);
    for (0..n) |i| {
        var a: f64 = @intToFloat(f64, 2 * i + 1 + half);
        var sum: f64 = 0.0;
        for (0..half) |k| {
            var b: f64 = @intToFloat(f64, 2 * k + 1);
            var arg: f64 = scale * a * b;
            sum = sum + spectra[@intCast(usize, k)] * std.math.cos(arg);
        }
        out[@intCast(usize, i)] = sum;
    }
}

// Precomputed tables for the FFT-based inverse MDCT of block size `n`.
// `fft` is a size-`n/4` transform; `pre_*` (length n/4) hold the input
// rotation and `post_*` (length n/4 + 1) the output rotation. All tables are
// built once from the decoder arena; decoding performs no transcendental calls.
pub const ImdctTables = struct {
    n: u32,
    fft: fft_mod.FftTables,
    pre_c: []f64,
    pre_s: []f64,
    post_c: []f64,
    post_s: []f64,
};

fn allocF64(arena: *std.arena.Arena, len: u32) ![]f64 {
    var nu: usize = @intCast(usize, len);
    var raw: [*]u8 = std.arena.alloc(arena, nu * @sizeOf(f64)) catch return error.OutOfMemory;
    return @ptrCast([*]f64, raw)[0..nu];
}

// Build the size-`n` inverse-MDCT tables. `n` is a power of two with n >= 8.
// The transform reduces to a size-`n/4` complex FFT (standard MDCT-to-FFT
// decomposition): with M = n/2 spectral coefficients and alpha = pi/M, the
// pre-rotation is exp(-i(alpha*j + alpha/4)) and the post-rotation is
// exp(-i*alpha*j) for the even outputs / exp(+i*alpha*(j+1)) for the odd ones.
pub fn imdctTablesInit(arena: *std.arena.Arena, n: u32) !ImdctTables {
    var k: u32 = n / 4;
    var fft: fft_mod.FftTables = fft_mod.fftInit(arena, k) catch |e| return e;
    var ku: usize = @intCast(usize, k);
    var pre_c: []f64 = try allocF64(arena, k);
    var pre_s: []f64 = try allocF64(arena, k);
    var post_c: []f64 = try allocF64(arena, k + 1);
    var post_s: []f64 = try allocF64(arena, k + 1);

    var mf: f64 = @intToFloat(f64, n / 2);
    var alpha: f64 = piVal() / mf;
    for (0..k) |i| {
        var beta: f64 = alpha * (@intToFloat(f64, i) + 0.25);
        pre_c[@intCast(usize, i)] = std.math.cos(beta);
        pre_s[@intCast(usize, i)] = std.math.sin(beta);
    }
    for (0..k + 1) |i| {
        var ang: f64 = alpha * @intToFloat(f64, i);
        post_c[@intCast(usize, i)] = std.math.cos(ang);
        post_s[@intCast(usize, i)] = std.math.sin(ang);
    }

    return ImdctTables{ .n = n, .fft = fft, .pre_c = pre_c, .pre_s = pre_s, .post_c = post_c, .post_s = post_s };
}

// FFT-based inverse MDCT with the same value and contract as `imdct`:
// `spectra.len == n/2`, `out.len == n`. `out` doubles as the FFT workspace, so
// no additional buffers or stack arrays are needed. Iterative throughout.
pub fn imdctFft(t: ImdctTables, spectra: []const f64, out: []f64) void {
    var m: usize = @intCast(usize, t.n / 2);
    var k: usize = @intCast(usize, t.n / 4);

    // Pre-twiddle the n/2 real coefficients into n/4 complex values.
    var i: usize = 0;
    while (i < k) : (i += 1) {
        var a: f64 = spectra[2 * i];
        var b: f64 = spectra[m - 1 - 2 * i];
        var pc: f64 = t.pre_c[i];
        var ps: f64 = t.pre_s[i];
        out[i] = a * pc + b * ps;
        out[k + i] = b * pc - a * ps;
    }
    fft_mod.fftRun(t.fft, out[0..k], out[k..2 * k]);

    // Post-twiddle into the length-M DCT-IV coefficients C[0..M-1], stored in
    // the far half of `out` while the FFT bins still live in the near half.
    var j: usize = 0;
    while (j < k) : (j += 1) {
        var vr: f64 = out[j];
        var vi: f64 = out[k + j];
        out[m + 2 * j] = vr * t.post_c[j] + vi * t.post_s[j];
        var r: usize = k - 1 - j;
        var ur: f64 = out[r];
        var ui: f64 = out[k + r];
        out[m + 2 * j + 1] = ur * t.post_c[j + 1] - ui * t.post_s[j + 1];
    }

    // Symmetric extension: y[i] = +/-C[index] for each of the four quarters.
    var h: usize = m / 2;
    i = 0;
    while (i < h) : (i += 1) {
        out[i] = out[m + h + i];
    }
    i = h;
    while (i < m) : (i += 1) {
        out[i] = -out[m + (3 * m / 2 - 1 - i)];
    }
    var q: usize = 0;
    while (q < h) : (q += 1) {
        out[3 * m / 2 + q] = -out[m + q];
    }
    q = 0;
    while (q < h / 2) : (q += 1) {
        var r2: usize = h - 1 - q;
        var lo: f64 = out[m + q];
        var hi: f64 = out[m + r2];
        out[m + q] = -hi;
        out[m + r2] = -lo;
    }
    if ((h % 2) == 1) {
        out[m + h / 2] = -out[m + h / 2];
    }
}

// One sample of the Vorbis half-window slope of length `len`:
// sin( (pi/2) * sin^2( (pi/(2*len)) * (i + 0.5) ) ). `sin^2` is a multiply.
fn slopeAt(len: u32, i: u32) f64 {
    var lenf: f64 = @intToFloat(f64, len);
    var inner: f64 = (piVal() / (2.0 * lenf)) * (@intToFloat(f64, i) + 0.5);
    var s: f64 = std.math.sin(inner);
    var s2: f64 = s * s;
    return std.math.sin(0.5 * piVal() * s2);
}

// Fill `out` (length `len`) with the Vorbis half-window slope of length `len`.
pub fn windowSlope(len: u32, out: []f64) void {
    for (0..len) |i| {
        out[@intCast(usize, i)] = slopeAt(len, i);
    }
}

// Fill `out` (length `n`) with the full symmetric Vorbis window for a block of
// size `n` (a power of two): the length-`n/2` slope on the left half, mirrored
// on the right half.
pub fn window(n: u32, out: []f64) void {
    var half: u32 = n / 2;
    var i: u32 = 0;
    while (i < half) : (i += 1) {
        var s: f64 = slopeAt(half, i);
        out[@intCast(usize, i)] = s;
        out[@intCast(usize, n - 1 - i)] = s;
    }
}

// Multiply `block` by `win` element by element (both the same length).
pub fn applyWindow(block: []f64, win: []f64) void {
    for (block) |*item, i| {
        item.* = item.* * win[i];
    }
}

// Overlap-add: out[i] = prev[i] + cur[i]. `prev` is the previous block's
// windowed right-half tail, `cur` the current block's windowed left-half head;
// all three slices share the overlap length.
pub fn overlapAdd(prev: []f64, cur: []f64, out: []f64) void {
    for (out) |*item, i| {
        item.* = prev[i] + cur[i];
    }
}
