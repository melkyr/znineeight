// stdlib_print_dispatch_xmod — Task 2 (z98-print-formatting) regression fixture
// for the width/signedness dispatch and the runtime format fixes (frozen table
// task-0-report.md rows A7-A17, C1).
//
// DEFECTS pinned here (all reproduced against the Task-1 seam compiler):
//   * `getPrintFnName` had explicit arms only for u32/i32/u64/i64/f64/f32/bool/
//     u8/slice; `usize` (32-bit unsigned in Z98), arbitrary-width ints
//     (`u40`/`i40`), enums and integer literals fell through to `printI32`.
//     A wide `usize` printed `-1294967296` (Zig `3000000000`); a size-8 `u40`
//     printed `-1` (Zig `1099511627775`); an `i40` printed `0` (Zig
//     `-549755813888`).
//   * `{x}` on a negative signed int printed the two's complement
//     (`fffffffb`) instead of Zig's `-` + hex magnitude (`-5`), and `{x}` on
//     small ints (i8/u16) was ignored (decimal).
//   * `pal_f64_to_str` always appended `'.'` + a fraction, so an integral
//     float printed `7.0`/`0.0`/`100.0` (Zig `7`/`0`/`100`).
//
// FIX (Task 2): route integer-like kinds by typeRegistryIntWidthBits /
// typeRegistryIntIsSigned (<=32 bits -> I32/U32, 33..64 -> I64/U64; signed
// `{x}` -> printHexI32/I64 = sign + hex magnitude; integral floats omit the
// decimal point). Rows below are the frozen table's values; every one is
// byte-identical to the official Zig 0.15.2 twin.
//
// Contract: stdout (18 lines) below, rc 0, byte-exact 3x, Zig-0.15.2-twin-matched:
//   usize=3000000000
//   usizex=b2d05e00
//   u40=1099511627775
//   u40x=ffffffffff
//   i40=-549755813888
//   i40x=-8000000000
//   u16x=ea60
//   i8x=-5
//   i8px=64
//   i32x=-5
//   i32minx=-80000000
//   i64x=-5
//   i64minx=-8000000000000000
//   f64int=7
//   f64zero=0
//   f64hundred=100
//   f32int=7
//   ccharx=-5
const std = @import("std");

pub fn main() void {
    var a: usize = @intCast(usize, 3000000000);
    if (a != @intCast(usize, 3000000000)) { @panic("usize"); }
    var b: u40 = @intCast(u40, 1099511627775);
    if (b != @intCast(u40, 1099511627775)) { @panic("u40"); }
    var c: i40 = @intCast(i40, 0 - 549755813888);
    if (c != @intCast(i40, 0 - 549755813888)) { @panic("i40"); }
    var d: u16 = @intCast(u16, 60000);
    if (d != @intCast(u16, 60000)) { @panic("u16"); }
    var e: i8 = @intCast(i8, 0 - 5);
    if (e != @intCast(i8, 0 - 5)) { @panic("i8"); }
    var e2: i8 = @intCast(i8, 100);
    if (e2 != @intCast(i8, 100)) { @panic("i8p"); }
    var f: i32 = @intCast(i32, 0 - 5);
    if (f != @intCast(i32, 0 - 5)) { @panic("i32"); }
    var f2: i32 = @intCast(i32, 0 - 2147483647 - 1);
    var g: i64 = @intCast(i64, 0 - 5);
    if (g != @intCast(i64, 0 - 5)) { @panic("i64"); }
    var g2: i64 = @intCast(i64, 0 - 9223372036854775807 - 1);
    var h: f64 = 7.0;
    if (h != 7.0) { @panic("f64int"); }
    var i: f64 = 0.0;
    if (i != 0.0) { @panic("f64zero"); }
    var j: f64 = 100.0;
    if (j != 100.0) { @panic("f64hundred"); }
    var k: f32 = @intToFloat(f32, 7);
    if (k != @intToFloat(f32, 7)) { @panic("f32int"); }
    var n: c_char = @intCast(c_char, 0 - 5);
    if (n != @intCast(c_char, 0 - 5)) { @panic("cchar"); }
    std.io.print("usize={}\n", .{a});
    std.io.print("usizex={x}\n", .{a});
    std.io.print("u40={}\n", .{b});
    std.io.print("u40x={x}\n", .{b});
    std.io.print("i40={}\n", .{c});
    std.io.print("i40x={x}\n", .{c});
    std.io.print("u16x={x}\n", .{d});
    std.io.print("i8x={x}\n", .{e});
    std.io.print("i8px={x}\n", .{e2});
    std.io.print("i32x={x}\n", .{f});
    std.io.print("i32minx={x}\n", .{f2});
    std.io.print("i64x={x}\n", .{g});
    std.io.print("i64minx={x}\n", .{g2});
    std.io.print("f64int={}\n", .{h});
    std.io.print("f64zero={}\n", .{i});
    std.io.print("f64hundred={}\n", .{j});
    std.io.print("f32int={}\n", .{k});
    std.io.print("ccharx={x}\n", .{n});
}
