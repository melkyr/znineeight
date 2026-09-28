// ptr_array_slice_reject_xmod — FX5 many-item-pointer open-end reject fixture.
//
// DEFECT (before FX5): an open-ended many-item-pointer slice (`mp[s..]`) is a
// lowering-path `error[3043]` ICE (rc 3, no C). Zig 0.15.2 accepts the shape
// only because it yields `[*]T`; Z98's many-pointer slice result is `[]T` and a
// many-item pointer carries no length, so FX5 clean-rejects it `error[3067]`
// (`slice of many-item pointer must be bounded`) at level 0, deduped per node,
// rc 2 / 0 `.c` — never an ICE. A struct/union array FIELD is exempt (its
// declared length is the effective end and stays accepted).
//
// EXPECTED: rc 2, 0 `.c`, one `error[3067]` per site (6 sites: four locals, a
// global, a parameter, and the cross-module helper), plus the pre-existing
// void-declaration cascade (`error[3000]` x4); no `error[3043]`.
const std = @import("std");
const helper = @import("helper.zig");

var g_arr = [4]i32{ 10, 20, 30, 40 };
var g_mp: [*]i32 = &g_arr;

fn openParam(p: [*]i32, a: usize) []i32 {
    return p[a..];
}

pub fn main() void {
    var arr = [4]i32{ 10, 20, 30, 40 };
    const mp: [*]i32 = &arr;
    var a: usize = 1;
    const s0 = mp[0..];
    const s1 = mp[1..];
    const s2 = mp[a..];
    const s3 = g_mp[2..];
    const s4 = helper.open(mp);
    const s5 = openParam(mp, a);
    _ = s0;
    _ = s1;
    _ = s2;
    _ = s3;
    _ = s4;
    _ = s5;
}
