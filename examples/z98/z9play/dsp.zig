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
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        var a: f64 = @intToFloat(f64, 2 * i + 1 + half);
        var sum: f64 = 0.0;
        var k: u32 = 0;
        while (k < half) : (k += 1) {
            var b: f64 = @intToFloat(f64, 2 * k + 1);
            var arg: f64 = scale * a * b;
            sum = sum + spectra[@intCast(usize, k)] * std.math.cos(arg);
        }
        out[@intCast(usize, i)] = sum;
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
    var i: u32 = 0;
    while (i < len) : (i += 1) {
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
    var i: usize = 0;
    while (i < block.len) : (i += 1) {
        block[i] = block[i] * win[i];
    }
}

// Overlap-add: out[i] = prev[i] + cur[i]. `prev` is the previous block's
// windowed right-half tail, `cur` the current block's windowed left-half head;
// all three slices share the overlap length.
pub fn overlapAdd(prev: []f64, cur: []f64, out: []f64) void {
    var i: usize = 0;
    while (i < out.len) : (i += 1) {
        out[i] = prev[i] + cur[i];
    }
}
