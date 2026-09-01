const sand_mod = @import("sand.zig");
const point_mod = @import("point.zig");

pub const PQNode = struct {
    pt: *point_mod.Point,
    priority: u16,
};

pub const PriorityQueue = struct {
    items: [*]PQNode,
    len: usize,
    capacity: usize,
    arena: *sand_mod.Sand,
};

pub fn PriorityQueue_init(arena: *sand_mod.Sand, initial_capacity: usize) !PriorityQueue {
    const mem = try sand_mod.sand_alloc(arena,
        initial_capacity * @sizeOf(PQNode),
        @alignOf(PQNode));
    return PriorityQueue{
        .items = @ptrCast([*]PQNode, mem),
        .len = @intCast(usize, 0),
        .capacity = initial_capacity,
        .arena = arena,
    };
}

pub fn PriorityQueue_push(self: *PriorityQueue, pt: *point_mod.Point, priority: u16) !void {
    if (self.len >= self.capacity) {
        const new_cap = self.capacity * 2;
        const new_mem = try sand_mod.sand_alloc(self.arena,
            new_cap * @sizeOf(PQNode),
            @alignOf(PQNode));
        const new_items = @ptrCast([*]PQNode, new_mem);

        var i: usize = 0;
        while (i < self.len) : (i += 1) {
            new_items[i] = self.items[i];
        }
        self.items = new_items;
        self.capacity = new_cap;
    }

    // Insert sorted by priority (ascending)
    var insert_idx: usize = 0;
    while (insert_idx < self.len) : (insert_idx += 1) {
        if (priority < self.items[insert_idx].priority) {
            break;
        }
    }

    // Shift items to the right
    var j: usize = self.len;
    while (j > insert_idx) : (j -= 1) {
        self.items[j] = self.items[j - 1];
    }

    self.items[insert_idx] = PQNode{ .pt = pt, .priority = priority };
    self.len += 1;
}

pub fn PriorityQueue_pop(self: *PriorityQueue) ?*point_mod.Point {
    if (self.len == 0) return null;
    const pt = self.items[0].pt;

    // Shift items to the left
    var i: usize = 0;
    while (i < self.len - 1) : (i += 1) {
        self.items[i] = self.items[i + 1];
    }
    self.len -= 1;
    return pt;
}
