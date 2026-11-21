const std = @import("std");

pub var x: i32 = 42;

pub fn main() void {
    x = x + 1;
    std.io.printInt(x);
}
