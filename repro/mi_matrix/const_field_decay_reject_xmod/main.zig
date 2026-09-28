// const_field_decay_reject_xmod — FX11 (Volume II) cross-module reject fixture.
//
// The aggregate-field-bound const-array holes closed by FX11, swept across the
// same materialisation sites as FX6 plus the address / element siblings:
//   * local decls: field `[0..]` -> `[]i32`/`[*]i32`, `&field` ->
//     `*[3]i32`/`[]i32`/`[*]i32`, direct field -> `*i32`;
//   * module vars: field `[0..]` -> mutable slice / many-pointer;
//   * assignments: mutable slice / many / element pointer from the field;
//   * returns: field `[0..]` / field / `&field` through mutable returns;
//   * field init: `H{ .m = gs.a[0..] }`;
//   * call args (in-module and cross-module): mutable slice / many / elem
//     pointer from `gs.a[0..]`, `&gs.a` and `gs.a`;
//   * a `*const S` field (`cp.a`): `[0..]` -> mutable slice, `&cp.a` ->
//     `*[3]i32`;
//   * array-literal element sites: `[1][]i32{ gs.a }` and
//     `[1][]i32{ gs.a[0..] }`.
//
// EXPECTED: dump rc 2, 0 `.c`, exactly 29 level-0
//   `error[3000]: cannot implicitly discard 'const' qualifier`, 0 x
// `warning[3000]`, 0 other codes. Every row is a clear const discard that
// Zig 0.15.2 rejects; the legal const-ADDING directions live in
// `stdlib_const_field_decay_ok_xmod`.
const std = @import("std");
const helper = @import("helper.zig");

const S = struct { a: [3]i32 };
const garr = [3]i32{ 1, 2, 3 };
const gs: S = .{ .a = garr };
const cp: *const S = &gs;

const H = struct { m: []i32 };

var msink: []i32 = gs.a[0..];
var mmink: [*]i32 = gs.a[0..];

fn leakSlice() []i32 {
    return gs.a[0..];
}

fn leakMany() [*]i32 {
    return gs.a[0..];
}

fn leakElemPtr() *i32 {
    return gs.a;
}

fn leakArrPtr() *[3]i32 {
    return &gs.a;
}

fn leakXSlice() []i32 {
    return helper.gs.a[0..];
}

pub fn main() void {
    var s: []i32 = gs.a[0..];
    var m: [*]i32 = gs.a[0..];
    var p: *[3]i32 = &gs.a;
    var sa: []i32 = &gs.a;
    var ma: [*]i32 = &gs.a;
    var q: *i32 = gs.a;
    var xs: []i32 = helper.gs.a[0..];
    var xp: *[3]i32 = &helper.gs.a;

    s = gs.a[0..];
    m = &gs.a;
    q = cp.a;

    var ps: []i32 = cp.a[0..];
    var pa: *[3]i32 = &cp.a;

    const hh: H = .{ .m = gs.a[0..] };

    helper.takeSlice(gs.a[0..]);
    helper.takeMany(&gs.a);
    helper.takeElemPtr(gs.a);
    helper.takeSlice(helper.gs.a[0..]);
    helper.takeMany(helper.gs.a[0..]);
    helper.takeElemPtr(helper.gs.a);

    const e1 = [1][]i32{ gs.a };
    const e2 = [1][]i32{ gs.a[0..] };

    _ = leakSlice;
    _ = leakMany;
    _ = leakElemPtr;
    _ = leakArrPtr;
    _ = leakXSlice;
    _ = e1;
    _ = e2;
    _ = hh;
    _ = s;
    _ = m;
    _ = p;
    _ = sa;
    _ = ma;
    _ = q;
    _ = xs;
    _ = xp;
    _ = ps;
    _ = pa;
    _ = msink;
    _ = mmink;
    std.io.print("unreached\n", .{});
}
