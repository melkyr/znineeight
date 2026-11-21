// stdlib_comptime_compare_xmod — Task 3 (signedness-free comparisons + logical
// folds) positive runtime fixture.
//
// Pins the retired Task 9D bounded divergence (`repro/mi_matrix/
// comptime_compare_diverge_reject_xmod`): comparisons now use the exact
// magnitude+sign of the arbitrary-precision `ComptimeInt`, so arithmetic-derived
// conditions fold exactly like Zig's `comptime_int`, and the condition of every
// capture-free no-`else` value `if` is stored (Task 1 §7) so lowering's `ie_fold`
// path elides the untaken branch — including module-scope operands (step-0
// S3/S5/E12, fixed here) whose emitted runtime branch was previously wrong.
//
// Covered:
//   * function-local consts (the fold runs through the sema local-const scope;
//     the runtime branch stays): `(umax - 1) > 0`, `0 < (umax - 1)`,
//     `(umax - 1) > zero`, `umax > (0 + 0)`, `(a + 1) == 2`, and the unreduced
//     i64 extremes `(imin + 1) < 0`, `(imax - 1) > 0` (E10/E11);
//   * module-scope consts (the phase pass folds + stores the condition, so the
//     branch elides): the same D1-D5 shapes, the declared-unsigned/untyped-
//     negative shapes `UU > -1`, `-1 < UU`, `UU > (0 - 1)` (step-0 S3/S4/S5),
//     the i64-min literal `-9223372036854775808 < 0` (E12), and module-scope
//     i64 extremes;
//   * logical short-circuit over arbitrary magnitudes: `and`/`or`/`!` with
//     2^100 operands;
//   * fix round 2: `(~u) != 0` with a typed u32 operand (module + local), the
//     valid Zig-equal class that a bit_not peer fit broke (Oracle: accepts,
//     prints `400 401`; Zig computes the wrapped complement 4294967295).
//
// Every value is `@panic`-guarded. Oracle: official Zig 0.15.2 twin
// (`/tmp/task3/oracle_accept.zig`; the fix-round-2 `~` shapes re-checked with
// `/tmp/fix3/bnot_oracle.zig`), which accepts every shape and prints these
// exact values.
//
// Contract: stdout below, rc 0, byte-exact 3x.
//
//   101 102 103 104 105 110 111 201 202 203 204
//   205 206 207 208 209 210 211 301 302 303 304
//   400 401
//   compare ok
const std = @import("std");

const UU: u8 = 200;
const MUMAX: u64 = 18446744073709551615;
const MZERO: u64 = 0;
const MA: i32 = 1;
const MICRO: i64 = -9223372036854775808;
const MIMAX: i64 = 9223372036854775807;
const UZERO: u32 = 0;

pub fn main() void {
    const umax: u64 = 18446744073709551615;
    const zero: u64 = 0;
    const a: i32 = 1;
    // NOTE: the local i64-min const is spelled through `@as` because the bare
    // `const imin: i64 = -9223372036854775808` spelling hits a PRE-EXISTING
    // (>32-bit local negate-const) HIT-materialisation defect unrelated to
    // comparisons (`print(imin)` prints 0 at HEAD too); Task 4/5 own that
    // lowering path. The comparison under test is unchanged.
    const imin: i64 = @as(i64, -9223372036854775808);
    const imax: i64 = 9223372036854775807;

    var l1: i32 = if ((umax - 1) > 0) 101;
    var l2: i32 = if (0 < (umax - 1)) 102;
    var l3: i32 = if ((umax - 1) > zero) 103;
    var l4: i32 = if (umax > (0 + 0)) 104;
    var l5: i32 = if ((a + 1) == 2) 105;
    var l6: i32 = if ((imin + 1) < 0) 110;
    var l7: i32 = if ((imax - 1) > 0) 111;

    var m1: i32 = if ((MUMAX - 1) > 0) 201;
    var m2: i32 = if (0 < (MUMAX - 1)) 202;
    var m3: i32 = if ((MUMAX - 1) > MZERO) 203;
    var m4: i32 = if (MUMAX > (0 + 0)) 204;
    var m5: i32 = if ((MA + 1) == 2) 205;
    var m6: i32 = if (UU > -1) 206;
    var m7: i32 = if (-1 < UU) 207;
    var m8: i32 = if (UU > (0 - 1)) 208;
    var m9: i32 = if (-9223372036854775808 < 0) 209;
    var m10: i32 = if ((MICRO + 1) < 0) 210;
    var m11: i32 = if ((MIMAX - 1) > 0) 211;

    var g1: i32 = if ((1 << 100) > 0 and true) 301;
    var g2: i32 = if (false or ((0 - (1 << 100)) < 0)) 302;
    var g3: i32 = if (!((1 << 100) < 0)) 303;
    var g4: i32 = if ((0 - (1 << 100)) < 0 and (1 << 100) > 0) 304;

    // Task 3 fix round 2: `~` must NOT apply the peer fit (only `negate` does).
    // Sema types `~x` as x's type and the runtime complement wraps, while Z98's
    // fold is the exact `-x - 1` (Task 1 §4); a fit check would reject EVERY
    // typed-unsigned `~u` shape, including these valid, Zig-equal ones. Module
    // operand (condition stored + elided) and local operand (runtime branch).
    // Declared divergence: a shape that depends on the WRAPPED value (e.g.
    // `(~uz) == 4294967295`) can still false-reject; see doc 04 Known Issues.
    var b1: i32 = if ((~UZERO) != 0) 400;
    const uz: u32 = 0;
    var b2: i32 = if ((~uz) != 0) 401;

    if (l1 != 101 or l2 != 102 or l3 != 103 or l4 != 104 or l5 != 105 or l6 != 110 or l7 != 111) {
        @panic("comptime_compare local guard failed");
    }
    if (m1 != 201 or m2 != 202 or m3 != 203 or m4 != 204 or m5 != 205 or m6 != 206) {
        @panic("comptime_compare module guard A failed");
    }
    if (m7 != 207 or m8 != 208 or m9 != 209 or m10 != 210 or m11 != 211) {
        @panic("comptime_compare module guard B failed");
    }
    if (g1 != 301 or g2 != 302 or g3 != 303 or g4 != 304) {
        @panic("comptime_compare logical guard failed");
    }
    if (b1 != 400 or b2 != 401) {
        @panic("comptime_compare bitnot guard failed");
    }
    std.io.print("{} {} {} {} {} {} {} {} {} {} {}\n", .{ l1, l2, l3, l4, l5, l6, l7, m1, m2, m3, m4 });
    std.io.print("{} {} {} {} {} {} {} {} {} {} {}\n", .{ m5, m6, m7, m8, m9, m10, m11, g1, g2, g3, g4 });
    std.io.print("{} {}\n", .{ b1, b2 });
    std.io.print("compare ok\n", .{});
}
