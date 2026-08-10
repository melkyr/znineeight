const std = @import("std_arena.zig");

var g_arena = std.create(16);

pub fn alloc(n: u32) [*]u8 {
    return (std.alloc(&g_arena, @intCast(usize, n)) orelse @ptrCast([*]u8, @intCast(usize, 0)));
}
