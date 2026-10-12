pub const Arena = struct {
    data: [*]u8,
    capacity: usize,
    used: usize,
};

var g_storage: [1048576]u8 = undefined;
var g_used: usize = 0;

pub fn create(initial_capacity: usize) Arena {
    _ = initial_capacity;
    var a = Arena{ .data = @ptrCast([*]u8, &g_storage[0]), .capacity = 1048576, .used = 0 };
    return a;
}

pub fn alloc(self: *Arena, size: usize) ?[*]u8 {
    _ = self;
    if (g_used + size > 1048576) return null;
    var result: [*]u8 = @ptrCast([*]u8, &g_storage[0]) + g_used;
    g_used += size;
    return result;
}

pub fn reset(self: *Arena) void {
    _ = self;
    g_used = 0;
}
