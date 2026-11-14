// std_fft.zig — Z98 std lib: iterative split-radix complex FFT (f64).
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
// have n entries each: cos_t[k] = cos(2*pi*k/n), sin_t[k] = sin(2*pi*k/n), so
// every split-radix twiddle is a direct table read. The forward transform uses
// the e^{-i} twiddle, so the inverse conjugates the imaginary input, runs the
// forward kernel, conjugates again, and scales both parts by 1/n.
//
// Iterative Yavne/Sorensen split-radix, decimation in time: DFT(N) = the
// even-index DFT(N/2) plus the twiddled 4k+1 and 4k+3 DFT(N/4) transforms,
// combined bottom-up after the bit-reversal permutation. Each L-shaped butterfly
// handles the four outputs k, k+N/4, k+N/2, k+3N/4 from the two halves of the
// even block and the odd blocks. All tables live in the caller's arena; no
// recursion and no large stack arrays. Runtime trig happens only in fftInit
// (`std.math.sin`/`std.math.cos`); the butterflies are table lookups. pi is
// built from its exact IEEE-754 bit pattern because the lexer's decimal-float
// parser is not guaranteed correctly rounded.

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

    var raw_rev = std.arena.alloc(arena, nu * @sizeOf(u32)) catch return error.OutOfMemory;
    var rev: []u32 = @ptrCast([*]u32, raw_rev)[0..nu];
    var raw_c = std.arena.alloc(arena, nu * @sizeOf(f64)) catch return error.OutOfMemory;
    var cos_t: []f64 = @ptrCast([*]f64, raw_c)[0..nu];
    var raw_s = std.arena.alloc(arena, nu * @sizeOf(f64)) catch return error.OutOfMemory;
    var sin_t: []f64 = @ptrCast([*]f64, raw_s)[0..nu];

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
    while (k < n) : (k += 1) {
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

    var bits: u32 = 0;
    var x: usize = n;
    while (x > 1) : (x >>= 1) {
        bits += 1;
    }

    var dm: u32 = 1;
    var m: usize = 2;
    while (m <= n) {
        var d: u32 = bits - dm;
        var nodes: usize = n / m;
        var j: usize = 0;
        while (j < nodes) : (j += 1) {
            var o: usize = j * m;
            var sbit: u32 = t.rev[o];
            var p: u32 = 0;
            var keep: bool = true;
            while (p < d and keep) {
                if (((sbit >> p) & 1) == 0) {
                    p += 1;
                } else if (p + 1 < d) {
                    p += 2;
                } else {
                    keep = false;
                }
            }
            if (!keep) continue;
            if (m == 2) {
                var x0r: f64 = re[o];
                var x0i: f64 = im[o];
                var x1r: f64 = re[o + 1];
                var x1i: f64 = im[o + 1];
                re[o] = x0r + x1r;
                im[o] = x0i + x1i;
                re[o + 1] = x0r - x1r;
                im[o + 1] = x0i - x1i;
            } else {
                var m2: usize = m / 2;
                var m4: usize = m / 4;
                var step: usize = n / m;
                var k: usize = 0;
                while (k < m4) : (k += 1) {
                    var i0: usize = o + k;
                    var i1: usize = o + k + m4;
                    var i2: usize = o + k + m2;
                    var i3: usize = o + k + 3 * m4;
                    var a0r: f64 = re[i0];
                    var a0i: f64 = im[i0];
                    var a1r: f64 = re[i1];
                    var a1i: f64 = im[i1];
                    var br: f64 = re[i2];
                    var bi: f64 = im[i2];
                    var cr: f64 = re[i3];
                    var ci: f64 = im[i3];
                    var p1: usize = k * step;
                    var p3: usize = 3 * k * step;
                    var wr: f64 = t.cos_t[p1];
                    var wi: f64 = -t.sin_t[p1];
                    var t1r: f64 = br * wr - bi * wi;
                    var t1i: f64 = br * wi + bi * wr;
                    var w3r: f64 = t.cos_t[p3];
                    var w3i: f64 = -t.sin_t[p3];
                    var t3r: f64 = cr * w3r - ci * w3i;
                    var t3i: f64 = cr * w3i + ci * w3r;
                    var d1r: f64 = t1r + t3r;
                    var d1i: f64 = t1i + t3i;
                    var d2r: f64 = t1r - t3r;
                    var d2i: f64 = t1i - t3i;
                    re[i0] = a0r + d1r;
                    im[i0] = a0i + d1i;
                    re[i2] = a0r - d1r;
                    im[i2] = a0i - d1i;
                    re[i1] = a1r + d2i;
                    im[i1] = a1i - d2r;
                    re[i3] = a1r - d2i;
                    im[i3] = a1i + d2r;
                }
            }
        }
        m <<= 1;
        dm += 1;
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
