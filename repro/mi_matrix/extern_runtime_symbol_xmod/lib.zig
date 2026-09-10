const std = @import("std_arena");

var g_buf: [16]u8 = undefined;
var g_arena = std.init(g_buf[0..]);

pub fn alloc(n: u32) [*]u8 {
    return (std.alloc(&g_arena, @intCast(usize, n)) orelse @ptrCast([*]u8, @intCast(usize, 0)));
}
