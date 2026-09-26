// S1 shape: an expression argument (`v + 1`) behaves like the literal case --
// the placeholder is dropped with no diagnostic.
const std = @import("std");

pub fn main() void {
    var v: i32 = 5;
    std.io.print("expr={}\n", v + 1);
}
