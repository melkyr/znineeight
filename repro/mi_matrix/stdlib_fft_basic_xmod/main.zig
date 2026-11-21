// stdlib_fft_basic_xmod — STDLIB std_fft forward radix-2 FFT fixture.
//
// A unit impulse at index 0 has a flat spectrum: every real bin is 1 and every
// imaginary bin is 0. This pins the bit-reversal permutation, the twiddle
// tables, and the butterfly sign convention.
//
// GREEN (contract): deterministic byte-exact stdout below (RUNRC=0):
//   1000 1000 1000 1000 1000 1000 1000 1000 0 0 0 0 0 0 0 0
const std = @import("std");
const fft = @import("std_fft.zig");

var g_buf: [4096]u8 = undefined;
var arena = std.arena.init(g_buf[0..]);

fn emit(v: f64, first: bool) void {
    if (!first) std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, v * 1000.0 + 0.5));
}

pub fn main() void {
    var t = fft.fftInit(&arena, 8) catch return;
    var re = [_]f64{ 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };
    var im = [_]f64{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };
    fft.fftRun(t, re[0..], im[0..]);
    var first = true;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        emit(re[i], first);
        first = false;
    }
    i = 0;
    while (i < 8) : (i += 1) {
        emit(im[i], first);
        first = false;
    }
    std.io.writeByte('\n');
}
