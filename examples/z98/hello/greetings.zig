const std = @import("std");
pub fn sayHello() void {
    std.io.print("Hello, world!\n", .{});
}
