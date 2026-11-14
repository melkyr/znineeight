const std = @import("std");

pub fn writeStr(s: []const u8) void {
    std.io.write(s);
}
