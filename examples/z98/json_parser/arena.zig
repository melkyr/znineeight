const std = @import("std_arena.zig");

var g_arena = std.create(1048576);

pub fn alloc_bytes(count: usize) []u8 {
    const ptr = @ptrCast([*]u8, (std.alloc(&g_arena, count) orelse unreachable));
    return ptr[0..count];
}
