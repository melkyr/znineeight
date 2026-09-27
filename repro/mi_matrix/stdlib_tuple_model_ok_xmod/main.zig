// stdlib_tuple_model_ok_xmod — FB (Volume II D4) positive runtime fixture.
//
// Before FB the Language Spec section 1.3 tuple type `struct { T1, T2 }` was a
// parse error, `.0`/`._0` were `error[3060]` and `t[0]` emitted gcc-invalid C.
// This fixture pins the accepted model at runtime:
//   dotN    `.0`/`.1` read + `.0` write
//   under   `._0`/`._1` read + `._1` write
//   index   `t[0]`/`t[1]` read + `t[0]` write + a local-const index
//   addr    `&p.0` + deref write
//   coerce  tuple literal -> named tuple (var decl, return, call argument)
//   named   named tuple -> shape-identical named tuple
//   xmod    cross-module tuple type/param/return and module global (read+write)
//   nested  nested tuple element read (`t[0][1]`)
//
// Contract: stdout `tp=12/20 us0=11 e1=20 ci=20 q=11/20 sw=20/11 m=7/8
// lit=9 g=44/5 ep=12 nn=2\n`, rc 0, byte-exact 3x. The values prove the access
// lowers to the emitted positional C fields (`_0`/`_1`) on the real storage,
// not a copy. Every observation is `@panic`-guarded.
//
// Zig-0.15.2 twin (comparison only): `.0`/`._0` are operator-ruled Z98
// divergences (Zig rejects them), so the twin uses `[0]`/`[1]` for every
// access; its `std.debug.print` body prints the same values byte-for-byte.
const std = @import("std");
const helper = @import("helper.zig");

pub fn main() void {
    var p: helper.Pair = .{ 1, 2 };
    p.0 = 10;
    p._1 = 20;
    p[0] = p[0] + 1;

    const e0 = p.0;
    const e1 = p.1;
    const us0 = p._0;
    const ci_idx: usize = 1;
    const ci = p[ci_idx];
    if (e0 != 11 or e1 != 20 or us0 != 11 or ci != 20) {
        @panic("tuple element read/write mismatch");
    }

    // tuple literal -> named tuple, and named tuple -> shape-identical tuple.
    const q: helper.Pair = .{ p[0], p[1] };
    const q2: helper.Pair = q;
    if (q2[0] != 11 or q2[1] != 20) {
        @panic("tuple-to-tuple coercion mismatch");
    }

    // cross-module param + return, and a tuple literal as a cross-module arg.
    const sw = helper.swap(p);
    if (sw[0] != 20 or sw.1 != 11) {
        @panic("cross-module tuple param/return mismatch");
    }
    const m = helper.mk(7, 8);
    if (m[0] != 7 or m[1] != 8) {
        @panic("inline tuple return mismatch");
    }
    const lit = helper.first(.{ 9, 10 });
    if (lit != 9) {
        @panic("tuple literal argument mismatch");
    }

    // cross-module module-global tuple: read, write through `[0]`, read back.
    const g0 = helper.g[0];
    const g1 = helper.g._1;
    if (g0 != 4 or g1 != 5) {
        @panic("cross-module tuple global read mismatch");
    }
    helper.g[0] = 44;

    // address of an element + deref write.
    const ep: *i32 = &p.0;
    ep.* = 12;

    // nested tuple read.
    const nn = .{ .{ 1, 2 }, 3 };
    const nv = nn[0][1];
    if (nv != 2) {
        @panic("nested tuple element read mismatch");
    }

    std.io.print("tp={}/{} us0={} e1={} ci={} q={}/{} sw={}/{} m={}/{} lit={} g={}/{} ep={} nn={}\n", .{ p.0, p[1], us0, p.1, ci, q[0], q[1], sw[0], sw[1], m[0], m[1], lit, helper.g[0], helper.g[1], p[0], nv });
}
