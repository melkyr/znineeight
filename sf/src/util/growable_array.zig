const Sand = @import("../allocator.zig").Sand;
const sandAlloc = @import("../allocator.zig").sandAlloc;

pub const U32ArrayList = struct {
    items: [*]u32,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn u32ArrayListInit(allocator: *Sand) U32ArrayList {
    return U32ArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn u32ArrayListEnsureCapacity(self: *U32ArrayList, new_capacity: usize) !void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < 8) new_cap = 8;
    var raw = try sandAlloc(self.allocator, @intCast(usize, 4) * new_cap, @intCast(usize, 4));
    var new_items = @ptrCast([*]u32, raw);
    var i: usize = 0;
    while (i < self.len) {
        new_items[i] = self.items[i];
        i += 1;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn u32ArrayListAppend(self: *U32ArrayList, value: u32) !void {
    try u32ArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn u32ArrayListPopOrNull(self: *U32ArrayList) ?u32 {
    if (self.len == 0) return null;
    self.len -= 1;
    return self.items[self.len];
}

pub fn u32ArrayListGetSlice(self: *U32ArrayList) []u32 {
    return self.items[0..self.len];
}
