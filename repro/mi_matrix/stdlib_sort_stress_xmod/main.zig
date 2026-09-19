// stdlib_sort_stress_xmod — STDLIB std_sort (L4) hand-written stress table.
//
// No PRNG: the only "random" input is an explicit fixed-seed LCG loop written
// out in `fillLcg` (literal seed 0x12345678); every other input is an explicit
// table/pattern. Stresses:
//   - 4096 full-range u32 (LCG): sorted after sortU32; permutation pinned by a
//     256-bucket high-byte histogram + u64 sum + u32 xor before == after;
//   - 2048 bounded u32 (0..255, LCG): exact 256-value histogram before == after;
//   - ascending 2048, descending 2048, 2048-value duplicates (0..4), 1000
//     all-equal, unsigned extremes, empty and single element;
//   - binarySearchU32 on the sorted arrays and on a written table, for present
//     and absent keys.
//
// GREEN (contract): deterministic byte-exact stdout `sort stress ok\n` (RUNRC=0).
const std = @import("std");
const sort = @import("std_sort.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn fillLcg(dst: []u32, seed: u32) void {
    var st: u32 = seed;
    var i: usize = 0;
    while (i < dst.len) : (i += 1) {
        st = st *% 1664525 +% 1013904223;
        dst[i] = st;
    }
}

fn isSorted(a: []const u32) bool {
    var i: usize = 1;
    while (i < a.len) : (i += 1) {
        if (a[i - 1] > a[i]) return false;
    }
    return true;
}

fn sumU32(a: []const u32) u64 {
    var s: u64 = 0;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        s = s +% @intCast(u64, a[i]);
    }
    return s;
}

fn xorU32(a: []const u32) u32 {
    var x: u32 = 0;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        x = x ^ a[i];
    }
    return x;
}

fn hist256(a: []const u32, h: []u32) void {
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        h[i] = 0;
    }
    i = 0;
    while (i < a.len) : (i += 1) {
        h[@intCast(usize, a[i] & 0xFF)] += 1;
    }
}

fn histHigh(a: []const u32, h: []u32) void {
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        h[i] = 0;
    }
    i = 0;
    while (i < a.len) : (i += 1) {
        h[@intCast(usize, a[i] >> 24)] += 1;
    }
}

fn ckHist(h0: []const u32, h1: []const u32, what: []const u8) void {
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        ck(h0[i] == h1[i], what);
    }
}

fn searchIs(a: []const u32, key: u32, what: []const u8) void {
    var got = sort.binarySearchU32(a, key);
    if (got) |idx| {
        ck(a[idx] == key, what);
    } else {
        ck(false, what);
    }
}

fn searchNull(a: []const u32, key: u32, what: []const u8) void {
    ck(sort.binarySearchU32(a, key) == null, what);
}

var g_a: [4096]u32 = undefined;
var g_b: [2048]u32 = undefined;
var g_h0: [256]u32 = undefined;
var g_h1: [256]u32 = undefined;

