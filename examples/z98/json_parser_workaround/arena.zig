const std = @import("std");

var g_arena = std.arena.create(1048576);

pub fn alloc_bytes(count: usize) []u8 {
    const ptr = @ptrCast([*]u8, (std.arena.alloc(&g_arena, count) orelse unreachable));
    return ptr[0..count];
}
