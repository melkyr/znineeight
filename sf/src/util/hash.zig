const alloc_mod = @import("../allocator.zig");
const Sand = alloc_mod.Sand;

pub fn fnv1a(data: []const u8) u32 {
    var hash: u32 = 2166136261;
    for (data) |byte| {
        hash ^= @intCast(u32, byte);
        hash = hash *% 16777619;
    }
    return hash;
}

pub const U32ToU32Map = struct {
    keys: [*]u32,
    values: [*]u32,
    occupied: [*]u8,
    capacity: usize,
    count: usize,
    alloc: *Sand,
};

pub fn u32ToU32MapInit(alloc: *Sand) U32ToU32Map {
    return U32ToU32Map{
        .keys = undefined, .values = undefined, .occupied = undefined,
        .capacity = @intCast(usize, 0), .count = @intCast(usize, 0), .alloc = alloc,
    };
}

pub fn u32ToU32MapGet(self: *U32ToU32Map, key: u32) ?u32 {
    if (self.capacity == @intCast(usize, 0)) return null;
    var mask = self.capacity - @intCast(usize, 1);
    var i = @intCast(usize, key) & mask;
    while (self.occupied[i] != @intCast(u8, 0)) {
        if (self.keys[i] == key) return self.values[i];
        i = (i + @intCast(usize, 1)) & mask;
    }
    return null;
}

fn u32ToU32MapGrow(self: *U32ToU32Map) void {
    var old_cap = self.capacity;
    var old_keys = self.keys;
    var old_values = self.values;
    var old_occupied = self.occupied;
    var new_cap = if (old_cap < @intCast(usize, 8)) @intCast(usize, 8) else old_cap * @intCast(usize, 2);
    var raw_keys = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_vals = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_occ = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 1) * new_cap, @intCast(usize, 4)) catch unreachable;
    self.keys = @ptrCast([*]u32, raw_keys);
    self.values = @ptrCast([*]u32, raw_vals);
    self.occupied = @ptrCast([*]u8, raw_occ);
    self.capacity = new_cap;
    self.count = @intCast(usize, 0);
    var zi: usize = 0;
    while (zi < new_cap) { self.occupied[zi] = @intCast(u8, 0); zi += 1; }
    var ri: usize = 0;
    while (ri < old_cap) {
        if (old_occupied[ri] != @intCast(u8, 0)) {
            var k = old_keys[ri];
            var v = old_values[ri];
            var mask2 = new_cap - @intCast(usize, 1);
            var idx = @intCast(usize, k) & mask2;
            while (self.occupied[idx] != @intCast(u8, 0)) { idx = (idx + @intCast(usize, 1)) & mask2; }
            self.keys[idx] = k;
            self.values[idx] = v;
            self.occupied[idx] = @intCast(u8, 1);
            self.count += 1;
        }
        ri += 1;
    }
}

pub fn u32ToU32MapPut(self: *U32ToU32Map, key: u32, value: u32) void {
    if (self.count * @intCast(usize, 4) >= self.capacity * @intCast(usize, 3)) { u32ToU32MapGrow(self); }
    if (self.capacity == @intCast(usize, 0)) { u32ToU32MapGrow(self); }
    var mask = self.capacity - @intCast(usize, 1);
    var i = @intCast(usize, key) & mask;
    while (self.occupied[i] != @intCast(u8, 0)) {
        if (self.keys[i] == key) { self.values[i] = value; return; }
        i = (i + @intCast(usize, 1)) & mask;
    }
    self.keys[i] = key;
    self.values[i] = value;
    self.occupied[i] = @intCast(u8, 1);
    self.count += 1;
}

pub const U64ToU32Map = struct {
    keys: [*]u64,
    values: [*]u32,
    occupied: [*]u8,
    capacity: usize,
    count: usize,
    alloc: *Sand,
};

pub fn u64ToU32MapInit(alloc: *Sand) U64ToU32Map {
    return U64ToU32Map{
        .keys = undefined, .values = undefined, .occupied = undefined,
        .capacity = @intCast(usize, 0), .count = @intCast(usize, 0), .alloc = alloc,
    };
}

pub fn u64ToU32MapGet(self: *U64ToU32Map, key: u64) ?u32 {
    if (self.capacity == @intCast(usize, 0)) return null;
    var mask = self.capacity - @intCast(usize, 1);
    var i = @intCast(usize, @intCast(u32, key & @intCast(u64, 0xFFFFFFFF))) & mask;
    while (self.occupied[i] != @intCast(u8, 0)) {
        if (self.keys[i] == key) return self.values[i];
        i = (i + @intCast(usize, 1)) & mask;
    }
    return null;
}

fn u64ToU32MapGrow(self: *U64ToU32Map) void {
    var old_cap = self.capacity;
    var old_keys = self.keys;
    var old_values = self.values;
    var old_occupied = self.occupied;
    var new_cap = if (old_cap < @intCast(usize, 8)) @intCast(usize, 8) else old_cap * @intCast(usize, 2);
    var raw_keys = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 8) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_vals = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_occ = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 1) * new_cap, @intCast(usize, 4)) catch unreachable;
    self.keys = @ptrCast([*]u64, raw_keys);
    self.values = @ptrCast([*]u32, raw_vals);
    self.occupied = @ptrCast([*]u8, raw_occ);
    self.capacity = new_cap;
    self.count = @intCast(usize, 0);
    var zi: usize = 0;
    while (zi < new_cap) { self.occupied[zi] = @intCast(u8, 0); zi += 1; }
    var ri: usize = 0;
    while (ri < old_cap) {
        if (old_occupied[ri] != @intCast(u8, 0)) {
            var k = old_keys[ri];
            var v = old_values[ri];
            var mask2 = new_cap - @intCast(usize, 1);
            var idx = @intCast(usize, @intCast(u32, k & @intCast(u64, 0xFFFFFFFF))) & mask2;
            while (self.occupied[idx] != @intCast(u8, 0)) { idx = (idx + @intCast(usize, 1)) & mask2; }
            self.keys[idx] = k;
            self.values[idx] = v;
            self.occupied[idx] = @intCast(u8, 1);
            self.count += 1;
        }
        ri += 1;
    }
}

pub fn u64ToU32MapPut(self: *U64ToU32Map, key: u64, value: u32) void {
    if (self.count * @intCast(usize, 4) >= self.capacity * @intCast(usize, 3)) { u64ToU32MapGrow(self); }
    if (self.capacity == @intCast(usize, 0)) { u64ToU32MapGrow(self); }
    var mask = self.capacity - @intCast(usize, 1);
    var i = @intCast(usize, @intCast(u32, key & @intCast(u64, 0xFFFFFFFF))) & mask;
    while (self.occupied[i] != @intCast(u8, 0)) {
        if (self.keys[i] == key) { self.values[i] = value; return; }
        i = (i + @intCast(usize, 1)) & mask;
    }
    self.keys[i] = key;
    self.values[i] = value;
    self.occupied[i] = @intCast(u8, 1);
    self.count += 1;
}
