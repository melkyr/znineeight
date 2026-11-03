// stdlib_fft_inverse_xmod — STDLIB std_fft forward+inverse identity fixture.
//
// Forward then inverse must recover the input real sequence (the inverse is
// normalized by 1/n), and the imaginary part must return to zero. This pins the
// conjugate/scale path in ifftRun.
//
// GREEN (contract): deterministic byte-exact stdout below (RUNRC=0):
//   1000 2000 3000 4000 5000 6000 7000 8000 0 0 0 0 0 0 0 0
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
    var re = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0 };
    var im = [_]f64{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };
    fft.fftRun(t, re[0..], im[0..]);
    fft.ifftRun(t, re[0..], im[0..]);
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
