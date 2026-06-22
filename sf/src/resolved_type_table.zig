const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const TypeId = @import("type_registry.zig").TypeId;
const hash_mod = @import("util/hash.zig");

pub const TypeTableEntry = struct {
    node_idx: u32,
    type_id: TypeId,
};

pub const ResolvedTypeTable = struct {
    entries_items: [*]TypeTableEntry,
    entries_len: usize,
    entries_cap: usize,
    entries_alloc: *Sand,
    index: hash_mod.U32ToU32Map,
    source_index: hash_mod.U32ToU32Map,
    source_items: [*]u32,
    source_len: usize,
    source_cap: usize,
};

pub fn resolvedTypeTableInit(alloc: *Sand) ResolvedTypeTable {
    return ResolvedTypeTable{
        .entries_items = undefined,
        .entries_len = @intCast(usize, 0),
        .entries_cap = @intCast(usize, 0),
        .entries_alloc = alloc,
        .index = hash_mod.u32ToU32MapInit(alloc),
        .source_index = hash_mod.u32ToU32MapInit(alloc),
        .source_items = undefined,
        .source_len = @intCast(usize, 0),
        .source_cap = @intCast(usize, 0),
    };
}

fn resolvedTypeTableEnsureCapacity(self: *ResolvedTypeTable, new_cap: usize) void {
    if (new_cap <= self.entries_cap) return;
    var nc = new_cap;
    if (nc < self.entries_cap * 2) nc = self.entries_cap * 2;
    if (nc < @intCast(usize, 8)) nc = @intCast(usize, 8);
    var raw = alloc_mod.sandAlloc(self.entries_alloc, @intCast(usize, @sizeOf(TypeTableEntry)) * nc, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]TypeTableEntry, raw);
    for (self.entries_items[0..self.entries_len]) |item, i| {
        new_items[i] = item;
    }
    self.entries_items = new_items;
    self.entries_cap = nc;
}

pub fn resolvedTypeTableSet(self: *ResolvedTypeTable, node_idx: u32, type_id: TypeId) void {
    var existing = hash_mod.u32ToU32MapGet(&self.index, node_idx);
    if (existing) |entry_idx| {
        self.entries_items[@intCast(usize, entry_idx)].type_id = type_id;
        return;
    }
    resolvedTypeTableEnsureCapacity(self, self.entries_len + 1);
    var entry = TypeTableEntry{ .node_idx = node_idx, .type_id = type_id };
    var new_idx = @intCast(u32, self.entries_len);
    self.entries_items[self.entries_len] = entry;
    self.entries_len += 1;
    hash_mod.u32ToU32MapPut(&self.index, node_idx, new_idx);
}

pub fn resolvedTypeTableGet(self: *ResolvedTypeTable, node_idx: u32) ?TypeId {
    var existing = hash_mod.u32ToU32MapGet(&self.index, node_idx);
    if (existing) |entry_idx| {
        return self.entries_items[@intCast(usize, entry_idx)].type_id;
    }
    return null;
}

fn sourceTableEnsureCapacity(self: *ResolvedTypeTable, new_cap: usize) void {
    if (new_cap <= self.source_cap) return;
    var nc = new_cap;
    if (nc < self.source_cap * 2) nc = self.source_cap * 2;
    if (nc < @intCast(usize, 8)) nc = @intCast(usize, 8);
    var raw = alloc_mod.sandAlloc(self.entries_alloc, @intCast(usize, 4) * nc, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]u32, raw);
    var si: usize = @intCast(usize, 0);
    while (si < self.source_len) : (si += @intCast(usize, 1)) { new_items[si] = self.source_items[si]; }
    self.source_items = new_items;
    self.source_cap = nc;
}

pub fn resolvedSourceTableSet(self: *ResolvedTypeTable, node_idx: u32, source_name_id: u32) void {
    var existing = hash_mod.u32ToU32MapGet(&self.source_index, node_idx);
    if (existing) |entry_idx| {
        self.source_items[@intCast(usize, entry_idx)] = source_name_id;
        return;
    }
    sourceTableEnsureCapacity(self, self.source_len + 1);
    var new_idx = @intCast(u32, self.source_len);
    self.source_items[self.source_len] = source_name_id;
    self.source_len += 1;
    hash_mod.u32ToU32MapPut(&self.source_index, node_idx, new_idx);
}

pub fn resolvedSourceTableGet(self: *ResolvedTypeTable, node_idx: u32) ?u32 {
    var existing = hash_mod.u32ToU32MapGet(&self.source_index, node_idx);
    if (existing) |entry_idx| {
        return self.source_items[@intCast(usize, entry_idx)];
    }
    return null;
}
