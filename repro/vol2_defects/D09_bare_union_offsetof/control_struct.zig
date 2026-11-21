// D9 control: `@offsetOf` on a struct works.
const std = @import("std");

const S = struct { a: i32, b: u32 };

pub fn main() void {
    std.io.print("off_a={} off_b={}\n", .{ @offsetOf(S, "a"), @offsetOf(S, "b") });
}
