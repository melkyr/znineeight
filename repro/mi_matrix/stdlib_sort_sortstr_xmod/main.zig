// stdlib_sort_sortstr_xmod — std_sort (L4) `sortStr` GREEN fixture.
//
// Contract (blueprint §3 L4): `sortStr(items: [][]const u8) void`. In-place
// introsort of byte slices, lexicographic (unsigned byte) order; no allocation,
// no error set, not stable.
//
// Cases pinned: random, already sorted, reverse sorted, duplicates, empty
// string and prefix ordering ("a" < "ab" < "abc" < "b" < "ba"), and an empty
// input array. Each case is compared element-for-element against its known
// sorted result.
//
// The input/expected arrays are built through an arena-backed
// `[*][]const u8` (not `[N][]const u8 = undefined`, whose -ffast zero-fill
// emits an invalid slice store today), matching the std_str_join fixture.
//
// GREEN (contract): deterministic byte-exact stdout `sortStr ok\n` (RUNRC=0).
const std = @import("std");
const sort = @import("std_sort.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn allocStrs(ar: *std.arena.Arena, n: usize) [][]const u8 {
    var raw = std.arena.alloc(ar, n * @sizeOf([]const u8)) catch {
        @panic("allocStrs");
    };
    var p: [*][]const u8 = @ptrCast([*][]const u8, raw);
    return p[0..n];
}

fn ckStr(got: [][]const u8, want: [][]const u8, what: []const u8) void {
    ck(got.len == want.len, what);
    var i: usize = 0;
    while (i < got.len) : (i += 1) {
        ck(std.str.eql(got[i], want[i]), what);
    }
}

pub fn main() void {
    var backing: [2048]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    // random
    var r = allocStrs(&ar, 6);
    r[0] = "banana";
    r[1] = "apple";
    r[2] = "cherry";
    r[3] = "date";
    r[4] = "fig";
    r[5] = "grape";
    var rw = allocStrs(&ar, 6);
    rw[0] = "apple";
    rw[1] = "banana";
    rw[2] = "cherry";
    rw[3] = "date";
    rw[4] = "fig";
    rw[5] = "grape";
    sort.sortStr(r);
    ckStr(r, rw, "str random");

    // already sorted
    var s = allocStrs(&ar, 5);
    s[0] = "a";
    s[1] = "b";
    s[2] = "c";
    s[3] = "d";
    s[4] = "e";
    var sw = allocStrs(&ar, 5);
    sw[0] = "a";
    sw[1] = "b";
    sw[2] = "c";
    sw[3] = "d";
    sw[4] = "e";
    sort.sortStr(s);
    ckStr(s, sw, "str sorted");

    // reverse
    var v = allocStrs(&ar, 5);
    v[0] = "e";
    v[1] = "d";
    v[2] = "c";
    v[3] = "b";
    v[4] = "a";
    var vw = allocStrs(&ar, 5);
    vw[0] = "a";
    vw[1] = "b";
    vw[2] = "c";
    vw[3] = "d";
    vw[4] = "e";
    sort.sortStr(v);
    ckStr(v, vw, "str reverse");

    // duplicates
    var d = allocStrs(&ar, 6);
    d[0] = "bb";
    d[1] = "a";
    d[2] = "bb";
    d[3] = "a";
    d[4] = "c";
    d[5] = "a";
    var dw = allocStrs(&ar, 6);
    dw[0] = "a";
    dw[1] = "a";
    dw[2] = "a";
    dw[3] = "bb";
    dw[4] = "bb";
    dw[5] = "c";
    sort.sortStr(d);
    ckStr(d, dw, "str dup");

    // prefixes + empty string
    var p = allocStrs(&ar, 6);
    p[0] = "a";
    p[1] = "ab";
    p[2] = "abc";
    p[3] = "b";
    p[4] = "ba";
    p[5] = "";
    var pw = allocStrs(&ar, 6);
    pw[0] = "";
    pw[1] = "a";
    pw[2] = "ab";
    pw[3] = "abc";
    pw[4] = "b";
    pw[5] = "ba";
    sort.sortStr(p);
    ckStr(p, pw, "str prefix");

    // empty array
    var e = allocStrs(&ar, 1);
    e[0] = "x";
    sort.sortStr(e[0..0]);
    ck(e[0].len == 1, "str empty noop");

    if (g_fail == 0) {
        std.io.write("sortStr ok\n");
    } else {
        std.io.write("sortStr FAIL\n");
    }
}
