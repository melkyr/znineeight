const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");

pub const StateEntry = struct {
    name_id: u32,
    state: u8,
};

pub const StateMap = struct {
    entries_items: [*]StateEntry,
    entries_len: usize,
    entries_cap: usize,
    entries_alloc: *Sand,
    parent: ?*StateMap,
};

pub fn stateMapInit(alloc: *Sand) StateMap {
    return StateMap{
        .entries_items = undefined,
        .entries_len = @intCast(usize, 0),
        .entries_cap = @intCast(usize, 0),
        .entries_alloc = alloc,
        .parent = null,
    };
}

fn stateMapEnsureCapacity(self: *StateMap, new_cap: usize) void {
    if (new_cap <= self.entries_cap) return;
    var nc = new_cap;
    if (nc < self.entries_cap * 2) nc = self.entries_cap * 2;
    if (nc < 8) nc = 8;
    var raw = alloc_mod.sandAlloc(self.entries_alloc, @intCast(usize, 8) * nc, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]StateEntry, raw);
    for (self.entries_items[0..self.entries_len]) |item, i| { new_items[i] = item; }
    self.entries_items = new_items;
    self.entries_cap = nc;
}

pub fn stateMapGet(self: *StateMap, name_id: u32) ?u8 {
    var i: usize = self.entries_len;
    while (i > 0) {
        i -= 1;
        if (self.entries_items[i].name_id == name_id) return self.entries_items[i].state;
    }
    if (self.parent) |p| return stateMapGet(p, name_id);
    return null;
}

pub fn stateMapSet(self: *StateMap, name_id: u32, state: u8) void {
    var i: usize = 0;
    while (i < self.entries_len) : (i += 1) {
        if (self.entries_items[i].name_id == name_id) {
            self.entries_items[i].state = state;
            return;
        }
    }
    stateMapEnsureCapacity(self, self.entries_len + 1);
    self.entries_items[self.entries_len] = StateEntry{ .name_id = name_id, .state = state };
    self.entries_len += 1;
}

pub fn stateMapFork(self: *StateMap, scratch: *Sand) *StateMap {
    var raw = alloc_mod.sandAlloc(scratch, @intCast(usize, @sizeOf(StateMap)), @intCast(usize, 4)) catch unreachable;
    var child = @ptrCast(*StateMap, raw);
    child.entries_items = undefined;
    child.entries_len = @intCast(usize, 0);
    child.entries_cap = @intCast(usize, 0);
    child.entries_alloc = scratch;
    child.parent = self;
    return child;
}

pub fn stateMapMergeStates(parent: *StateMap, branch_a: *StateMap, branch_b: *StateMap, unknown_state: u8) void {
    var i: usize = 0;
    while (i < branch_a.entries_len) : (i += 1) {
        var entry = branch_a.entries_items[i];
        var bs = stateMapGet(branch_b, entry.name_id);
        if (bs) |b_state| {
            if (b_state != entry.state) {
                stateMapSet(parent, entry.name_id, unknown_state);
            } else {
                stateMapSet(parent, entry.name_id, entry.state);
            }
        } else {
            var ps = stateMapGet(parent, entry.name_id);
            if (ps) |ps_val| {
                if (ps_val != entry.state) {
                    stateMapSet(parent, entry.name_id, unknown_state);
                }
            }
        }
    }
    var j: usize = 0;
    while (j < branch_b.entries_len) : (j += 1) {
        var entry = branch_b.entries_items[j];
        if (stateMapGet(branch_a, entry.name_id) == null) {
            var ps = stateMapGet(parent, entry.name_id);
            if (ps) |ps_val| {
                if (ps_val != entry.state) {
                    stateMapSet(parent, entry.name_id, unknown_state);
                }
            }
        }
    }
}

pub fn stateMapGetEntries(self: *StateMap) []StateEntry {
    return self.entries_items[0..self.entries_len];
}