pub fn main() void {
    // ---- A: full-range LCG, permutation via high-byte histogram + sum + xor --
    fillLcg(g_a[0..4096], 0x12345678);
    histHigh(g_a[0..4096], g_h0[0..]);
    var s0 = sumU32(g_a[0..4096]);
    var x0 = xorU32(g_a[0..4096]);
    sort.sortU32(g_a[0..4096]);
    ck(isSorted(g_a[0..4096]), "A sorted");
    histHigh(g_a[0..4096], g_h1[0..]);
    ckHist(g_h0[0..], g_h1[0..], "A high-byte histogram");
    ck(sumU32(g_a[0..4096]) == s0, "A sum preserved");
    ck(xorU32(g_a[0..4096]) == x0, "A xor preserved");
    searchIs(g_a[0..4096], g_a[0], "A search first");
    searchIs(g_a[0..4096], g_a[2048], "A search mid");
    searchIs(g_a[0..4096], g_a[4095], "A search last");
    searchNull(g_a[0..4096], 0xFFFFFFF0, "A search absent");
    searchNull(g_a[0..4096], 0x0000000F, "A search absent low");

    // ---- B: bounded values 0..255, exact histogram -------------------------
    fillLcg(g_b[0..2048], 0x9E3779B9);
    var i: usize = 0;
    while (i < 2048) : (i += 1) {
        g_b[i] = g_b[i] & 0xFF;
    }
    hist256(g_b[0..2048], g_h0[0..]);
    sort.sortU32(g_b[0..2048]);
    ck(isSorted(g_b[0..2048]), "B sorted");
    hist256(g_b[0..2048], g_h1[0..]);
    ckHist(g_h0[0..], g_h1[0..], "B exact histogram");
    searchIs(g_b[0..2048], 0, "B search 0");
    searchIs(g_b[0..2048], 255, "B search 255");
    searchNull(g_b[0..2048], 256, "B search 256");

    // ---- C: ascending ------------------------------------------------------
    i = 0;
    while (i < 2048) : (i += 1) {
        g_b[i] = @intCast(u32, i) * 3;
    }
    sort.sortU32(g_b[0..2048]);
    i = 0;
    while (i < 2048) : (i += 1) {
        ck(g_b[i] == @intCast(u32, i) * 3, "C ascending stable");
    }

    // ---- D: descending -----------------------------------------------------
    i = 0;
    while (i < 2048) : (i += 1) {
        g_b[i] = @intCast(u32, 2048 - i) * 3;
    }
    sort.sortU32(g_b[0..2048]);
    i = 0;
    while (i < 2048) : (i += 1) {
        ck(g_b[i] == @intCast(u32, i + 1) * 3, "D descending -> ascending");
    }

    // ---- E: duplicates 0..4 ------------------------------------------------
    i = 0;
    while (i < 2048) : (i += 1) {
        g_b[i] = @intCast(u32, (i * 7) % 5);
    }
    hist256(g_b[0..2048], g_h0[0..]);
    sort.sortU32(g_b[0..2048]);
    ck(isSorted(g_b[0..2048]), "E sorted");
    hist256(g_b[0..2048], g_h1[0..]);
    ckHist(g_h0[0..], g_h1[0..], "E duplicate histogram");

    // ---- F: all-equal ------------------------------------------------------
    i = 0;
    while (i < 1000) : (i += 1) {
        g_b[i] = 0xDEADBEEF;
    }
    sort.sortU32(g_b[0..1000]);
    i = 0;
    while (i < 1000) : (i += 1) {
        ck(g_b[i] == 0xDEADBEEF, "F all equal");
    }

    // ---- G: extremes -------------------------------------------------------
    var ex = [_]u32{ 0xFFFFFFFF, 0, 0x80000000, 0x7FFFFFFF, 1, 0xFFFFFFFE, 0x80000001 };
    var exw = [_]u32{ 0, 1, 0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFE, 0xFFFFFFFF };
    sort.sortU32(ex[0..]);
    i = 0;
    while (i < ex.len) : (i += 1) {
        ck(ex[i] == exw[i], "G extremes");
    }

    // ---- H: empty + single -------------------------------------------------
    var none = [_]u32{0};
    sort.sortU32(none[0..0]);
    ck(none[0] == 0, "H empty noop");
    var one = [_]u32{0xFFFFFFFF};
    sort.sortU32(one[0..]);
    ck(one[0] == 0xFFFFFFFF, "H single");

    // ---- I: binarySearchU32 table ------------------------------------------
    var bs = [_]u32{ 0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89 };
    searchIs(bs[0..], 0, "I 0");
    searchIs(bs[0..], 1, "I 1 dup");
    searchIs(bs[0..], 2, "I 2");
    searchIs(bs[0..], 13, "I 13");
    searchIs(bs[0..], 89, "I 89");
    searchNull(bs[0..], 4, "I absent 4");
    searchNull(bs[0..], 90, "I absent 90");
    searchNull(bs[0..], 0xFFFFFFFF, "I absent max");
    searchNull(none[0..0], 0, "I empty array null");

    if (g_fail == 0) {
        std.io.write("sort stress ok\n");
    } else {
        std.io.write("sort stress FAIL\n");
    }
}
