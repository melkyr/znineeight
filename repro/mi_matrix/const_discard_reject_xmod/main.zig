// const_discard_reject_xmod — FC (Volume II D12) reject fixture.
//
// Language Spec "Type Coercions / Const Correctness": "Coercions are only
// allowed if they do not discard const qualifiers"; the `[]const T` -> `[*]T`
// bullet is explicitly Forbidden. Every const-discarding shape must reject
// level-0 `error[3000]: cannot implicitly discard 'const' qualifier`, rc 2 /
// 0 `.c`, and the LEGAL const-adding directions in the same program must add
// no diagnostic at all.
//
// Shapes (exact census, re-counted from the FC compiler run; all sites are
// runtime `const` bindings so no comptime fold can hide them):
//   local decl `[]const i32` -> `[]i32` / `[*]i32`
//   assignment `[]const i32` -> `[]i32` / `[*]i32`
//   module var `[]const i32` -> `[]i32` / `[*]i32`
//   return `[]const i32` -> `[]i32` / `[*]i32`
//   call arg `[]const i32` -> `[]i32` / `[*]i32`    (same module)
//   field init `[]const i32` -> `[]i32` / `[*]i32`
//   `*const i32` -> `*i32`
//   `[*]const i32` -> `[*]i32`
//   cross-module call args `[]const i32` -> `[]i32` / `[*]i32`
//   cross-module return `[]const i32` -> `[]i32`
// => 17 x error[3000], 0 x warning[3000], 0 other error codes.
//
// Legal (must stay silent here): `[]i32` -> `[]const i32`, `[]i32` ->
// `[*]const i32`, `[]const i32` -> `[*]const i32`, `*i32` -> `*const i32`,
// `[*]i32` -> `[*]const i32`, array -> slice/many decays.
const std = @import("std");
const helper = @import("helper.zig");

const Holder = struct { m: []i32 };
const ManyHolder = struct { mp: [*]i32 };

var garr: [3]i32 = [3]i32{ 1, 2, 3 };
const gc: []const i32 = garr;
var gm: []i32 = gc; // module var, slice -> slice
var gmp: [*]i32 = gc; // module var, slice -> many

fn takeSlice(m: []i32) void {
    m[0] = 9;
}

fn takeMany(mp: [*]i32) void {
    mp[0] = 9;
}

fn retSlice(c: []const i32) []i32 {
    return c;
}

fn retMany(c: []const i32) [*]i32 {
    return c;
}

pub fn main() void {
    var arr = [3]i32{ 1, 2, 3 };
    const c: []const i32 = arr;

    // local decl
    var m: []i32 = c;
    var mp: [*]i32 = c;

    // assignment
    var am: []i32 = arr;
    am = c;
    var amp: [*]i32 = arr;
    amp = c;

    // return
    const rm = retSlice(c);
    const rp = retMany(c);

    // call arg (same module)
    takeSlice(c);
    takeMany(c);

    // field init
    var h: Holder = .{ .m = c };
    var mh: ManyHolder = .{ .mp = c };

    // pointer families
    const pc: *const i32 = &arr[0];
    const q: *i32 = pc;
    const mpc: [*]const i32 = arr;
    const mpq: [*]i32 = mpc;

    // cross-module
    helper.takeSlice(c);
    helper.takeMany(c);
    const xr = helper.retSlice(c);

    // legal const-adding directions: must add NO diagnostic
    const okc: []const i32 = arr;
    const okmc: [*]const i32 = arr;
    const okcc: [*]const i32 = okc;
    const okp: *const i32 = &arr[0];
    const okmp: [*]const i32 = amp;

    m[0] = 9;
    mp[0] = 9;
    am[0] = 9;
    amp[0] = 9;
    rm[0] = 9;
    rp[0] = 9;
    h.m[0] = 9;
    mh.mp[0] = 9;
    q.* = 9;
    mpq[0] = 9;
    xr[0] = 9;
    _ = okc;
    _ = okmc;
    _ = okcc;
    _ = okp;
    _ = okmp;
    _ = gm;
    _ = gmp;
    std.io.print("unreachable\n", .{});
}
