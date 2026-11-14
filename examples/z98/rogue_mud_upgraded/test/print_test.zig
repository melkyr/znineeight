// examples/rogue_mud/test/print_test.zig
const std = @import("std");

pub fn main() void {
    const x: i32 = 42;
    std.io.print("Hello: {}\n", .{x});
}
