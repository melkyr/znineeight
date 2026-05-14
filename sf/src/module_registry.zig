const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const StringInterner = @import("string_interner.zig").StringInterner;
const interner_mod = @import("string_interner.zig");
const pal_mod = @import("pal.zig");

pub const ModuleState = enum(u8) {
    pending,
    parsing,
    parsed,
    resolved,
    failed,
};

pub const ModuleEntry = struct {
    id: u32,
    path_id: u32,
    state: ModuleState,
    ast_root: u32,
    import_count: u32,
    imports_start: u32,
    symbol_table: u32,
    type_offset: u32,
};

pub const ModuleEntryArrayList = struct {
    items: [*]ModuleEntry,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn moduleEntryArrayListInit(allocator: *Sand, initial_capacity: usize) ModuleEntryArrayList {
    var list = ModuleEntryArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
    moduleEntryArrayListEnsureCapacity(&list, initial_capacity);
    return list;
}

pub fn moduleEntryArrayListEnsureCapacity(self: *ModuleEntryArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < 8) new_cap = 8;
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, 32) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]ModuleEntry, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn moduleEntryArrayListAppend(self: *ModuleEntryArrayList, value: ModuleEntry) void {
    moduleEntryArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn moduleEntryArrayListGetSlice(self: *ModuleEntryArrayList) []ModuleEntry {
    return self.items[0..self.len];
}

pub const SearchDirArrayList = struct {
    items: [*]u32,
    len: usize,
    capacity: usize,
    alloc: *Sand,
};

fn searchDirArrayListEnsureCapacity(self: *SearchDirArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < 2) new_cap = 2;
    var raw = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]u32, raw);
    for (self.items[0..self.len]) |item, i| { new_items[i] = item; }
    self.items = new_items;
    self.capacity = new_cap;
}

fn searchDirArrayListAppend(self: *SearchDirArrayList, value: u32) void {
    searchDirArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub const ModuleResolver = struct {
    search_dirs: SearchDirArrayList,
    interner: *StringInterner,
    diag: *DiagnosticCollector,
};

fn joinPath(dir: []const u8, rel: []const u8, scratch: *Sand) ?[]u8 {
    var total = dir.len + @intCast(usize, 1) + rel.len;
    var raw = alloc_mod.sandAlloc(scratch, total, @intCast(usize, 1)) catch return null;
    var buf = @ptrCast([*]u8, raw);
    var i: usize = 0;
    while (i < dir.len) { buf[i] = dir[i]; i += 1; }
    buf[i] = '/'; i += 1;
    var j: usize = 0;
    while (j < rel.len) { buf[i + j] = rel[j]; j += 1; }
    return buf[0..total];
}

fn moduleDirPath(path: []const u8) []const u8 {
    var i: usize = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/') return path[0..i];
    }
    return "";
}

pub fn moduleResolverInit(alloc: *Sand, interner: *StringInterner, diag: *DiagnosticCollector) ModuleResolver {
    return ModuleResolver{
        .search_dirs = SearchDirArrayList{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0), .alloc = alloc },
        .interner = interner,
        .diag = diag,
    };
}

pub fn moduleResolverAddSearchDir(self: *ModuleResolver, dir: []const u8) void {
    var id = interner_mod.stringInternerIntern(self.interner, dir);
    searchDirArrayListAppend(&self.search_dirs, id);
}

pub fn moduleResolverResolve(self: *ModuleResolver, importer_path: []const u8, target: []const u8, scratch: *Sand) ?u32 {
    var importer_dir = moduleDirPath(importer_path);
    if (importer_dir.len > 0) {
        var full = joinPath(importer_dir, target, scratch) orelse return null;
        if (pal_mod.fileExists(full)) return interner_mod.stringInternerIntern(self.interner, full);
    }
    var i: usize = 0;
    while (i < self.search_dirs.len) {
        var dir = interner_mod.stringInternerGet(self.interner, self.search_dirs.items[i]);
        var full = joinPath(dir, target, scratch) orelse return null;
        if (pal_mod.fileExists(full)) return interner_mod.stringInternerIntern(self.interner, full);
        i += 1;
    }
    var lib_s: []const u8 = ".";
    var lib_full = joinPath(lib_s, target, scratch) orelse return null;
    if (pal_mod.fileExists(lib_full)) return interner_mod.stringInternerIntern(self.interner, lib_full);
    return null;
}

const U32ToU32Map = struct {
    keys: [*]u32,
    values: [*]u32,
    occupied: [*]u8,
    capacity: usize,
    count: usize,
    alloc: *Sand,
};

