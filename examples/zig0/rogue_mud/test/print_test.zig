// examples/rogue_mud/test/print_test.zig
const std = @import("../../mud_server/std.zig");

pub fn main() void {
    const x: i32 = 42;
    std.debug.print("Hello: {}\n", .{x});
}
