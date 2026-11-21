// stdlib_sort_sorti32_xmod — std_sort (L4) `sortI32` GREEN fixture.
//
// Contract (blueprint §3 L4): `sortI32(items: []i32) void`. In-place introsort
// through the module's internal vtable; no allocation, no error set, not stable.
//
// Cases pinned: random (mixed signs), already sorted, reverse sorted,
// duplicates, and empty / single-element inputs. Each case is compared
// element-for-element against its known sorted result.
//
// GREEN (contract): deterministic byte-exact stdout `sortI32 ok\n` (RUNRC=0).
const std = @import("std");
const sort = @import("std_sort.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn ckI32(got: []i32, want: []const i32, what: []const u8) void {
    ck(got.len == want.len, what);
    var i: usize = 0;
    while (i < got.len) : (i += 1) {
        ck(got[i] == want[i], what);
    }
}

pub fn main() void {
    var r = [_]i32{ 5, -3, 12, 0, -7, 42, 1, -1, 8, -20 };
    var rw = [_]i32{ -20, -7, -3, -1, 0, 1, 5, 8, 12, 42 };
    sort.sortI32(r[0..]);
    ckI32(r[0..], rw[0..], "i32 random");

    var s = [_]i32{ -5, -4, -3, -2, -1, 0, 1, 2, 3, 4 };
    var sw = [_]i32{ -5, -4, -3, -2, -1, 0, 1, 2, 3, 4 };
    sort.sortI32(s[0..]);
    ckI32(s[0..], sw[0..], "i32 sorted");

    var v = [_]i32{ 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 };
    var vw = [_]i32{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    sort.sortI32(v[0..]);
    ckI32(v[0..], vw[0..], "i32 reverse");

    var d = [_]i32{ 3, 1, 3, 2, 1, 3, 2, 1, 2, 3 };
    var dw = [_]i32{ 1, 1, 1, 2, 2, 2, 3, 3, 3, 3 };
    sort.sortI32(d[0..]);
    ckI32(d[0..], dw[0..], "i32 dup");

    var one = [_]i32{-9};
    sort.sortI32(one[0..]);
    ckI32(one[0..], one[0..], "i32 one");

    var none = [_]i32{0};
    sort.sortI32(none[0..0]);
    ck(none[0] == 0, "i32 empty noop");

    if (g_fail == 0) {
        std.io.write("sortI32 ok\n");
    } else {
        std.io.write("sortI32 FAIL\n");
    }
}
