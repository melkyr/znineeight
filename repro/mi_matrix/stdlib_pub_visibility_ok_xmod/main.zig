// stdlib_pub_visibility_ok_xmod — Task 15 (S3) positive runtime control.
//
// The Task 15 cross-module `pub` enforcement must leave every VALID form
// unchanged. Covers: a `pub` fn across modules (`helper.visible`); a private
// helper reached ONLY from its own module (`helper.call_own` calls
// `secret`/`hidden_const`, `helper.uses_hidden` calls `hidden_only`); a `pub`
// const read; a `pub` type alias used cross-module; the nested `pub` module
// `helper.inner` (`visible2`, `call_own2` -> private `secret2`, `shown_const2`);
// and a cross-module `pub var` store/read (`helper.shown_var`). Every
// observation is `@panic`-guarded.
//
// Contract: stdout `a=22 b=46 c=12 d=7 e=9 f=23 g=3 h=8 i=11\n`, rc 0,
// byte-exact 3x, Zig-0.15.2-twin-matched.
const std = @import("std");
const helper = @import("helper.zig");

pub fn main() void {
    var a: i32 = helper.visible(21);
    if (a != 22) {
        @panic("pub cross-module fn call failed");
    }
    var b: i32 = helper.call_own();
    if (b != 46) {
        @panic("same-module private call failed");
    }
    var c: i32 = helper.uses_hidden(6);
    if (c != 12) {
        @panic("same-module private helper call failed");
    }
    var d: i32 = helper.shown_const;
    if (d != 7) {
        @panic("pub const read failed");
    }
    var e: helper.ShownAlias = 9;
    if (e != 9) {
        @panic("pub type alias use failed");
    }
    var f: i32 = helper.inner.visible2(21);
    if (f != 23) {
        @panic("nested pub fn call failed");
    }
    var g: i32 = helper.inner.call_own2();
    if (g != 3) {
        @panic("nested same-module private call failed");
    }
    var h: i32 = helper.inner.shown_const2;
    if (h != 8) {
        @panic("nested pub const read failed");
    }
    helper.shown_var = 11;
    var iv: i32 = helper.shown_var;
    if (iv != 11) {
        @panic("cross-module pub var store failed");
    }
    // Fix round 1 controls: a `pub` const is foldable in an array-size and an
    // enum-initializer position, and a same-module private const stays foldable
    // inside its own module (all Zig-0.15.2-matched).
    var fold_arr: [helper.shown_const]u8 = undefined;
    if (fold_arr.len != 7) {
        @panic("pub const array size failed");
    }
    const EFold = enum(u8) {
        A = helper.shown_const,
        B,
    };
    var ef: EFold = EFold.B;
    if (@enumToInt(ef) != 8) {
        @panic("pub const enum init failed");
    }
    if (helper.private_buf_len() != 5) {
        @panic("same-module private array size failed");
    }
    std.io.print("a={} b={} c={} d={} e={} f={} g={} h={} i={}\n", .{ a, b, c, d, e, f, g, h, iv });
}
