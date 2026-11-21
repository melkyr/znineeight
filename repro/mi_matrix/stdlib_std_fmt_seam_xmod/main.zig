// stdlib_std_fmt_seam_xmod — Task 1 (z98-print-formatting) regression fixture
// for the `std.fmt` seam move.
//
// CONTRACT (Task 1, byte-identical formatting behavior): the print primitive
// BODIES moved out of the C runtime (`std_print_*` in zig_runtime.c /
// emit_support.zig) into the Z98 module sf/src/std_fmt.zig, re-exported as
// `std.fmt`; the compiler emits mangled cross-module `std.fmt` calls and
// auto-imports std_fmt whenever a `print` is lowered. Every route that existed
// before the move must produce exactly the same bytes.
//
// Routes pinned here (all values chosen so the Task 2-6 fixes do NOT move this
// golden — see the frozen table task-0-report.md): i32/u32/i64/u64 `{}`/`{d}`,
// non-negative `{x}` (hex), u8 `{c}`, `bool {}`, `[]const u8 {s}`, f32/f64
// non-integral `{}`, format-string literal segments, and a direct
// `std.fmt.*` call through the re-export.
//
// Expected stdout (exact) and rc 0:
//   i32=-2147483648
//   i32d=42
//   i32x=ff
//   u32=4294967295
//   u32x=beef
//   i64=-9223372036854775808
//   u64=18446744073709551615
//   f64=2.5
//   f32=1.5
//   bool=true
//   c=A
//   s=hello
//   direct=7
const std = @import("std");

fn i32Min() i32 {
    return @intCast(i32, 0 - 2147483647 - 1);
}

fn i64Min() i64 {
    return @intCast(i64, 0 - 9223372036854775807 - 1);
}

pub fn main() void {
    std.io.print("i32={}\n", .{i32Min()});
    std.io.print("i32d={d}\n", .{@as(i32, 42)});
    std.io.print("i32x={x}\n", .{@as(i32, 255)});
    std.io.print("u32={}\n", .{@as(u32, 4294967295)});
    std.io.print("u32x={x}\n", .{@as(u32, 48879)});
    std.io.print("i64={}\n", .{i64Min()});
    std.io.print("u64={}\n", .{@as(u64, 18446744073709551615)});
    var f: f64 = 2.5;
    std.io.print("f64={}\n", .{f});
    var g: f32 = @floatCast(f32, 1.5);
    std.io.print("f32={}\n", .{g});
    var b: bool = true;
    std.io.print("bool={}\n", .{b});
    var c: u8 = 65;
    std.io.print("c={c}\n", .{c});
    var s: []const u8 = "hello";
    std.io.print("s={s}\n", .{s});
    std.io.print("direct=", .{});
    std.fmt.printI32(@as(i32, 7));
    var nl: []const u8 = "\n";
    std.fmt.printStr(nl.ptr, nl.len);
}
