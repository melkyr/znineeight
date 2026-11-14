// D9 control: introspection on a packed struct works (@offsetOf and
// @bitOffsetOf).
const std = @import("std");

const P = packed struct { a: u4, b: u4 };

pub fn main() void {
    std.io.print("off_a={} bitoff_b={}\n", .{ @offsetOf(P, "a"), @bitOffsetOf(P, "b") });
}
