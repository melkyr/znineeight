// stdlib_print_fmt_valid_xmod — Task 3 (z98-print-formatting) positive runtime
// control: the new print-format validator must KEEP accepting every
// (type x specifier) pair whose route is final after Task 2, and the program
// must still build, link, run and match official Zig 0.15.2 byte-for-byte.
//
// Covers the frozen-table FIX rows task-0-report.md A1-A17, B2/B3, C1, D1, D3:
// integer-like widths/signedness with `{}`/`{d}`/`{x}` (i32/i64/usize/u40/i40,
// u16 `{x}`, i8 `{x}` incl. a negative, u8 `{}`/`{d}`/`{x}`/`{c}`), `c_char`
// `{}`/`{x}`, integer literal `{}`/`{x}`, `bool {}`, `[]const u8 {s}`, integral
// f32/f64 `{}`/`{d}` and enum `{d}`/`{x}`. Rows owned by later tasks
// (aggregate `{}`, enum `{}`, pointer/fn-pointer `{}`, float `{x}`) are
// deliberately NOT pinned here.
//
// Golden contract (27 lines, rc 0, 3x byte-exact, Zig-0.15.2-twin-matched):
//   i32d=42 i32x=2a i64d=-5000000000 i64x=-12a05f200 uszd=3000000000
//   uszx=b2d05e00 u40d=1099511627775 u40x=ffffffffff i40d=-549755813888
//   i40x=-8000000000 u16x=ea60 i8x=64 i8mx=-5 u8d=65 u8x=41 u8c=A
//   cchard=-5 ccharx=-5 litd=42 litx=2a boold=true strs=hi f64d=7 f64h=100
//   f32d=7 enumd=1 enumx=1
const std = @import("std");
const C = enum { red, green };

pub fn main() void {
    var i32v: i32 = 42;
    var i64v: i64 = @intCast(i64, 0 - 5000000000);
    var uszv: usize = @intCast(usize, 3000000000);
    var u40v: u40 = @intCast(u40, 1099511627775);
    var i40v: i40 = @intCast(i40, 0 - 549755813888);
    var u16v: u16 = 60000;
    var i8v: i8 = 100;
    var i8m: i8 = @intCast(i8, 0 - 5);
    var u8v: u8 = 65;
    var ccv: c_char = @intCast(c_char, 0 - 5);
    var bv = true;
    var sv: []const u8 = "hi";
    var f64v: f64 = 7.0;
    var f64h: f64 = 100.0;
    var f32v: f32 = 7.0;
    var cv: C = .green;
    if (i32v != 42) { @panic("i32"); }
    if (i64v != @intCast(i64, 0 - 5000000000)) { @panic("i64"); }
    if (uszv != @intCast(usize, 3000000000)) { @panic("usize"); }
    if (u40v != @intCast(u40, 1099511627775)) { @panic("u40"); }
    if (i40v != @intCast(i40, 0 - 549755813888)) { @panic("i40"); }
    if (bv != true) { @panic("bool"); }
    if (f64v != 7.0) { @panic("f64"); }
    std.io.print("i32d={}\n", .{i32v});
    std.io.print("i32x={x}\n", .{i32v});
    std.io.print("i64d={d}\n", .{i64v});
    std.io.print("i64x={x}\n", .{i64v});
    std.io.print("uszd={}\n", .{uszv});
    std.io.print("uszx={x}\n", .{uszv});
    std.io.print("u40d={}\n", .{u40v});
    std.io.print("u40x={x}\n", .{u40v});
    std.io.print("i40d={}\n", .{i40v});
    std.io.print("i40x={x}\n", .{i40v});
    std.io.print("u16x={x}\n", .{u16v});
    std.io.print("i8x={x}\n", .{i8v});
    std.io.print("i8mx={x}\n", .{i8m});
    std.io.print("u8d={}\n", .{u8v});
    std.io.print("u8x={x}\n", .{u8v});
    std.io.print("u8c={c}\n", .{u8v});
    std.io.print("cchard={}\n", .{ccv});
    std.io.print("ccharx={x}\n", .{ccv});
    std.io.print("litd={}\n", .{42});
    std.io.print("litx={x}\n", .{42});
    std.io.print("boold={}\n", .{bv});
    std.io.print("strs={s}\n", .{sv});
    std.io.print("f64d={d}\n", .{f64v});
    std.io.print("f64h={}\n", .{f64h});
    std.io.print("f32d={}\n", .{f32v});
    std.io.print("enumd={d}\n", .{cv});
    std.io.print("enumx={x}\n", .{cv});
}
