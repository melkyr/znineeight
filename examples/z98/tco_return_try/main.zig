const std = @import("std.zig");

@cInclude("zig_runtime.h");

fn count(n: i32, acc: i32) !i32 {
    if (n == 0) return acc;
    return try count(n - 1, acc + 1);
}

pub fn main() !void {
    const r = try count(10, 0);
    std.debug.print("count(10) = {}\n", .{r});
    const d = try count(100000, 0);
    std.debug.print("count(100000) = {}\n", .{d});
}
