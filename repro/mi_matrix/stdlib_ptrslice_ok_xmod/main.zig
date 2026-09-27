// stdlib_ptrslice_ok_xmod — FH (Volume II D10) positive runtime fixture.
//
// Before FH a `*T` slice yielded `[]T`, the illegal slices were accepted
// unchecked (the open form ICEd at lowering), and a single-item-pointer index
// silently emitted `base[idx]` C with no bounds information. This fixture pins
// the FH behavior:
//   s00/s01/s11  `p[0..0]`/`p[0..1]`/`p[1..1]` yield `*[0]T`/`*[1]T`
//   const/vol    `*const T` / `*volatile T` bases carry their qualifiers
//   read         `*[1]T` indexing (`t01[0]`) and the `[]T` coercion
//   pa           `*[N]T` auto-deref indexing + the unchanged `*[N]T` slice path
//   deref/many   `p.*` and `[*]T` indexing controls stay accepted
//
// Contract: stdout `lens=0 1 0 v=42 sl0=42 c=42 vv=7 pa1=20 pas1=20 dv=42
// mp=20\n`, rc 0, byte-exact 3x and byte-identical to the Zig-0.15.2 twin
// (comparison only). Every observation is `@panic`-guarded.
const std = @import("std");

pub fn main() void {
    var x: i32 = 42;
    const p: *i32 = &x;
    const s00 = p[0..0];
    const t00: *[0]i32 = s00;
    const s01 = p[0..1];
    const t01: *[1]i32 = s01;
    const s11 = p[1..1];
    const t11: *[0]i32 = s11;
    const v = t01[0];
    const sl: []i32 = t01;
    if (t00.len != 0 or t01.len != 1 or t11.len != 0) {
        @panic("single-item-pointer slice length mismatch");
    }
    if (v != 42 or sl[0] != 42) {
        @panic("single-item-pointer slice read mismatch");
    }

    // const and volatile qualifiers survive the three legal slices.
    const cp: *const i32 = &x;
    const c01 = cp[0..1];
    const ct01: *const [1]i32 = c01;
    if (ct01[0] != 42) {
        @panic("const-qualified slice read mismatch");
    }
    var xv: i32 = 7;
    const vp: *volatile i32 = &xv;
    const v01 = vp[0..1];
    const vt: *volatile [1]i32 = v01;
    const vv = vt[0];
    if (vv != 7) {
        @panic("volatile-qualified slice read mismatch");
    }

    // `*[N]T` auto-deref indexing and slicing keep their existing behavior.
    var arr = [3]i32{ 10, 20, 30 };
    const pa: *[3]i32 = &arr;
    const pa1 = pa[1];
    const pas = pa[0..2];
    const psl: []i32 = pas;
    if (pa1 != 20 or psl.len != 2 or psl[1] != 20) {
        @panic("pointer-to-array path mismatch");
    }

    // Deref and many-pointer indexing controls.
    const dv = p.*;
    var marr = [3]i32{ 10, 20, 30 };
    const mp: [*]i32 = marr;
    const mpv = mp[1];
    if (dv != 42 or mpv != 20) {
        @panic("deref/many-pointer control mismatch");
    }

    std.io.print("lens={} {} {} v={} sl0={} c={} vv={} pa1={} pas1={} dv={} mp={}\n", .{ t00.len, t01.len, t11.len, v, sl[0], ct01[0], vv, pa1, psl[1], dv, mpv });
}
