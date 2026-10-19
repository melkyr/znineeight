// stdlib_rand_stat_xmod — std_rand (L5) statistical fixture.
//
// 2^20 u32 values from pcg32Init(0xDEADBEEF, 1):
//   - byte-frequency chi-squared over 256 bins (2^22 bytes, 16384 expected
//     per bin), pass iff < 310.5 (df=255, p=0.01);
//   - serial Pearson r over consecutive u32s, pass iff |r| < 0.01;
//   - 2^20 pcg32Bounded(7) draws: every draw < 7, bucket chi-squared
//     < 16.81 (df=6, p=0.01);
//   - pcg32Bounded(1) is always 0;
//   - xoshiroBounded bounds 2^63 and 2^64-1: every draw < bound;
//     xoshiroBounded(1) is always 0.
//
// GREEN (contract): byte-exact stdout `rand stat ok\n` and RUNRC=0.
const std = @import("std");
const rand = @import("std_rand.zig");

const N: usize = 1048576;
const SEED: u64 = 0xDEADBEEF;

var g_vals: [N]u32 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    var p = rand.pcg32Init(SEED, 1);
    var counts: [256]u32 = undefined;
    var j: usize = 0;
    while (j < 256) : (j += 1) {
        counts[j] = 0;
    }

    var i: usize = 0;
    while (i < N) : (i += 1) {
        var v: u32 = rand.pcg32Next(&p);
        g_vals[i] = v;
        counts[@intCast(usize, v & 0xFF)] += 1;
        counts[@intCast(usize, (v >> 8) & 0xFF)] += 1;
        counts[@intCast(usize, (v >> 16) & 0xFF)] += 1;
        counts[@intCast(usize, (v >> 24) & 0xFF)] += 1;
    }

    var chi2: f64 = 0.0;
    var expected: f64 = 16384.0;
    j = 0;
    while (j < 256) : (j += 1) {
        var diff: f64 = @intToFloat(f64, @intCast(i64, counts[j])) - expected;
        chi2 = chi2 + (diff * diff) / expected;
    }
    ck(chi2 < 310.5, "byte chi2");

    var sum: f64 = 0.0;
    i = 0;
    while (i < N) : (i += 1) {
        sum = sum + @intToFloat(f64, @intCast(i64, g_vals[i]));
    }
    var mean: f64 = sum / @intToFloat(f64, @intCast(i64, N));

    var sxx: f64 = 0.0;
    var syy: f64 = 0.0;
    var sxy: f64 = 0.0;
    i = 0;
    while (i + 1 < N) : (i += 1) {
        var dx: f64 = @intToFloat(f64, @intCast(i64, g_vals[i])) - mean;
        var dy: f64 = @intToFloat(f64, @intCast(i64, g_vals[i + 1])) - mean;
        sxx = sxx + dx * dx;
        syy = syy + dy * dy;
        sxy = sxy + dx * dy;
    }
    ck(sxx > 0.0 and syy > 0.0, "serial variance");
    var r2: f64 = (sxy * sxy) / (sxx * syy);
    ck(r2 < 0.0001, "serial correlation");

    var bp = rand.pcg32Init(SEED, 1);
    var buckets: [7]u32 = undefined;
    j = 0;
    while (j < 7) : (j += 1) {
        buckets[j] = 0;
    }
    i = 0;
    while (i < N) : (i += 1) {
        var b: u32 = rand.pcg32Bounded(&bp, 7);
        ck(b < 7, "bounded range");
        buckets[@intCast(usize, b)] += 1;
    }
    var expected_b: f64 = @intToFloat(f64, @intCast(i64, N)) / 7.0;
    var chi_b: f64 = 0.0;
    j = 0;
    while (j < 7) : (j += 1) {
        var diff_b: f64 = @intToFloat(f64, @intCast(i64, buckets[j])) - expected_b;
        chi_b = chi_b + (diff_b * diff_b) / expected_b;
    }
    ck(chi_b < 16.81, "bounded chi2");

    var one = rand.pcg32Init(SEED, 1);
    i = 0;
    while (i < 1000) : (i += 1) {
        ck(rand.pcg32Bounded(&one, 1) == 0, "bounded bound 1");
    }

    var bx = rand.xoshiroInit(SEED);
    i = 0;
    while (i < N) : (i += 1) {
        ck(rand.xoshiroBounded(&bx, 9223372036854775808) < 9223372036854775808, "xoshiro bound 2^63");
    }
    i = 0;
    while (i < N) : (i += 1) {
        ck(rand.xoshiroBounded(&bx, 18446744073709551615) < 18446744073709551615, "xoshiro bound 2^64-1");
    }
    var xone = rand.xoshiroInit(SEED);
    i = 0;
    while (i < 1000) : (i += 1) {
        ck(rand.xoshiroBounded(&xone, 1) == 0, "xoshiro bound 1");
    }

    std.io.write("rand stat ok\n");
}
