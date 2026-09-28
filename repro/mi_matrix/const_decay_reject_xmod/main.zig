// const_decay_reject_xmod — FX6 (Volume II) cross-module reject fixture.
//
// Three const-violation holes closed by FX6 (`const`-array decay,
// string-literal -> mutable slice/many, array-literal element const discard),
// exercised across a module boundary on top of the local sites:
//   * cross-module call args: module const array / local const array /
//     `&arr` / string literal into mutable `[]i32`, `[*]i32`, `[]u8` params;
//   * cross-module returns: array value returned through `[]i32` / `[*]i32`;
//   * local module var, local decl, assignment, field init and array-literal
//     element sites.
//
// EXPECTED: dump rc 2, 0 `.c`, exactly 23 level-0
//   `error[3000]: cannot implicitly discard 'const' qualifier`, 0 x
// `warning[3000]`, 0 other codes. Legal const-ADDING shapes in the same file
// add NO diagnostic (green-guard / GREEN per the corpus classifier). Census:
// 2 module vars + 7 local decls + 2 assignments + 5 xmod call args + 2
// array-literal elements pairs (4) + 1 field init + 2 helper returns = 23.
const std = @import("std");
const helper = @import("helper.zig");

const Holder = struct { m: []i32 };

const garr = [3]i32{ 1, 2, 3 };

// Module vars (array value / string literal -> mutable slice).
var gs: []i32 = garr;
var gsp: []u8 = "abc";

pub fn main() void {
    var mut = [3]i32{ 7, 8, 9 };
    var mutbuf = [3]u8{ 1, 2, 3 };
    const arr = [3]i32{ 4, 5, 6 };
    const tmp = [2]i32{ 1, 2 };
    const c: []const i32 = tmp[0..];

    // Local decls (array value / decay / string literal).
    var s: []i32 = arr;
    var p: [*]i32 = arr;
    var s2: []i32 = arr[0..];
    var s3: []i32 = &arr;
    var pp: *[3]i32 = &arr;
    var sp: []u8 = "abc";
    var spp: [*]u8 = "abc";

    // Assignment.
    var am: []i32 = mut;
    am = arr;
    var asm: []u8 = mutbuf;
    asm = "abc";

    // Cross-module call arguments.
    helper.takeSlice(garr);
    helper.takeMany(garr);
    helper.takeSlice(arr);
    helper.takeMany(&arr);
    helper.takeU8("abc");

    // Cross-module returns (the helper's own body errors; the args also
    // exercise the array-value argument path).
    const xr = helper.retSlice(arr);
    const xm = helper.retMany(arr);

    // Field init.
    var h: Holder = .{ .m = arr };

    // Array-literal element sites.
    var xs = [2][]i32{ c, c };
    var ys = [2][]u8{ "ab", "cd" };

    // Legal const-ADDING shapes: must add NO diagnostic.
    const ok1: []const i32 = arr;
    const ok2: []const i32 = arr[0..];
    const ok3: [*]const i32 = arr;
    const ok4: [*]const i32 = &arr;
    const ok5: []const u8 = "abc";
    const ok6: [*]const u8 = "abc";
    const ok7: []i32 = mut;
    var ok8: []i32 = mut[0..];
    var ok9 = [2][]const i32{ c, c };

    _ = s;
    _ = p;
    _ = s2;
    _ = s3;
    _ = pp;
    _ = sp;
    _ = spp;
    _ = am;
    _ = asm;
    _ = xr;
    _ = xm;
    _ = h;
    _ = xs;
    _ = ys;
    _ = ok1;
    _ = ok2;
    _ = ok3;
    _ = ok4;
    _ = ok5;
    _ = ok6;
    _ = ok7;
    _ = ok8;
    _ = ok9;
    std.io.print("unreachable\n", .{});
}
