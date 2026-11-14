// S1 shape (silent wrong code): two non-tuple variable print calls compile
// and run, but both placeholders print the FIRST variable's value
// (`one=1 two=1` instead of `one=1 two=2`).
const std = @import("std");

pub fn main() void {
    var a: i32 = 1;
    var b: i32 = 2;
    std.io.print("one={}\n", a);
    std.io.print("two={}\n", b);
}
