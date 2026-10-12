const std = @import("std");

@cInclude("zig_runtime.h");

fn fact(n: i32, acc: i32) i32 {
    if (n == 0) return acc;
    return fact(n - 1, acc * n);
}

pub fn main() !void {
    std.io.print("fact(10) = {}\n", .{fact(10, 1)});
    _ = fact(100000, 1);
    std.io.print("deep ok\n", .{});
}
