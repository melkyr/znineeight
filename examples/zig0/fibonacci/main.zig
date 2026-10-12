const std = @import("std.zig");

fn fib(n: u32) u32 {
    if (n <= 1) { return n; }
    return fib(n - 1) + fib(n - 2);
}

pub fn main() void {
    const result = fib(10);
    std.debug.printInt(@intCast(i32, result));
}
