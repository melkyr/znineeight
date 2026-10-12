// src/dungeon/room.zig
const sand_mod = @import("sand.zig");

pub const Room_t = struct {
    x: u8,
    y: u8,
    w: u8,
    h: u8,
};

pub fn Room_centerX(self: Room_t) u8 {
    return self.x + @intCast(u8, self.w / 2);
}

pub fn Room_centerY(self: Room_t) u8 {
    return self.y + @intCast(u8, self.h / 2);
}

// --- ArrayListRoom ---
pub const ArrayListRoom = struct {
    items: [*]Room_t,
    len: usize,
    capacity: usize,
    arena: *sand_mod.Sand,
};

pub fn ArrayListRoom_init(arena: *sand_mod.Sand, initial_capacity: usize) !ArrayListRoom {
    const mem = try sand_mod.sand_alloc(arena,
        initial_capacity * @sizeOf(Room_t),
        @alignOf(Room_t));
    return ArrayListRoom{
        .items = @ptrCast([*]Room_t, mem),
        .len = @intCast(usize, 0),
        .capacity = initial_capacity,
        .arena = arena,
    };
}

pub fn ArrayListRoom_append(self: *ArrayListRoom, item: Room_t) !void {
    if (self.len >= self.capacity) {
        const new_cap = self.capacity * 2;
        const new_mem = try sand_mod.sand_alloc(self.arena,
            new_cap * @sizeOf(Room_t),
            @alignOf(Room_t));
        const new_items = @ptrCast([*]Room_t, new_mem);

        var i: usize = 0;
        while (i < self.len) : (i += 1) {
            new_items[i] = self.items[i];
        }
        self.items = new_items;
        self.capacity = new_cap;
    }
    self.items[self.len] = item;
    self.len += 1;
}

pub fn ArrayListRoom_toSlice(self: *ArrayListRoom, out: *[]Room_t) void {
    if (out != null) {
        out.* = self.items[0..self.len];
    }
}
