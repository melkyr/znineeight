const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const diag_mod = @import("diagnostics.zig");
const StringInterner = @import("string_interner.zig").StringInterner;
const interner_mod = @import("string_interner.zig");
const pal_mod = @import("pal.zig");
const hash_mod = @import("util/hash.zig");
const path_mod = @import("util/path.zig");
const SourceManager = @import("source_manager.zig").SourceManager;
const ga_mod = @import("growable_array.zig");
const U32ArrayList = ga_mod.U32ArrayList;
const AstStore = @import("ast.zig").AstStore;
const AstKind = @import("ast.zig").AstKind;

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
    source_file_id: u32,
    state: ModuleState,
    ast_root: u32,
    import_count: u32,
    imports_start: u32,
    symbol_table: u32,
    type_offset: u32,
    c_includes: U32ArrayList,
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
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, @sizeOf(ModuleEntry)) * new_cap, @intCast(usize, 4)) catch unreachable;
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

fn joinPath(dir: []const u8, rel: []const u8, scratch: *Sand) ?[]const u8 {
    var total: usize = dir.len + @intCast(usize, 1) + rel.len;
    var raw = alloc_mod.sandAlloc(scratch, total, @intCast(usize, 1)) catch return null;
    var buf = @ptrCast([*]u8, raw);
    var i: usize = 0;
    while (i < dir.len) { buf[i] = dir[i]; i += 1; }
    buf[i] = '/'; i += 1;
    var j: usize = 0;
    while (j < rel.len) { buf[i + j] = rel[j]; j += 1; }
    var full = buf[0..total];
    var norm = path_mod.normalizePath(full, full) orelse return full;
    return norm;
}

fn moduleDirPath(path: []const u8) []const u8 {
    var i: usize = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/') return path[0..i];
    }
    var empty_str: []const u8 = "";
    return empty_str;
}

fn appendZigExt(target: []const u8, scratch: *Sand) ?[]u8 {
    var total: usize = target.len + @intCast(usize, 4);
    var raw = alloc_mod.sandAlloc(scratch, total, @intCast(usize, 1)) catch return null;
    var buf = @ptrCast([*]u8, raw);
    var i: usize = 0;
    while (i < target.len) { buf[i] = target[i]; i += 1; }
    buf[i] = '.'; i += 1;
    buf[i] = 'z'; i += 1;
    buf[i] = 'i'; i += 1;
    buf[i] = 'g';
    return buf[0..total];
}

fn moduleResolverTryDir(self: *ModuleResolver, dir: []const u8, target: []const u8, scratch: *Sand) ?u32 {
    var full = joinPath(dir, target, scratch) orelse return null;
    if (pal_mod.fileExists(full)) return interner_mod.stringInternerIntern(self.interner, full);
    var tzig = appendZigExt(target, scratch) orelse return null;
    var full2 = joinPath(dir, tzig, scratch) orelse return null;
    if (pal_mod.fileExists(full2)) return interner_mod.stringInternerIntern(self.interner, full2);
    return null;
}

pub fn moduleResolverInit(alloc: *Sand, interner: *StringInterner, diag: *DiagnosticCollector) ModuleResolver {
    return ModuleResolver{
        .search_dirs = SearchDirArrayList{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0), .alloc = alloc },
        .interner = interner,
        .diag = diag,
    };
}

pub fn moduleResolverAddSearchDir(self: *ModuleResolver, dir: []const u8) void {
    var buf: [512]u8 = undefined;
    var use_dir = dir;
    if (dir.len <= 512) {
        var norm = path_mod.normalizePath(buf[0..dir.len], dir);
        if (norm) |n| use_dir = n;
    }
    var id = interner_mod.stringInternerIntern(self.interner, use_dir);
    searchDirArrayListAppend(&self.search_dirs, id);
}

