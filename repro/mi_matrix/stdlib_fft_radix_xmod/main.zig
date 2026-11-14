// stdlib_fft_radix_xmod — STDLIB std_fft naive-DFT correctness net.
//
// For N in {4,8,16,32,64,128,256,512}: fill a deterministic asymmetric complex
// input, run fftRun, then compute the naive O(N^2) DFT inline with
// std.math.cos/sin and compare every real and imaginary output. The maximum
// absolute delta over all sizes must be <= 1e-9. This pins the split-radix
// rework against an independent transform (it is green on the radix-2 core too,
// so it is a correctness net, not a RED step).
//
// GREEN (contract): deterministic byte-exact stdout below (RUNRC=0):
//   ok
const std = @import("std");
const fft = @import("std_fft.zig");

const PI_BITS: u64 = 0x400921FB54442D18;

var g_buf: [32768]u8 = undefined;
var arena = std.arena.init(g_buf[0..]);

fn b2d(b: u64) f64 {
    var p: *f64 = @ptrCast(*f64, &b);
    return p.*;
}

fn absf(x: f64) f64 {
    if (x < 0.0) return -x;
    return x;
}

pub fn main() void {
    var sizes = [_]u32{ 4, 8, 16, 32, 64, 128, 256, 512 };
    var two_pi: f64 = 2.0 * b2d(PI_BITS);
    var max: f64 = 0.0;
    var s: usize = 0;
    while (s < 8) : (s += 1) {
        var n: u32 = sizes[s];
        var nu: usize = @intCast(usize, n);
        var t = fft.fftInit(&arena, n) catch return;
        var re: [512]f64 = undefined;
        var im: [512]f64 = undefined;
        var xr: [512]f64 = undefined;
        var xi: [512]f64 = undefined;
        var i: usize = 0;
        while (i < nu) : (i += 1) {
            var ii: i32 = @intCast(i32, i);
            var a: i32 = (ii * 37 + 11) % 97 - 48;
            var b: i32 = (ii * 53 + 7) % 89 - 44;
            re[i] = @intToFloat(f64, a);
            im[i] = @intToFloat(f64, b);
            xr[i] = re[i];
            xi[i] = im[i];
        }
        fft.fftRun(t, re[0..nu], im[0..nu]);
        var nf: f64 = @intToFloat(f64, n);
        var k: usize = 0;
        while (k < nu) : (k += 1) {
            var sr: f64 = 0.0;
            var si: f64 = 0.0;
            var j: usize = 0;
            while (j < nu) : (j += 1) {
                var th: f64 = two_pi * @intToFloat(f64, @intCast(i32, k * j)) / nf;
                var c: f64 = std.math.cos(th);
                var sn: f64 = std.math.sin(th);
                sr += xr[j] * c + xi[j] * sn;
                si += xi[j] * c - xr[j] * sn;
            }
            var dr: f64 = absf(sr - re[k]);
            var di: f64 = absf(si - im[k]);
            if (dr > max) max = dr;
            if (di > max) max = di;
        }
    }
    if (max <= 1e-9) {
        std.io.print("ok\n", .{});
    } else {
        std.io.print("fail {d}\n", .{max});
    }
}
