// int_arbitrary_width_xmod — FEATURE-GAP RED fixture (arbitrary-width ints).
// Feature: integer types uN/iN for any N in 1..65535 (u3, i7, u12, ...).
// RED today: only fixed widths register (TYPE_SYSTEM TypeKind) -> unknown type
//   `u3` -> clean FAIL. RECORD ACTUAL.
// GREEN (contract): "7 -3 3000 4\n" — u3 5+2=7; i7 -3; u12 3000; u3 7&4=4.
const std = @import("std");

pub fn main() void {
    var a: u3 = 5;
    a = a + 2;
    var b: i7 = -3;
    var c: u12 = 3000;
    var d: u3 = 0;
    d = a & 4;
    std.io.printInt(@intCast(i32, a));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, b));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, c));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, d));
    std.io.writeByte('\n');
}
