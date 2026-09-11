// safe_divmod_control_xmod — A16 div/mod guard CONTROL (C89-AHEAD).
//
// All of these divisions/mods are representable and MUST NOT trap under
// `-fsafe`: signed in-range `100 / -4`, `100 % -4`, the `x / -1` and `x % -1`
// shapes with a non-MIN lhs (5/-1, 5%-1), and unsigned `u32` operands (the
// `INT_MIN/-1` comparison must be omitted for unsigned). Expected under
// `-fsafe`, `-ffast`, and PRE: rc 0, `-25 0 -5 0 14 2`.
const std = @import("std");

pub fn main() void {
    var a: i32 = 100;
    var b: i32 = -4;
    var n: i32 = 5;
    var m: i32 = -1;
    var ua: u32 = 100;
    var ub: u32 = 7;
    std.io.printInt(a / b);
    std.io.writeByte(' ');
    std.io.printInt(a % b);
    std.io.writeByte(' ');
    std.io.printInt(n / m);
    std.io.writeByte(' ');
    std.io.printInt(n % m);
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, ua / ub));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, ua % ub));
    std.io.writeByte('\n');
}
