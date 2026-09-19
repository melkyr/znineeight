// stdlib_sort_sortu32_xmod — std_sort (L4) `sortU32` GREEN fixture.
//
// Contract (blueprint §3 L4): `sortU32(items: []u32) void`. In-place introsort
// through the module's internal vtable; no allocation, no error set, not stable.
//
// Cases pinned: random, already sorted, reverse sorted, duplicates, empty /
// single-element, plus the unsigned extremes 0 and 0xFFFFFFFF (the full u32
// range; no sentinel is reserved). Each case is compared element-for-element
// against its known sorted result.
//
// GREEN (contract): deterministic byte-exact stdout `sortU32 ok\n` (RUNRC=0).
const std = @import("std");
const sort = @import("std_sort.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn ckU32(got: []u32, want: []const u32, what: []const u8) void {
    ck(got.len == want.len, what);
    var i: usize = 0;
    while (i < got.len) : (i += 1) {
        ck(got[i] == want[i], what);
    }
}

pub fn main() void {
    var r = [_]u32{ 5, 3, 12, 0, 7, 42, 1, 1, 8, 20 };
    var rw = [_]u32{ 0, 1, 1, 3, 5, 7, 8, 12, 20, 42 };
    sort.sortU32(r[0..]);
    ckU32(r[0..], rw[0..], "u32 random");

    var s = [_]u32{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    var sw = [_]u32{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    sort.sortU32(s[0..]);
    ckU32(s[0..], sw[0..], "u32 sorted");

    var v = [_]u32{ 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 };
    var vw = [_]u32{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    sort.sortU32(v[0..]);
    ckU32(v[0..], vw[0..], "u32 reverse");

    var d = [_]u32{ 3, 1, 3, 2, 1, 3, 2, 1, 2, 3 };
    var dw = [_]u32{ 1, 1, 1, 2, 2, 2, 3, 3, 3, 3 };
    sort.sortU32(d[0..]);
    ckU32(d[0..], dw[0..], "u32 dup");

    // unsigned extremes
    var e = [_]u32{ 0xFFFFFFFF, 0, 0x80000000, 7, 0xFFFFFFFF, 0 };
    var ew = [_]u32{ 0, 0, 7, 0x80000000, 0xFFFFFFFF, 0xFFFFFFFF };
    sort.sortU32(e[0..]);
    ckU32(e[0..], ew[0..], "u32 extremes");

    var one = [_]u32{0xFFFFFFFF};
    sort.sortU32(one[0..]);
    ckU32(one[0..], one[0..], "u32 one");

    var none = [_]u32{0};
    sort.sortU32(none[0..0]);
    ck(none[0] == 0, "u32 empty noop");

    if (g_fail == 0) {
        std.io.write("sortU32 ok\n");
    } else {
        std.io.write("sortU32 FAIL\n");
    }
}
