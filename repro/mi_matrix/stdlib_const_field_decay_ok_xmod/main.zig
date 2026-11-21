// stdlib_const_field_decay_ok_xmod — FX11 (Volume II) positive runtime fixture.
//
// FX11 extends the FX6 const-decay guarantee to an aggregate's array FIELD: a
// const aggregate's array field must not decay/alias/copy into a mutable
// slice, many-pointer, pointer or element site. This fixture pins the LEGAL
// directions so the closure does not over-reject:
//   * mutable aggregate field (`var ms: S`) -> `[]i32` / `[*]i32` / `*[3]i32`
//     with writes through all three read back;
//   * const aggregate field, in-module and cross-module: `gs.a[0..]` ->
//     `[]const i32` / `[*]const i32`, `&gs.a` -> `*const [3]i32` /
//     `[]const i32` / `[*]const i32`, `gs.a` -> `*const i32`;
//   * const array-field -> const return (`retConstField`) and const call
//     arguments (local and cross-module helpers);
//   * a `[]const i32` slice FIELD of a const aggregate re-slices to
//     `[]const`/`[*]const`;
//   * a const-bound aggregate with a MUTABLE `[]i32` slice field keeps
//     element mutability (`hbm.m[0..]` stays `[]i32`);
//   * a const-adding array-literal element (`[1][]const i32{ gs.a[0..] }`).
//
// Both aggregates are initialised from a named `garr` binding: the inline
// nested-array-literal field initializer (`.a = .{ 1, 2, 3 }`) is a separate,
// PRE-EXISTING lowering gap (it zeroes the field and drops the element tuple)
// and is deliberately not exercised here.
//
// Contract: stdout line below (see expected.txt), rc 0, byte-exact 3x, every
// observation `@panic`-guarded.
const std = @import("std");
const helper = @import("helper.zig");

const S = struct { a: [3]i32 };
const garr = [3]i32{ 1, 2, 3 };
const gs: S = .{ .a = garr };

const HolderC = struct { m: []const i32 };
const HolderM = struct { m: []i32 };

fn retConstField(p: *const [3]i32) []const i32 {
    return p[0..];
}

pub fn main() void {
    // Mutable aggregate field: slice / many / pointer decay, writes allowed.
    var ms: S = .{ .a = garr };
    var s3: []i32 = ms.a[0..];
    var m3: [*]i32 = ms.a[0..];
    var p3: *[3]i32 = &ms.a;
    s3[0] = 7;
    m3[1] = 8;
    p3[2] = 9;
    if (ms.a[0] != 7 or ms.a[1] != 8 or ms.a[2] != 9) {
        @panic("mutable aggregate field writes failed");
    }
    helper.bumpMut(ms.a[0..]);
    if (ms.a[0] != 8) {
        @panic("mutable aggregate field cross-module write failed");
    }

    // Const aggregate field: every const-adding direction (in-module).
    const s1: []const i32 = gs.a[0..];
    const m1: [*]const i32 = gs.a[0..];
    const p1: *const [3]i32 = &gs.a;
    const sa: []const i32 = &gs.a;
    const ma: [*]const i32 = &gs.a;
    const q1: *const i32 = gs.a;
    const lc: S = .{ .a = garr };
    const ls: []const i32 = lc.a[0..];
    const fromRet: []const i32 = retConstField(&gs.a);

    // Const aggregate field: cross-module (helper.gs).
    const x1: []const i32 = helper.gs.a[0..];
    const x2: [*]const i32 = helper.gs.a[0..];
    const xp: *const [3]i32 = &helper.gs.a;
    const xr: []const i32 = helper.retConstField(&helper.gs.a);
    const xsum = helper.sumConst(helper.gs.a[0..]);
    const xmany = helper.sumConstMany(helper.gs.a[0..]);

    // Const slice field of a const aggregate; const-bound mutable slice field.
    const hc: HolderC = .{ .m = garr };
    const hcs: []const i32 = hc.m[0..];
    const hcm: [*]const i32 = hc.m[0..];
    const hbm: HolderM = .{ .m = ms.a[0..] };
    var hres: []i32 = hbm.m[0..];
    hres[1] = 44;
    if (ms.a[1] != 44) {
        @panic("const-bound mutable slice field reslice failed");
    }

    // Const-adding array-literal element from a const aggregate field.
    const els = [1][]const i32{ gs.a[0..] };

    if (s1[0] + s1[2] + m1[1] + p1[2] + sa[1] + ma[2] + q1.* + ls[2] + fromRet[0] != 19) {
        @panic("const aggregate field reads failed");
    }
    if (x1[0] + x2[2] + xp[1] + xr[0] + xsum + xmany != 49) {
        @panic("cross-module const aggregate field reads failed");
    }
    if (hcs[1] + hcm[2] + els[0][2] != 8) {
        @panic("const slice field / element reads failed");
    }
    std.io.print("cfd={} {} {} {} {} {} {} {} {} {} {} {} {} {} {}\n", .{ s1[0], s1[2], m1[1], p1[2], sa[1], ma[2], q1.*, ls[2], fromRet[0], x1[0], x2[2], xp[1], xr[0], hcs[1], els[0][2] });
}
