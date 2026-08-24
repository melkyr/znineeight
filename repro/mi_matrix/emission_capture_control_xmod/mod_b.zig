const mod_a = @import("mod_a.zig");

pub fn capture() void {
    var arr: [3]u32 = .{ 1, 2, 3 };
    for (arr) |s| {
        var s: []const u8 = "x";
        mod_a.writeStr(s);
    }
}
