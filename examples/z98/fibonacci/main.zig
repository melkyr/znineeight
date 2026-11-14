const std = @import("std");

fn fib(n: u32) u32 {
    if (n <= 1) { return n; }
    return fib(n - 1) + fib(n - 2);
}

pub fn main() void {
    const result = fib(10);
    std.io.printInt(@intCast(i32, result));
}
