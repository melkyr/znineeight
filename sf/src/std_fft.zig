// std_fft.zig — Z98 std lib: iterative radix-2 complex FFT (f64).
//
// Contract: alloc at init only | errors NotPowerOfTwo/TooSmall/TooLarge/
// OutOfMemory | coroutine no. Standalone module imported by path (deliberately
// NOT re-exported from `std.zig`, so the seed pins do not move).
//
//   FftError                     error{ NotPowerOfTwo, TooSmall, TooLarge, OutOfMemory }
//   FftTables                    { n, rev, cos_t, sin_t }
//   fftInit(arena, n)            build the bit-reversal + twiddle tables
//   fftRun(t, re, im)            in-place forward DFT
//   ifftRun(t, re, im)           in-place inverse DFT (normalized by 1/n)
//
// `n` is a power of two, 2 <= n <= 65536. `rev` has n entries; `cos_t`/`sin_t`
// have n/2 entries each: cos_t[k] = cos(2*pi*k/n), sin_t[k] = sin(2*pi*k/n).
// The forward transform uses the e^{-i} twiddle, so the inverse conjugates the
// imaginary input, runs the forward kernel, conjugates again, and scales both
// parts by 1/n.
//
// Iterative Cooley-Tukey, radix-2, decimation in time. All tables live in the
// caller's arena; no recursion and no large stack arrays. Runtime trig happens
// only in fftInit (`std.math.sin`/`std.math.cos`); the butterflies are table
// lookups. pi is built from its exact IEEE-754 bit pattern because the lexer's
// decimal-float parser is not guaranteed correctly rounded.

const std = @import("std");

const PI_BITS: u64 = 0x400921FB54442D18;

fn b2d(b: u64) f64 {
    var p: *f64 = @ptrCast(*f64, &b);
    return p.*;
}

pub const FftError = error{ NotPowerOfTwo, TooSmall, TooLarge, OutOfMemory };

pub const FftTables = struct {
    n: u32,
    rev: []u32,
    cos_t: []f64,
    sin_t: []f64,
};

pub fn fftInit(arena: *std.arena.Arena, n: u32) FftError!FftTables {
    if (n < 2) return error.TooSmall;
    if (n > 65536) return error.TooLarge;
    if ((n & (n - 1)) != 0) return error.NotPowerOfTwo;

    var nu: usize = @intCast(usize, n);
    var half: u32 = n / 2;
    var hu: usize = @intCast(usize, half);

    var raw_rev = std.arena.alloc(arena, nu * @sizeOf(u32)) catch return error.OutOfMemory;
    var rev: []u32 = @ptrCast([*]u32, raw_rev)[0..nu];
    var raw_c = std.arena.alloc(arena, hu * @sizeOf(f64)) catch return error.OutOfMemory;
    var cos_t: []f64 = @ptrCast([*]f64, raw_c)[0..hu];
    var raw_s = std.arena.alloc(arena, hu * @sizeOf(f64)) catch return error.OutOfMemory;
    var sin_t: []f64 = @ptrCast([*]f64, raw_s)[0..hu];

    var bits: u32 = 0;
    var m: u32 = n;
    while (m > 1) : (m >>= 1) {
        bits += 1;
    }

    var i: u32 = 0;
    while (i < n) : (i += 1) {
        var x: u32 = i;
        var r: u32 = 0;
        var b: u32 = 0;
        while (b < bits) : (b += 1) {
            r = (r << 1) | (x & 1);
            x = x >> 1;
        }
        rev[@intCast(usize, i)] = r;
    }

    var two_pi: f64 = 2.0 * b2d(PI_BITS);
    var nf: f64 = @intToFloat(f64, n);
    var k: u32 = 0;
    while (k < half) : (k += 1) {
        var arg: f64 = two_pi * @intToFloat(f64, k) / nf;
        cos_t[@intCast(usize, k)] = std.math.cos(arg);
        sin_t[@intCast(usize, k)] = std.math.sin(arg);
    }

    return FftTables{ .n = n, .rev = rev, .cos_t = cos_t, .sin_t = sin_t };
}

pub fn fftRun(t: FftTables, re: []f64, im: []f64) void {
    var n: usize = @intCast(usize, t.n);

    var i: usize = 0;
    while (i < n) : (i += 1) {
        var j: usize = @intCast(usize, t.rev[i]);
        if (i < j) {
            var tr: f64 = re[i];
            re[i] = re[j];
            re[j] = tr;
            var ti: f64 = im[i];
            im[i] = im[j];
            im[j] = ti;
        }
    }

    var len: usize = 2;
    while (len <= n) {
        var half: usize = len / 2;
        var step: usize = n / len;
        var start: usize = 0;
        while (start < n) {
            var k: usize = 0;
            while (k < half) : (k += 1) {
                var idx: usize = start + k;
                var kk: usize = k * step;
                var wr: f64 = t.cos_t[kk];
                var wi: f64 = -t.sin_t[kk];
                var xr: f64 = re[idx + half];
                var xi: f64 = im[idx + half];
                var br: f64 = xr * wr - xi * wi;
                var bi: f64 = xr * wi + xi * wr;
                var ar: f64 = re[idx];
                var ai: f64 = im[idx];
                re[idx] = ar + br;
                im[idx] = ai + bi;
                re[idx + half] = ar - br;
                im[idx + half] = ai - bi;
            }
            start += len;
        }
        len = len * 2;
    }
}

pub fn ifftRun(t: FftTables, re: []f64, im: []f64) void {
    var i: usize = 0;
    while (i < im.len) : (i += 1) {
        im[i] = -im[i];
    }
    fftRun(t, re, im);
    var scale: f64 = 1.0 / @intToFloat(f64, t.n);
    i = 0;
    while (i < re.len) : (i += 1) {
        re[i] = re[i] * scale;
        im[i] = -im[i] * scale;
    }
}