pub fn moduleResolverResolve(self: *ModuleResolver, importer_path: []const u8, target: []const u8, scratch: *Sand) ?u32 {
    var importer_dir = moduleDirPath(importer_path);
    if (importer_dir.len > 0) {
        var id = moduleResolverTryDir(self, importer_dir, target, scratch);
        if (id) |v| return v;
    }
    var i: usize = 0;
    while (i < self.search_dirs.len) {
        var dir = interner_mod.stringInternerGet(self.interner, self.search_dirs.items[i]);
        var id = moduleResolverTryDir(self, dir, target, scratch);
        if (id) |v| return v;
        i += 1;
    }
    var lib_s: []const u8 = ".";
    var id = moduleResolverTryDir(self, lib_s, target, scratch);
    if (id) |v| return v;
    return null;
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
    source_man: *SourceManager,
    alloc: *Sand,
    next_id: u32,
    path_to_id: hash_mod.U32ToU32Map,
    content_to_id: hash_mod.U32ToU32Map,
    import_queue: ImportQueue,
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

var source_man_stub: u8 = 0;

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
        .source_man = @ptrCast(*SourceManager, &source_man_stub),
        .alloc = alloc,
        .next_id = @intCast(u32, 0),
        .path_to_id = hash_mod.u32ToU32MapInit(alloc),
        .content_to_id = hash_mod.u32ToU32MapInit(alloc),
        .import_queue = importQueueInit(alloc, diag),
    };
}

pub fn moduleRegistrySetSourceMan(self: *ModuleRegistry, sm: *SourceManager) void {
    self.source_man = sm;
}

pub fn moduleRegistryAddModule(self: *ModuleRegistry, path_id: u32) u32 {
    var id = self.next_id;
    var entry = ModuleEntry{
        .id = id,
        .path_id = path_id,
        .source_file_id = @intCast(u32, 0),
        .state = ModuleState.pending,
        .ast_root = @intCast(u32, 0),
        .import_count = @intCast(u32, 0),
        .imports_start = @intCast(u32, 0),
        .symbol_table = @intCast(u32, 0),
        .type_offset = @intCast(u32, 0),
        .c_includes = ga_mod.u32ArrayListInit(self.alloc),
    };
    moduleEntryArrayListAppend(&self.modules, entry);
    self.next_id += 1;
    return id;
}

pub fn moduleRegistryGetModules(self: *ModuleRegistry) []ModuleEntry {
    return self.modules.items[0..self.modules.len];
}

pub fn moduleRegistryGetOrCreateModule(self: *ModuleRegistry, path_id: u32) u32 {
    var existing = hash_mod.u32ToU32MapGet(&self.path_to_id, path_id);
    if (existing) |id| return id;
    var new_id = moduleRegistryAddModule(self, path_id);
    hash_mod.u32ToU32MapPut(&self.path_to_id, path_id, new_id);
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
    var importer_path = interner_mod.stringInternerGet(self.interner, self.modules.items[importer_id].path_id);
    var resolved_path_id = moduleResolverResolve(&self.resolver, importer_path, path_s, scratch) orelse {
        var p1: []const u8 = "could not resolve imported file '";
        var p2: []const u8 = "'";
        var parts: [3][]const u8 = [3][]const u8{ p1, path_s, p2 };
        var msg = diag_mod.diagnosticBuilderMakeMsg(self.interner, &parts[0], @intCast(u32, 3));
        diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3048_CANNOT_READ_FILE)), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), msg);
        return null;
    };

    // Path-level dedup (primary guard — canonical path strings once joinPath
    // normalizes; the syntactic-alias class collapses here).
    var by_path = hash_mod.u32ToU32MapGet(&self.path_to_id, resolved_path_id);
    if (by_path) |existing_id| {
        moduleRegistryAddImport(self, importer_id, existing_id);
        importQueueEnqueue(&self.import_queue, existing_id);
        _ = hash_mod.u32ToU32MapPut(&self.path_to_id, path_id, existing_id);
        return existing_id;
    }

    // Content-hash double-guard (resolve-time, before entry creation): hash the
    // module source; if an identical source is already recorded, reuse that
    // module id instead of creating a duplicate entry. No merge/neuter needed —
    // the duplicate entry is simply never created.
    var resolved_path_s = interner_mod.stringInternerGet(self.interner, resolved_path_id);
    var content = pal_mod.readFile(resolved_path_s, scratch) orelse {
        // resolve-time read failed (rare) — fall through to the normal create
        // path; the parse loop reports error[3048] if the file is genuinely
        // unreadable.
        var mod_id = moduleRegistryGetOrCreateModule(self, resolved_path_id);
        moduleRegistryAddImport(self, importer_id, mod_id);
        importQueueEnqueue(&self.import_queue, mod_id);
        _ = hash_mod.u32ToU32MapPut(&self.path_to_id, path_id, mod_id);
        return mod_id;
    };
    var c_hash = hash_mod.fnv1a(content);
    var by_content = hash_mod.u32ToU32MapGet(&self.content_to_id, c_hash);
    if (by_content) |target_id| {
        _ = hash_mod.u32ToU32MapPut(&self.path_to_id, resolved_path_id, target_id);
        moduleRegistryAddImport(self, importer_id, target_id);
        importQueueEnqueue(&self.import_queue, target_id);
        _ = hash_mod.u32ToU32MapPut(&self.path_to_id, path_id, target_id);
        return target_id;
    }
    var mod_id = moduleRegistryGetOrCreateModule(self, resolved_path_id);
    _ = hash_mod.u32ToU32MapPut(&self.content_to_id, c_hash, mod_id);
    moduleRegistryAddImport(self, importer_id, mod_id);
    importQueueEnqueue(&self.import_queue, mod_id);
    _ = hash_mod.u32ToU32MapPut(&self.path_to_id, path_id, mod_id);
    return mod_id;
}

