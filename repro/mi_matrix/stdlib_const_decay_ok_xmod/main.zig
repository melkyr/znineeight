// stdlib_const_decay_ok_xmod — FX6 (Volume II) positive runtime fixture.
//
// The const-violation holes closed by FX6 (const-array decay, `"abc"` -> `[]u8`
// / `[*]u8`, array-literal element const discard) must not over-reject:
// every LEGAL const-ADDING direction and every MUTABLE-array decay stays
// accepted and runtime-correct, in-module and cross-module.
//
// Contract: stdout (one line, see expected.txt), rc 0, byte-exact 3x, every
// observation `@panic`-guarded. Shapes:
//   * mutable array -> `[]i32`/`[*]i32` (+ cross-module mutable params);
//   * `const arr` -> `[]const i32`/`[*]const i32`, `arr[0..]` -> `[]const`,
//     `&arr` -> `[]const`/`[*]const`/`*const [3]i32`;
//   * string literal -> `[]const u8`/`[*]const u8` (in-module + xmod);
//   * `[]i32` -> `[]const i32`/`[*]const i32` (decl/assign/args/fields);
//   * array-literal elements typed `[]const i32` (mutable element types with
//     const elements must stay rejected — see const_decay_reject_xmod);
//   * cross-module const-array -> const-slice return and const slice -> const
//     many return.
//
// (A bare `const arr` -> `[]const i32` spelling is Z98-accepted per the FX6
// operator ruling; official Zig 0.15.2 requires `&arr` there, so the Zig twin
// uses the `&` spelling for exactly those rows.)
const std = @import("std");
const helper = @import("helper.zig");

const Holder = struct { m: []const i32 };
const ManyHolder = struct { mp: [*]const i32 };
const StrHolder = struct { s: []const u8 };

const garr = [3]i32{ 1, 2, 3 };
const gc: []const i32 = garr;
const gcm: [*]const i32 = garr;
const gstr: []const u8 = "abc";
const gstrp: [*]const u8 = "abc";
const gh: Holder = .{ .m = garr };
const gmh: ManyHolder = .{ .mp = &garr };

var gmut = [3]i32{ 7, 8, 9 };
var gms: []i32 = gmut;

pub fn main() void {
    var mut = [3]i32{ 10, 20, 30 };
    const arr = [3]i32{ 4, 5, 6 };

    // Mutable directions (must keep working).
    var ms: []i32 = mut;
    var mp: [*]i32 = mut;
    var ms2: []i32 = mut[0..];
    var mp2: [*]i32 = &mut;
    const ep: *i32 = &mut[0];
    ms[0] = 11;
    mp[1] = 21;
    ms2[2] = 31;
    mp2[0] = 12;
    ep.* = 13;
    helper.bumpMut(ms);
    helper.bumpMany(mp);
    gms[0] = 70;
    if (mut[0] != 14 or mut[1] != 23 or mut[2] != 31 or gmut[0] != 70) {
        @panic("mutable array/slice/many writes failed");
    }

    // Const-ADDING from a const array (all shapes + `&arr` spellings).
    const cs1: []const i32 = arr;
    const cs2: []const i32 = arr[0..];
    const cm1: [*]const i32 = arr;
    const cm2: [*]const i32 = arr[0..];
    const cs3: []const i32 = &arr;
    const cm3: [*]const i32 = &arr;
    const ca: *const [3]i32 = &arr;
    if (cs1[0] + cs2[1] + cm1[2] + cm2[0] + cs3[1] + cm3[2] + ca[0] != 34) {
        @panic("const-array const-adding reads failed");
    }

    // Const-ADDING from string literals.
    const st1: []const u8 = "abc";
    const st2: [*]const u8 = "abc";
    if (st1[2] != 99 or st2[1] != 98) {
        @panic("string-literal const reads failed");
    }

    // Const-ADDING from mutable slices/arrays and field initializers.
    const up: []const i32 = ms;
    const upm: [*]const i32 = ms;
    var h: Holder = .{ .m = arr };
    var mh: ManyHolder = .{ .mp = &arr };
    var sh: StrHolder = undefined;
    sh = .{ .s = "abc" };
    const pt = ms.ptr;
    if (up[1] + upm[2] + h.m[2] + mh.mp[1] + sh.s[1] + pt[0] != 23 + 31 + 6 + 5 + 98 + 14) {
        @panic("const-adding from mutable slices / fields failed");
    }

    // Cross-module const-adding arguments and returns.
    const xs = helper.sumConst(gc);
    const xm = helper.sumConstMany(garr);
    const xa = helper.sumConst(arr);
    const xam = helper.sumConstMany(&arr);
    const xs2 = helper.sumConst(ms);
    const xr = helper.retConstFromArray(&arr);
    const xrs = helper.retConstFromSlice(cs1);
    const xs8 = helper.strHead("abc");
    const xm8 = helper.strTail("abc");
    if (xs + xm + xa + xam + xs2 + xr[1] + xrs[2] + xs8 + xm8 != 6 + 6 + 15 + 15 + 68 + 5 + 6 + 97 + 99) {
        @panic("cross-module const-adding failed");
    }

    // Module const bindings and field inits.
    if (gc[0] + gcm[1] + gstr[0] + gstrp[1] + gh.m[2] + gmh.mp[0] != 1 + 2 + 97 + 98 + 3 + 1) {
        @panic("module const bindings failed");
    }

    // Array-literal elements typed `[]const` (const-adding element control).
    const okarr = [2][]const i32{ cs1, cs2 };
    if (okarr[0][0] + okarr[1][2] != 10) {
        @panic("array-literal const-element control failed");
    }

    std.io.print("cda={} {} {} {} {} {} {} {} {} {} {} {} {}\n", .{ mut[0], mut[1], mut[2], gmut[0], cs1[0], cm1[2], st1[0], up[1], xr[0], xrs[1], okarr[1][1], xs8, xm8 });
}
