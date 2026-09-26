// D4 sibling shape: parse error on a tuple return type.
const std = @import("std");

fn divmod(a: i32, b: i32) struct { i32, i32 } {
    return .{ a / b, a % b };
}

pub fn main() void {
    const d = divmod(17, 5);
    std.io.print("d={}\n", .{d});
}