fn u32ToU32MapInit(alloc: *Sand) U32ToU32Map {
    return U32ToU32Map{
        .keys = undefined, .values = undefined, .occupied = undefined,
        .capacity = @intCast(usize, 0), .count = @intCast(usize, 0), .alloc = alloc,
    };
}

fn u32ToU32MapGet(self: *U32ToU32Map, key: u32) ?u32 {
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

fn u32ToU32MapPut(self: *U32ToU32Map, key: u32, value: u32) void {
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

pub const ModuleRegistry = struct {
    modules: ModuleEntryArrayList,
    import_edges_items: [*]u32,
    import_edges_len: usize,
    import_edges_cap: usize,
    import_edges_alloc: *Sand,
    resolver: ModuleResolver,
    interner: *StringInterner,
    diag: *DiagnosticCollector,
    alloc: *Sand,
    next_id: u32,
    path_to_id: U32ToU32Map,
};

fn importEdgesEnsureCapacity(items: *[*]u32, len: *usize, cap: *usize, alloc: *Sand, new_cap: usize) void {
    if (new_cap <= cap.*) return;
    var nc = new_cap;
    if (nc < cap.* * 2) nc = cap.* * 2;
    if (nc < 8) nc = 8;
    var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, 4) * nc, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]u32, raw);
    for (items.*[0..len.*]) |item, i| { new_items[i] = item; }
    items.* = new_items;
    cap.* = nc;
}

fn importEdgesAppend(items: *[*]u32, len: *usize, cap: *usize, alloc: *Sand, value: u32) void {
    importEdgesEnsureCapacity(items, len, cap, alloc, len.* + 1);
    items.*[len.*] = value;
    len.* += 1;
}

pub fn moduleRegistryInit(alloc: *Sand, interner: *StringInterner, diag: *DiagnosticCollector) ModuleRegistry {
    return ModuleRegistry{
        .modules = moduleEntryArrayListInit(alloc, 8),
        .import_edges_items = undefined,
        .import_edges_len = @intCast(usize, 0),
        .import_edges_cap = @intCast(usize, 0),
        .import_edges_alloc = alloc,
        .resolver = moduleResolverInit(alloc, interner, diag),
        .interner = interner,
        .diag = diag,
        .alloc = alloc,
        .next_id = @intCast(u32, 0),
        .path_to_id = u32ToU32MapInit(alloc),
    };
}

pub fn moduleRegistryAddModule(self: *ModuleRegistry, path_id: u32) u32 {
    var id = self.next_id;
    var entry = ModuleEntry{
        .id = id,
        .path_id = path_id,
        .state = ModuleState.pending,
        .ast_root = @intCast(u32, 0),
        .import_count = @intCast(u32, 0),
        .imports_start = @intCast(u32, 0),
        .symbol_table = @intCast(u32, 0),
        .type_offset = @intCast(u32, 0),
    };
    moduleEntryArrayListAppend(&self.modules, entry);
    self.next_id += 1;
    return id;
}

pub fn moduleRegistryGetOrCreateModule(self: *ModuleRegistry, path_id: u32) u32 {
    var existing = u32ToU32MapGet(&self.path_to_id, path_id);
    if (existing) |id| return id;
    var new_id = moduleRegistryAddModule(self, path_id);
    u32ToU32MapPut(&self.path_to_id, path_id, new_id);
    return new_id;
}

pub fn moduleRegistryAddImport(self: *ModuleRegistry, importer_id: u32, imported_id: u32) void {
    importEdgesAppend(&self.import_edges_items, &self.import_edges_len, &self.import_edges_cap, self.import_edges_alloc, imported_id);
    var entry = self.modules.items[importer_id];
    if (entry.import_count == @intCast(u32, 0)) entry.imports_start = @intCast(u32, self.import_edges_len - 1);
    entry.import_count += 1;
    self.modules.items[importer_id] = entry;
}

pub fn moduleRegistryResolveImport(self: *ModuleRegistry, path_id: u32, importer_id: u32, scratch: *Sand) ?u32 {
    var path_s = interner_mod.stringInternerGet(self.interner, path_id);
    var resolved_path_id = moduleResolverResolve(&self.resolver, path_s, path_s, scratch) orelse return null;
    var mod_id = moduleRegistryGetOrCreateModule(self, resolved_path_id);
    moduleRegistryAddImport(self, importer_id, mod_id);
    return mod_id;
}
