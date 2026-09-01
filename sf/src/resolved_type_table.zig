const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const TypeId = @import("type_registry.zig").TypeId;

pub const ResolvedTypeTable = struct {
    types_items: [*]u32,
    types_flags: [*]u8,
    source_items: [*]u32,
    source_flags: [*]u8,
    cap: usize,
    entries_alloc: *Sand,
};

pub fn resolvedTypeTableInit(alloc: *Sand) ResolvedTypeTable {
    return ResolvedTypeTable{
        .types_items = undefined,
        .types_flags = undefined,
        .source_items = undefined,
        .source_flags = undefined,
        .cap = @intCast(usize, 0),
        .entries_alloc = alloc,
    };
}

fn resolvedTypeTableGrowU32(self: *ResolvedTypeTable, items: *[*]u32, new_cap: usize) void {
    var old_cap = self.cap;
    if (old_cap > 0) {
        var grown = alloc_mod.sandTryReallocInPlace(self.entries_alloc,
            @ptrCast([*]u8, items.*),
            old_cap * @intCast(usize, 4),
            new_cap * @intCast(usize, 4),
            @intCast(usize, 4));
        if (grown != null) {
            return;
        }
    }
    var raw = alloc_mod.sandAlloc(self.entries_alloc, new_cap * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]u32, raw);
    var i: usize = 0;
    while (i < old_cap) : (i += 1) {
        new_items[i] = items.*[i];
    }
    items.* = new_items;
}

fn resolvedTypeTableGrowU8(self: *ResolvedTypeTable, items: *[*]u8, new_cap: usize) void {
    var old_cap = self.cap;
    if (old_cap > 0) {
        var grown = alloc_mod.sandTryReallocInPlace(self.entries_alloc,
            @ptrCast([*]u8, items.*),
            old_cap,
            new_cap,
            @intCast(usize, 1));
        if (grown != null) {
            var gi: usize = old_cap;
            while (gi < new_cap) : (gi += 1) {
                items.*[gi] = @intCast(u8, 0);
            }
            return;
        }
    }
    var raw = alloc_mod.sandAlloc(self.entries_alloc, new_cap, @intCast(usize, 1)) catch unreachable;
    var new_items = raw;
    var i: usize = 0;
    while (i < old_cap) : (i += 1) {
        new_items[i] = items.*[i];
    }
    while (i < new_cap) : (i += 1) {
        new_items[i] = @intCast(u8, 0);
    }
    items.* = new_items;
}

fn resolvedTypeTableGrow(self: *ResolvedTypeTable, new_cap: usize) void {
    if (new_cap <= self.cap) return;
    resolvedTypeTableGrowU32(self, &self.types_items, new_cap);
    resolvedTypeTableGrowU8(self, &self.types_flags, new_cap);
    resolvedTypeTableGrowU32(self, &self.source_items, new_cap);
    resolvedTypeTableGrowU8(self, &self.source_flags, new_cap);
    self.cap = new_cap;
}

pub fn resolvedTypeTableReserve(self: *ResolvedTypeTable, node_count: usize) void {
    resolvedTypeTableGrow(self, node_count);
}

pub fn resolvedTypeTableSet(self: *ResolvedTypeTable, node_idx: u32, type_id: TypeId) void {
    var ni = @intCast(usize, node_idx);
    if (ni >= self.cap) resolvedTypeTableGrow(self, ni + 1);
    self.types_items[ni] = type_id;
    self.types_flags[ni] = @intCast(u8, 1);
}

pub fn resolvedTypeTableGet(self: *ResolvedTypeTable, node_idx: u32) ?TypeId {
    var ni = @intCast(usize, node_idx);
    if (ni < self.cap and self.types_flags[ni] != @intCast(u8, 0)) {
        return self.types_items[ni];
    }
    return null;
}

pub fn resolvedSourceTableSet(self: *ResolvedTypeTable, node_idx: u32, source_name_id: u32) void {
    var ni = @intCast(usize, node_idx);
    if (ni >= self.cap) resolvedTypeTableGrow(self, ni + 1);
    self.source_items[ni] = source_name_id;
    self.source_flags[ni] = @intCast(u8, 1);
}

pub fn resolvedSourceTableGet(self: *ResolvedTypeTable, node_idx: u32) ?u32 {
    var ni = @intCast(usize, node_idx);
    if (ni < self.cap and self.source_flags[ni] != @intCast(u8, 0)) {
        return self.source_items[ni];
    }
    return null;
}
