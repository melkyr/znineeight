// src/dungeon/bsp.zig
const sand_mod = @import("sand.zig");
const room_mod = @import("room.zig");

pub const BspNode = struct {
    x: u8, y: u8, w: u8, h: u8,
    left: ?*BspNode,
    right: ?*BspNode,
    room: ?*room_mod.Room_t,
};

// --- ArrayListBspNodePtr ---
pub const ArrayListBspNodePtr = struct {
    items: [*]*BspNode,
    len: usize,
    capacity: usize,
    arena: *sand_mod.Sand,
};

pub fn ArrayListBspNodePtr_init(arena: *sand_mod.Sand, initial_capacity: usize) !ArrayListBspNodePtr {
    const mem = try sand_mod.sand_alloc(arena,
        initial_capacity * @sizeOf(*BspNode),
        @alignOf(*BspNode));
    return ArrayListBspNodePtr{
        .items = @ptrCast([*]*BspNode, mem),
        .len = @intCast(usize, 0),
        .capacity = initial_capacity,
        .arena = arena,
    };
}

pub fn ArrayListBspNodePtr_append(self: *ArrayListBspNodePtr, item: *BspNode) !void {
    if (self.len >= self.capacity) {
        const new_cap = self.capacity * 2;
        const new_mem = try sand_mod.sand_alloc(self.arena,
            new_cap * @sizeOf(*BspNode),
            @alignOf(*BspNode));
        const new_items = @ptrCast([*]*BspNode, new_mem);

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

pub fn ArrayListBspNodePtr_pop(self: *ArrayListBspNodePtr) ?*BspNode {
    if (self.len == 0) return null;
    self.len -= 1;
    return self.items[self.len];
}

pub fn ArrayListBspNodePtr_toSlice(self: *ArrayListBspNodePtr, out: *[]*BspNode) void {
    if (out != null) {
        out.* = self.items[0..self.len];
    }
}
