pub const Arena = struct {
    data: [*]u8,
    capacity: usize,
    used: usize,
};

pub fn init(data: []u8) Arena {
    var a = Arena{ .data = data.ptr, .capacity = data.len, .used = 0 };
    return a;
}

pub fn alloc(self: *Arena, size: usize) ?[*]u8 {
    if (self.used + size > self.capacity) return null;
    var result: [*]u8 = self.data + self.used;
    self.used += size;
    return result;
}

pub fn reset(self: *Arena) void {
    self.used = 0;
}
