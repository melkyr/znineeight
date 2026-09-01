const std = @import("std");

pub fn main() void {
    var c = @intCast(i32, 'c');
    std.io.printInt(c);
}
