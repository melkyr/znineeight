const std = @import("std.zig");

pub fn print(fmt: *const c_char, args: anytype) void {
    std.io.print(fmt);
}
