// ptr_slice_reject_xmod — FH (Volume II D10) reject fixture.
//
// Census (pinned in EXPECTED_FAIL.md; `helper.zig` carries the cross-module
// site):
//   3066 indexing a single-item pointer to a non-array pointee, or a `type`
//        base: `p[0]`, `p[1]`, runtime `p[i]`, `p[0] = v`, `ps[0].x`,
//        `(*p)[i]`, `helper.atOne(p)`
//   3067 single-item-pointer slice bounds: `p[0..2]`, `p[1..0]`, `p[-1..1]`,
//        runtime `p[0..m]`, open `p[0..]` (the former error[3043] ICE)
//   3000 the unchanged controls: `p.*[0]` on `*i32` (deref -> scalar)
// Every site is rejected by official Zig 0.15.2 except `p.*[0]`, which Z98
// keeps as its documented non-array-base reject. `*[N]T` indexing/slicing and
// `p.*`/`[*]T` stay accepted (see stdlib_ptrslice_ok_xmod).
const std = @import("std");
const helper = @import("helper.zig");

const Point = struct { x: i32, y: i32 };

pub fn main() void {
    var n: i32 = 42;
    const p: *i32 = &n;
    var i: usize = 1;
    const a = p[0];
    const b = p[1];
    const c = p[i];
    p[0] = 7;
    var pt = Point{ .x = 5, .y = 6 };
    const ps: *Point = &pt;
    const d = ps[0].x;
    const e = (*p)[i];
    const s1 = p[0..2];
    const s2 = p[1..0];
    const s3 = p[-1..1];
    var m: usize = 1;
    const s4 = p[0..m];
    const s5 = p[0..];
    const z = helper.atOne(p);
    const w = p.*[0];
    _ = a;
    _ = b;
    _ = c;
    _ = d;
    _ = e;
    _ = s1;
    _ = s2;
    _ = s3;
    _ = s4;
    _ = s5;
    _ = z;
    _ = w;
}
