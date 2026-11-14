// D1 cross-module helper (split control): a bare `defer`.
const std = @import("std");

pub fn plain() void {
    defer std.io.print("helper-plain-defer\n", .{});
    std.io.print("helper-plain-body\n", .{});
}
