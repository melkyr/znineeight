// stdlib_test/noise_lz4_usage — M2 Task 3 usage program (R7b pattern).
//
// Composes std_rand (L5) + std_noise (L5) + std_lz4 (L4) into one intended
// workflow: expand a fixed seed with xoshiro256**, seed an OpenSimplex state
// from that value, sample and range-check 2D/3D noise, confirm identical
// initializations are bit-identical, check the fBm zero-octave precondition,
// then decode one embedded all-literals LZ4 block.
//
// Fixed seed and inputs only: no clock, environment, PID or address input.
//
// GREEN (contract): deterministic byte-exact stdout (RUNRC=0):
//   range: 128 ok
//   determinism: 128 ok
//   fbm0: 0.0
//   lz4: 16 bytes
//   noise_lz4 ok
// A mismatch increments g_fail and calls @panic; the final line is
// `noise_lz4 ok` only when g_fail == 0.
const std = @import("std");
const std_rand = @import("std_rand.zig");
const std_noise = @import("std_noise.zig");
const std_lz4 = @import("std_lz4.zig");

const SEED: u64 = 0x5EED1234;

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

fn seedFromRand() u64 {
    var r = std_rand.xoshiroInit(SEED);
    return std_rand.xoshiroNext(&r);
}

fn checkRange(n: *const std_noise.OpenSimplex) u32 {
    var count: u32 = 0;
    var i: u32 = 0;
    while (i < 64) : (i += 1) {
        var fi: f64 = @intToFloat(f64, i);
        var x: f64 = fi * 0.031 - 4.0;
        var y: f64 = fi * 0.017 + 1.5;
        var v2: f64 = std_noise.noise2d(n, x, y);
        ck(v2 >= -1.0 and v2 <= 1.0, "noise2d range");
        count += 1;

        var z: f64 = fi * 0.009 - 0.75;
        var v3: f64 = std_noise.noise3d(n, x, y, z);
        ck(v3 >= -1.0 and v3 <= 1.0, "noise3d range");
        count += 1;
    }
    return count;
}

fn checkDeterminism(seed: u64) u32 {
    var a = std_noise.opensimplexInit(seed);
    var b = std_noise.opensimplexInit(seed);
    var count: u32 = 0;
    var i: u32 = 0;
    while (i < 64) : (i += 1) {
        var fi: f64 = @intToFloat(f64, i);
        var x: f64 = fi * 0.023 - 2.0;
        var y: f64 = fi * 0.011 + 0.5;
        ck(bitsOf(std_noise.noise2d(&a, x, y)) == bitsOf(std_noise.noise2d(&b, x, y)), "det 2d");
        count += 1;

        var z: f64 = fi * 0.007 - 1.0;
        ck(bitsOf(std_noise.noise3d(&a, x, y, z)) == bitsOf(std_noise.noise3d(&b, x, y, z)), "det 3d");
        count += 1;
    }
    return count;
}

fn checkLz4() u32 {
    var dst: [64]u8 = undefined;
    var got = std_lz4.lz4DecompressBlock(lz4_block[0..], dst[0..]) catch {
        g_fail += 1;
        @panic("lz4 decode");
    };
    ck(got == @intCast(u32, lz4_raw.len), "lz4 length");
    var i: usize = 0;
    while (i < lz4_raw.len) : (i += 1) {
        ck(dst[i] == lz4_raw[i], "lz4 byte");
    }
    return got;
}

pub fn main() void {
    // Seed std_noise from a xoshiro256** expansion of the fixed seed.
    var seed: u64 = seedFromRand();
    var n = std_noise.opensimplexInit(seed);

    var range_count: u32 = checkRange(&n);
    std.io.write("range: 128 ok\n");

    var det_count: u32 = checkDeterminism(seed);
    std.io.write("determinism: 128 ok\n");

    ck(range_count == 128, "range count");
    ck(det_count == 128, "determinism count");

    var fbm_zero: f64 = std_noise.noiseFbm2d(&n, 0.5, -0.25, 0, 2.0, 0.5);
    ck(fbm_zero == 0.0, "fbm octaves 0");
    std.io.write("fbm0: 0.0\n");

    var lz4_len: u32 = checkLz4();
    std.io.write("lz4: 16 bytes\n");
    ck(lz4_len == 16, "lz4 summary length");

    if (g_fail == 0) {
        std.io.write("noise_lz4 ok\n");
    } else {
        std.io.write("noise_lz4 FAIL\n");
    }
}

// Valid LZ4 block containing only literals: token 0xF0 (15 + extension 1 =
// 16 literal bytes), no match, so the final sequence is all literals.
const lz4_block = [_]u8{
    0xF0, 0x01, 0x5A, 0x39, 0x38, 0x20, 0x6C, 0x7A, 0x34, 0x20, 0x6C, 0x69,
    0x74, 0x65, 0x72, 0x61, 0x6C, 0x73,
};

const lz4_raw = [_]u8{
    0x5A, 0x39, 0x38, 0x20, 0x6C, 0x7A, 0x34, 0x20, 0x6C, 0x69, 0x74, 0x65,
    0x72, 0x61, 0x6C, 0x73,
};
