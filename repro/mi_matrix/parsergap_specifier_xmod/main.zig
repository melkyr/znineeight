const std = @import("std");
pub fn main() void {
    var v: u8 = 65;
    std.io.print("{x}\n", .{v});
}
