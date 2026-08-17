const std = @import("std");
const lib = @import("lib.zig");

pub fn main() void {
    var x: i32 = if (lib.get_opt()) |cap| cap else -1;
    std.io.printInt(x);
}
