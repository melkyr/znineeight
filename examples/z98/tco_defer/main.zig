const std = @import("std.zig");

@cInclude("zig_runtime.h");

extern fn __bootstrap_print(s: *const c_char) void;

fn countDown(n: u32) u32 {
    defer {
        __bootstrap_print("D\n");
    }
    if (n == 0) return 0;
    return countDown(n - 1);
}

pub fn main() !void {
    const r = countDown(10);
    std.debug.print("countDown(10) = ", .{});
    std.debug.printInt(@intCast(i32, r));
    __bootstrap_print("\n");

    const d = countDown(100000);
    std.debug.print("countDown(100000) = ", .{});
    std.debug.printInt(@intCast(i32, d));
    __bootstrap_print("\n");

    std.debug.print("deep ok\n", .{});
}
