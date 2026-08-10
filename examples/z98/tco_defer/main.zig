const std = @import("std.zig");

@cInclude("zig_runtime.h");

fn countDown(n: u32) u32 {
    defer {
        std.io.print("D\n");
    }
    if (n == 0) return 0;
    return countDown(n - 1);
}

pub fn main() !void {
    const r = countDown(10);
    std.debug.print("countDown(10) = ", .{});
    std.debug.printInt(@intCast(i32, r));
    std.io.print("\n");

    const d = countDown(100000);
    std.debug.print("countDown(100000) = ", .{});
    std.debug.printInt(@intCast(i32, d));
    std.io.print("\n");

    std.debug.print("deep ok\n", .{});
}
