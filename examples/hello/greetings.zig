const std = @import("std.zig");
pub fn sayHello() void {
    std.debug.print("Hello, world!\n", .{});
}
