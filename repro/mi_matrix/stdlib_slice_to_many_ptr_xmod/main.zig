// stdlib_slice_to_many_ptr_xmod — FC (Volume II D5) positive runtime fixture.
//
// The Language Spec "Implicit Coercion to Many-Item Pointers and Slices"
// promises a slice -> many-item-pointer coercion by extracting `.ptr`:
//   "A slice `[]T` is coerced to `[*]T` by accessing its `.ptr` field",
// allowed in declarations, assignments, argument passing and returns. The
// allowed const-adding directions must stay accepted too.
//
// Contract: stdout
//   `mp2=30 arr0=6 len=4 cmp1=20 rp3=4 first=2 csum=30 addc0=6 p2=30\n`
// rc 0, byte-exact 3x, with every observation `@panic`-guarded. The runtime
// values prove the lowering really aliases the slice's backing storage (the
// pre-fix compiler emitted a raw cast of the slice STRUCT and gcc rejected it
// with `cannot convert to a pointer type`).
//
// Shapes: in-module decl (`[]i32` -> `[*]i32`, `[]const i32` ->
// `[*]const i32`), assignment, return, cross-module argument and return, the
// const-adding directions (`[]i32` -> `[*]const i32`), and the array/`.ptr`
// controls.
const std = @import("std");
const helper = @import("helper.zig");

pub fn main() void {
    var arr = [4]i32{ 1, 2, 3, 4 };
    const sl: []i32 = arr;
    const mp: [*]i32 = sl;
    mp[2] = 30;
    if (sl[2] != 30) {
        @panic("slice did not observe the write through the [*]i32 alias");
    }

    var sl2: []i32 = arr;
    var mp2: [*]i32 = sl2;
    mp2 = sl2;
    helper.bump(mp2);
    if (arr[0] != 6) {
        @panic("cross-module bump through the [*]i32 alias failed");
    }

    const rp = helper.retMany(sl);
    if (rp[3] != 4) {
        @panic("returned [*]i32 does not alias the slice");
    }

    const carr = [3]i32{ 10, 20, 30 };
    const csl: []const i32 = carr;
    const cmp: [*]const i32 = csl;
    if (cmp[1] != 20) {
        @panic("[]const i32 -> [*]const i32 read failed");
    }

    const addc: [*]const i32 = sl;
    if (addc[0] != 6) {
        @panic("[]i32 -> [*]const i32 (const-adding) failed");
    }

    const p = sl.ptr;
    if (p[2] != 30) {
        @panic("explicit .ptr control failed");
    }

    const arr_mp: [*]i32 = arr;
    if (arr_mp[1] != 2) {
        @panic("array -> [*]i32 decay control failed");
    }

    std.io.print("mp2={} arr0={} len={} cmp1={} rp3={} first={} csum={} addc0={} p2={}\n", .{ mp[2], arr[0], sl.len, cmp[1], rp[3], helper.firstMany(sl), helper.sumConstMany(csl), addc[0], p[2] });
}
