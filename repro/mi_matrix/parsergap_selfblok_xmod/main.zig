const std = @import("std");

pub fn main() void {
    var x: u32 = 10;
    var y: u32 = 3;
    var z: u32 = 0;
    if (x > y) z = 1;
    else z = 2;
    std.io.printInt(@intCast(i32, z));
}
