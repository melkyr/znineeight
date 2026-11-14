const std = @import("std");
const mod_a = @import("mod_a.zig");

pub fn run() u32 {
    var r = mod_a.maybe() catch |e| {
        var e: []const u8 = "err";
        std.io.write(e);
        0;
    };
    return r;
}