pub const ImportQueue = struct {
    pending_items: [*]u32,
    pending_len: usize,
    pending_cap: usize,
    pending_alloc: *Sand,
    diag: *DiagnosticCollector,
};

fn importQueuePendingEnsureCapacity(items: *[*]u32, len: *usize, cap: *usize, alloc: *Sand, new_cap: usize) void {
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

fn importQueuePendingAppend(items: *[*]u32, len: *usize, cap: *usize, alloc: *Sand, value: u32) void {
    importQueuePendingEnsureCapacity(items, len, cap, alloc, len.* + 1);
    items.*[len.*] = value;
    len.* += 1;
}

fn importQueuePendingPop(items: *[*]u32, len: *usize) ?u32 {
    if (len.* == @intCast(usize, 0)) return null;
    len.* -= 1;
    return items.*[len.*];
}

pub fn importQueueInit(alloc: *Sand, diag: *DiagnosticCollector) ImportQueue {
    var q = ImportQueue{
        .pending_items = undefined,
        .pending_len = @intCast(usize, 0),
        .pending_cap = @intCast(usize, 0),
        .pending_alloc = alloc,
        .diag = diag,
    };
    return q;
}

pub fn importQueueEnqueue(self: *ImportQueue, module_id: u32) void {
    var i: usize = 0;
    while (i < self.pending_len) {
        if (self.pending_items[i] == module_id) return;
        i += 1;
    }
    importQueuePendingAppend(&self.pending_items, &self.pending_len, &self.pending_cap, self.pending_alloc, module_id);
}

pub fn importQueueDequeue(self: *ImportQueue) ?u32 {
    return importQueuePendingPop(&self.pending_items, &self.pending_len);
}

// KEPT (unwired) — topological module sort per Import_Symbol_reg.md §3; currently not wired into pipeline (fix pending import-edge attribution bug in parser.zig:641-643). Also exercised by tests (test_mod_reg_bin.zig).
pub fn moduleRegistrySortModules(reg: *ModuleRegistry) void {
    var mod_count = reg.modules.len;
    var in_degree: [256]u32 = undefined;
    var i: usize = 0;
    while (i < mod_count) { in_degree[i] = 0; i += 1; }
    i = 0;
    while (i < mod_count) {
        var entry = reg.modules.items[i];
        if (entry.state != ModuleState.failed) {
            in_degree[i] = entry.import_count;
        }
        i += 1;
    }
    i = 0;
    var worklist_items: [256]u32 = undefined;
    var worklist_len: usize = 0;
    while (i < mod_count) {
        if (in_degree[i] == 0 and reg.modules.items[i].state != ModuleState.failed) {
            worklist_items[worklist_len] = @intCast(u32, i);
            worklist_len += 1;
        }
        i += 1;
    }
    var si: usize = 0;
    while (si < worklist_len) {
        var sj: usize = si + 1;
        while (sj < worklist_len) {
            if (worklist_items[si] > worklist_items[sj]) {
                var tmp = worklist_items[si];
                worklist_items[si] = worklist_items[sj];
                worklist_items[sj] = tmp;
            }
            sj += 1;
        }
        si += 1;
    }
    var sorted_count: u32 = 0;
    while (worklist_len > 0) {
        worklist_len -= 1;
        var id = worklist_items[worklist_len];
        var id_idx = @intCast(usize, id);
        if (reg.modules.items[id_idx].state == ModuleState.failed) continue;
        var entry = reg.modules.items[id_idx];
        entry.state = ModuleState.resolved;
        reg.modules.items[id_idx] = entry;
        sorted_count += 1;
        var ii: usize = 0;
        while (ii < mod_count) {
            var imp_entry = reg.modules.items[ii];
            if (imp_entry.state != ModuleState.failed) {
                var start = @intCast(usize, imp_entry.imports_start);
                var end = start + @intCast(usize, imp_entry.import_count);
                var j: usize = start;
                while (j < end) {
                    if (reg.import_edges_items[j] == id) {
                        if (in_degree[ii] > 0) in_degree[ii] -= 1;
                        if (in_degree[ii] == 0) {
                            worklist_items[worklist_len] = @intCast(u32, ii);
                            worklist_len += 1;
                        }
                    }
                    j += 1;
                }
            }
            ii += 1;
        }
    }
    if (sorted_count < @intCast(u32, mod_count)) {
        var ci: usize = 0;
        while (ci < mod_count) {
            var entry = reg.modules.items[ci];
            if (entry.state != ModuleState.failed and in_degree[ci] > 0) {
                var mn = interner_mod.stringInternerGet(reg.interner, entry.path_id);
                var cp1: []const u8 = "circular import detected in module '";
                var cp2: []const u8 = "'";
                var cparts: [3][]const u8 = [3][]const u8{cp1, mn, cp2};
                var msg = diag_mod.diagnosticBuilderMakeMsg(reg.diag.interner, &cparts[0], @intCast(u32, 3));
                diag_mod.diagnosticCollectorAdd(reg.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3005_CIRCULAR_TYPE_DEPENDENCY)), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), msg);
                entry.state = ModuleState.failed;
                reg.modules.items[ci] = entry;
            }
            ci += 1;
        }
    }
    moduleRegistryVerifyOrder(reg);
}

