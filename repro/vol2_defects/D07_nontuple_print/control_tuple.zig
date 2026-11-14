// D7 control: the tuple-literal form prints both arguments.
const std = @import("std");

pub fn main() void {
    std.io.print("tuple={} {}\n", .{ 7, 8 });
}
