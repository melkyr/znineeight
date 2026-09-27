// D10 in-module reject census (FH conversion, 2026-09-27): a single-item
// pointer to a non-array pointee may not be indexed, and the only legal `*T`
// slices are the three comptime Zig forms. The former acceptance (seed v88
// printed `p[0]=42`) is now `error[3066]`/`error[3067]` (rc 2 / 0 `.c`); the
// census is pinned in `expected_error.txt` and the exact per-site wording in
// /tmp/vol2_defects_out/D10_single_ptr_index/compile.log. Sibling files:
// `reject_slice_02/10/open.zig` (3067), `reject_star_paren.zig` (3066 type
// base), `control_slice_legal.zig` (accepted, new `*[N]T` result types),
// `control_deref.zig` (unchanged) and the cross-module `xmod_main.zig`.
const std = @import("std");

const Point = struct { x: i32, y: i32 };

pub fn main() void {
    var n: i32 = 42;
    const p: *i32 = &n;
    var i: usize = 1;

    // 3066: all single-item-pointer index forms.
    const a = p[0];
    const b = p[1];
    const c = p[i];
    p[0] = 7;
    var pt = Point{ .x = 5, .y = 6 };
    const ps: *Point = &pt;
    const d = ps[0].x;
    // 3066: a `type` base (the wrong-code `(*p)[i]` shape).
    const e = (*p)[i];

    // 3067: every non-legal slice form (the open form used to ICE 3043).
    const s1 = p[0..2];
    const s2 = p[1..0];
    const s3 = p[-1..1];
    var m: usize = 1;
    const s4 = p[0..m];
    const s5 = p[0..];

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
}
