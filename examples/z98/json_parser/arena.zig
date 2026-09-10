const std = @import("std");

var g_buf: [1048576]u8 = undefined;
var g_arena = std.arena.init(g_buf[0..]);

pub fn alloc_bytes(count: usize) []u8 {
    const ptr = @ptrCast([*]u8, (std.arena.alloc(&g_arena, count) orelse unreachable));
    return ptr[0..count];
}
