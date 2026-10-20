// stdlib_noise_basic_xmod — std_noise (L5) basic/visual GREEN fixture.
//
// Checks:
//   - range: 100k deterministic samples (50k noise2d + 50k noise3d) in [-1,1];
//   - continuity: |n(x,y) - n(x+0.0001,y)| < 0.001 over 1000 points;
//   - determinism: two opensimplexInit(seed) instances produce bit-identical
//     samples (500 2D + 500 3D);
//   - noiseFbm2d(..., octaves=0) == 0.0;
//   - visual golden: FNV-1a 64 hash of a 256x256 PGM built from noiseFbm2d.
//
// GREEN (contract): byte-exact stdout `expected.txt` (RUNRC=0). A mismatch
// calls @panic.
const std = @import("std");
const noise = @import("std_noise.zig");

const SEED: u64 = 3735928559;
const VISUAL_SEED: u64 = 12648430;
const FNV_OFFSET: u64 = 14695981039346656037;
const FNV_PRIME: u64 = 1099511628211;

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn bitsOf(v: f64) u64 {
    var p: *u64 = @ptrCast(*u64, &v);
    return p.*;
}

fn hexChar(v: u64) u8 {
    if (v < 10) return @intCast(u8, @intCast(u32, '0') + @intCast(u32, v));
    return @intCast(u8, @intCast(u32, 'a') + @intCast(u32, v - 10));
}

fn writeHex16(v: u64) void {
    var buf: [16]u8 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        var sh: u64 = @intCast(u64, (15 - i) * 4);
        buf[i] = hexChar((v >> sh) & 15);
    }
    std.io.write(buf[0..16]);
}

fn fnvByte(h: u64, b: u8) u64 {
    return (h ^ @intCast(u64, b)) *% FNV_PRIME;
}

fn fnvStr(h: u64, s: []const u8) u64 {
    var out: u64 = h;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        out = fnvByte(out, s[i]);
    }
    return out;
}

fn fbmByte(v: f64) u8 {
    if (v <= -1.0) return 0;
    var i: u32 = 0;
    while (i < 255) : (i += 1) {
        var hi: f64 = -1.0 + @intToFloat(f64, i + 1) * (2.0 / 255.0);
        if (v < hi) return @intCast(u8, i);
    }
    return 255;
}

fn checkRange(n: *const noise.OpenSimplex) void {
    var i: u32 = 0;
    while (i < 50000) : (i += 1) {
        var fi: f64 = @intToFloat(f64, i);
        var x: f64 = fi * 0.0137 - 3.25;
        var y: f64 = fi * 0.0071 + 1.75;
        var v: f64 = noise.noise2d(n, x, y);
        ck(v >= -1.0 and v <= 1.0, "range 2d");
    }
    while (i < 100000) : (i += 1) {
        var fi: f64 = @intToFloat(f64, i);
        var x: f64 = fi * 0.0137 - 3.25;
        var y: f64 = fi * 0.0071 + 1.75;
        var z: f64 = fi * 0.0033 - 0.5;
        var v: f64 = noise.noise3d(n, x, y, z);
        ck(v >= -1.0 and v <= 1.0, "range 3d");
    }
    std.io.write("range ok\n");
}

fn checkContinuity(n: *const noise.OpenSimplex) void {
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        var fi: f64 = @intToFloat(f64, i);
        var x: f64 = fi * 0.017 - 5.0;
        var y: f64 = fi * 0.011 + 2.0;
        var d: f64 = noise.noise2d(n, x, y) - noise.noise2d(n, x + 0.0001, y);
        if (d < 0.0) d = -d;
        ck(d < 0.001, "continuity");
    }
    std.io.write("continuity ok\n");
}

fn checkDeterminism() void {
    var a = noise.opensimplexInit(SEED);
    var b = noise.opensimplexInit(SEED);
    var i: u32 = 0;
    while (i < 500) : (i += 1) {
        var fi: f64 = @intToFloat(f64, i);
        var x: f64 = fi * 0.021 - 2.5;
        var y: f64 = fi * 0.013 + 0.75;
        ck(bitsOf(noise.noise2d(&a, x, y)) == bitsOf(noise.noise2d(&b, x, y)), "det 2d");
    }
    while (i < 1000) : (i += 1) {
        var fi: f64 = @intToFloat(f64, i);
        var x: f64 = fi * 0.021 - 2.5;
        var y: f64 = fi * 0.013 + 0.75;
        var z: f64 = fi * 0.009 - 1.25;
        ck(bitsOf(noise.noise3d(&a, x, y, z)) == bitsOf(noise.noise3d(&b, x, y, z)), "det 3d");
    }
    std.io.write("determinism ok\n");
}

fn checkOctavesZero(n: *const noise.OpenSimplex) void {
    ck(noise.noiseFbm2d(n, 0.5, -0.25, 0, 2.0, 0.5) == 0.0, "fbm octaves 0");
    std.io.write("fbm0 ok\n");
}

fn visualHash() u64 {
    var n = noise.opensimplexInit(VISUAL_SEED);
    var h: u64 = fnvStr(FNV_OFFSET, "P5\n256 256\n255\n");
    var y: u32 = 0;
    while (y < 256) : (y += 1) {
        var fy: f64 = @intToFloat(f64, y);
        var x: u32 = 0;
        while (x < 256) : (x += 1) {
            var fx: f64 = @intToFloat(f64, x);
            var v: f64 = noise.noiseFbm2d(&n, fx * 0.08, fy * 0.08, 4, 2.0, 0.5);
            h = fnvByte(h, fbmByte(v));
        }
    }
    return h;
}

pub fn main() void {
    ck(@sizeOf(noise.OpenSimplex) == 512, "state size");
    var n = noise.opensimplexInit(SEED);
    checkRange(&n);
    checkContinuity(&n);
    checkDeterminism();
    checkOctavesZero(&n);

    var h: u64 = visualHash();
    std.io.write("pgm fnv1a64 ");
    writeHex16(h);
    std.io.write("\n");

    if (g_fail == 0) {
        std.io.write("noise basic ok\n");
    } else {
        std.io.write("noise basic FAIL\n");
    }
}
