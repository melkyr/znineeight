// stdlib_sort_binarysearchu32_xmod — std_sort (L4) `binarySearchU32` GREEN
// fixture.
//
// Contract (blueprint §3 L4): `binarySearchU32(items: []const u32, key) ?usize`
// returns the index of `key` in a sorted (`sortU32`-ordered) slice, or null when
// absent. Requires sorted input. No allocation, no error set.
//
// Cases pinned: empty input; single element (hit + both misses); a sorted
// unique range with a hit for every element and misses between/below/above;
// duplicates (a hit for each duplicated value); and a reverse input and a
// random input, each sorted first with `sortU32` then searched for every
// original element. Every hit is checked to hold `key`.
//
// GREEN (contract): deterministic byte-exact stdout `binarySearchU32 ok\n`
// (RUNRC=0).
const std = @import("std");
const sort = @import("std_sort.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn ckFound(items: []const u32, key: u32, what: []const u8) void {
    var got = sort.binarySearchU32(items, key);
    if (got) |idx| {
        ck(idx < items.len, what);
        ck(items[idx] == key, what);
    } else {
        ck(false, what);
    }
}

fn ckMissing(items: []const u32, key: u32, what: []const u8) void {
    ck(sort.binarySearchU32(items, key) == null, what);
}

pub fn main() void {
    // empty
    var e = [_]u32{0};
    ckMissing(e[0..0], 0, "bs empty 0");
    ckMissing(e[0..0], 12345, "bs empty 12345");

    // single
    var one = [_]u32{7};
    ckFound(one[0..], 7, "bs single hit");
    ckMissing(one[0..], 6, "bs single below");
    ckMissing(one[0..], 8, "bs single above");

    // sorted unique range
    var u = [_]u32{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        ckFound(u[0..], i, "bs unique hit");
    }
    ckMissing(u[0..], 10, "bs unique above");
    ckMissing(u[0..], 99, "bs unique far");

    // duplicates
    var d = [_]u32{ 1, 1, 2, 2, 2, 3, 3, 4 };
    ckFound(d[0..], 1, "bs dup 1");
    ckFound(d[0..], 2, "bs dup 2");
    ckFound(d[0..], 3, "bs dup 3");
    ckFound(d[0..], 4, "bs dup 4");
    ckMissing(d[0..], 0, "bs dup 0");
    ckMissing(d[0..], 5, "bs dup 5");

    // reverse input, sorted first, then every element must be found
    var v = [_]u32{ 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 };
    sort.sortU32(v[0..]);
    i = 0;
    while (i < 10) : (i += 1) {
        ckFound(v[0..], i, "bs reverse hit");
    }

    // random input (with a duplicate), sorted first, then every element found
    var r = [_]u32{ 5, 3, 12, 0, 7, 42, 1, 1, 8, 20 };
    sort.sortU32(r[0..]);
    ckFound(r[0..], 5, "bs random 5");
    ckFound(r[0..], 3, "bs random 3");
    ckFound(r[0..], 12, "bs random 12");
    ckFound(r[0..], 0, "bs random 0");
    ckFound(r[0..], 7, "bs random 7");
    ckFound(r[0..], 42, "bs random 42");
    ckFound(r[0..], 1, "bs random 1");
    ckFound(r[0..], 8, "bs random 8");
    ckFound(r[0..], 20, "bs random 20");
    ckMissing(r[0..], 2, "bs random miss 2");
    ckMissing(r[0..], 100, "bs random miss 100");

    if (g_fail == 0) {
        std.io.write("binarySearchU32 ok\n");
    } else {
        std.io.write("binarySearchU32 FAIL\n");
    }
}
