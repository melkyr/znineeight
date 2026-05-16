const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");

pub const Symbol = struct {
    name_id: u32,
    type_id: u32,
    kind: SymbolKind,
    flags: u16,
    decl_node: u32,
    module_id: u32,
    scope_level: u32,
};

pub const SymbolKind = enum(u8) {
    local = 0,
    param = 1,
    global = 2,
    function = 3,
    type_alias = 4,
    module = 5,
    test_sym = 6,
};

pub const SymbolTable = struct {
    items: [*]Symbol,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn symbolTableInit(allocator: *Sand) SymbolTable {
    return SymbolTable{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

fn symbolTableEnsureCapacity(self: *SymbolTable, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var nc = new_capacity;
    if (nc < self.capacity * 2) nc = self.capacity * 2;
    if (nc < 8) nc = 8;
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, 24) * nc, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]Symbol, raw);
    for (self.items[0..self.len]) |item, i| { new_items[i] = item; }
    self.items = new_items;
    self.capacity = nc;
}

pub fn symbolTableInsert(self: *SymbolTable, sym: Symbol) bool {
    var i: usize = 0;
    while (i < self.len) {
        if (self.items[i].name_id == sym.name_id) return false;
        i += 1;
    }
    symbolTableEnsureCapacity(self, self.len + 1);
    self.items[self.len] = sym;
    self.len += 1;
    return true;
}

pub fn symbolTableLookup(self: *SymbolTable, name_id: u32) ?*Symbol {
    var i: usize = 0;
    while (i < self.len) {
        if (self.items[i].name_id == name_id) return &self.items[i];
        i += 1;
    }
    return null;
}

pub const SymbolRegistry = struct {
    tables_items: [*]SymbolTable,
    tables_len: usize,
    tables_cap: usize,
    tables_alloc: *Sand,
};

fn symbolRegistryEnsureCapacity(self: *SymbolRegistry, new_cap: usize) void {
    if (new_cap <= self.tables_cap) return;
    var nc = new_cap;
    if (nc < self.tables_cap * 2) nc = self.tables_cap * 2;
    if (nc < 8) nc = 8;
    var raw = alloc_mod.sandAlloc(self.tables_alloc, @intCast(usize, 16) * nc, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]SymbolTable, raw);
    for (self.tables_items[0..self.tables_len]) |item, i| { new_items[i] = item; }
    self.tables_items = new_items;
    self.tables_cap = nc;
}

pub fn symbolRegistryInit(alloc: *Sand) SymbolRegistry {
    return SymbolRegistry{
        .tables_items = undefined,
        .tables_len = @intCast(usize, 0),
        .tables_cap = @intCast(usize, 0),
        .tables_alloc = alloc,
    };
}

pub fn symbolRegistryGetTable(self: *SymbolRegistry, module_id: u32) *SymbolTable {
    var idx = @intCast(usize, module_id);
    if (idx >= self.tables_len) {
        symbolRegistryEnsureCapacity(self, idx + 1);
        var zi = self.tables_len;
        while (zi <= idx) {
            self.tables_items[zi] = symbolTableInit(self.tables_alloc);
            zi += 1;
        }
        self.tables_len = idx + 1;
    }
    return &self.tables_items[idx];
}

pub fn symbolIsPublic(sym: *Symbol) bool {
    return (sym.flags & @intCast(u16, 2)) != 0;
}

pub fn symbolRegistryQualifiedLookup(reg: *SymbolRegistry, mod_id: u32, name_id: u32) ?*Symbol {
    var table = symbolRegistryGetTable(reg, mod_id);
    return symbolTableLookup(table, name_id);
}