pub fn moduleRegistryVerifyOrder(reg: *ModuleRegistry) void {
    var mod_count = reg.modules.len;
    var vi: usize = 0;
    while (vi < mod_count) {
        var entry = reg.modules.items[vi];
        if (entry.state == ModuleState.resolved) {
            var start = @intCast(usize, entry.imports_start);
            var end = start + @intCast(usize, entry.import_count);
            var vj: usize = start;
            while (vj < end) {
                var imp_id = reg.import_edges_items[vj];
                var imp = reg.modules.items[@intCast(usize, imp_id)];
                if (imp.state != ModuleState.resolved and imp.state != ModuleState.failed) {
                    var msg: []const u8 = "topological sort violation: import not resolved";
                    diag_mod.diagnosticCollectorAdd(reg.diag, @intCast(u8, 0),
                        @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_4000_INVALID_CONTROL_FLOW)),
                        @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), msg);
                }
                vj += 1;
            }
        }
        vi += 1;
    }
}

pub fn moduleRegistryCollectIncludes(store: *AstStore, decls: []u32, c_includes: *U32ArrayList) void {
    var di: usize = @intCast(usize, 0);
    while (di < decls.len) : (di += @intCast(usize, 1)) {
        var decl = store.nodes.items[@intCast(usize, decls[di])];
        if (decl.kind == AstKind.c_include) {
            ga_mod.u32ArrayListAppend(c_includes, decl.payload);
        } else if (decl.kind == AstKind.var_decl and decl.child_1 != @intCast(u32, 0)) {
            var init = store.nodes.items[@intCast(usize, decl.child_1)];
            if (init.kind == AstKind.c_include) {
                ga_mod.u32ArrayListAppend(c_includes, init.payload);
            }
        }
    }
}
