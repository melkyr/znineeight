const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = @import("type_registry.zig").TypeId;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const diag_mod = @import("diagnostics.zig");
const sym_reg = @import("symbol_registrator.zig");
const DepEdge = sym_reg.DepEdge;

pub const TypeResolver = struct {
    registry: *TypeRegistry,
    depend_items: [*]DepEdge,
    depend_len: usize,
    depend_cap: usize,
    in_degree_items: [*]u32,
    in_degree_cap: usize,
    worklist_items: [*]u32,
    worklist_len: usize,
    worklist_cap: usize,
    diag: *DiagnosticCollector,
    alloc: *Sand,
};

fn dependEnsureCapacity(self: *TypeResolver) void {
    if (self.depend_len < self.depend_cap) return;
    var nc = if (self.depend_cap < 8) @intCast(usize, 8) else self.depend_cap * 2;
    var raw = alloc_mod.sandAlloc(self.alloc, nc * @intCast(usize, 8), @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]DepEdge, raw);
    for (self.depend_items[0..self.depend_len]) |item, i| { new_items[i] = item; }
    self.depend_items = new_items;
    self.depend_cap = nc;
}

pub fn typeResolverAddEdge(self: *TypeResolver, from: u32, to: u32) void {
    dependEnsureCapacity(self);
    self.depend_items[self.depend_len] = DepEdge{ .from = from, .to = to };
    self.depend_len += 1;
}

fn worklistEnsureCapacity(self: *TypeResolver) void {
    if (self.worklist_len < self.worklist_cap) return;
    var nc = if (self.worklist_cap < 64) @intCast(usize, 64) else self.worklist_cap * 2;
    var raw = alloc_mod.sandAlloc(self.alloc, nc * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]u32, raw);
    for (self.worklist_items[0..self.worklist_len]) |item, i| { new_items[i] = item; }
    self.worklist_items = new_items;
    self.worklist_cap = nc;
}

fn worklistPush(self: *TypeResolver, id: u32) void {
    worklistEnsureCapacity(self);
    self.worklist_items[self.worklist_len] = id;
    self.worklist_len += 1;
}

fn worklistPop(self: *TypeResolver) ?u32 {
    if (self.worklist_len == 0) return null;
    self.worklist_len -= 1;
    return self.worklist_items[self.worklist_len];
}

fn inDegreeEnsureCapacity(self: *TypeResolver, capacity: usize) void {
    if (capacity <= self.in_degree_cap) return;
    var nc = capacity;
    if (nc < 64) nc = 64;
    var raw = alloc_mod.sandAlloc(self.alloc, nc * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable;
    self.in_degree_items = @ptrCast([*]u32, raw);
    self.in_degree_cap = nc;
}

pub fn typeResolverInit(registry: *TypeRegistry, diag: *DiagnosticCollector, alloc: *Sand) TypeResolver {
    return TypeResolver{
        .registry = registry,
        .depend_items = undefined,
        .depend_len = @intCast(usize, 0),
        .depend_cap = @intCast(usize, 0),
        .in_degree_items = undefined,
        .in_degree_cap = @intCast(usize, 0),
        .worklist_items = undefined,
        .worklist_len = @intCast(usize, 0),
        .worklist_cap = @intCast(usize, 0),
        .diag = diag,
        .alloc = alloc,
    };
}

pub fn typeResolverBuild(self: *TypeResolver, g: *sym_reg.DepGraph) void {
    var i: usize = 0;
    while (i < g.len) {
        typeResolverAddEdge(self, g.items[i].from, g.items[i].to);
        i += 1;
    }
    var type_count = self.registry.types_len;
    inDegreeEnsureCapacity(self, type_count);
    var zi: usize = 0;
    while (zi < type_count) {
        self.in_degree_items[zi] = @intCast(u32, 0);
        zi += 1;
    }
    var ei: usize = 0;
    while (ei < self.depend_len) {
        var target = self.depend_items[ei].to;
        if (@intCast(usize, target) < type_count) {
            self.in_degree_items[@intCast(usize, target)] += 1;
        }
        ei += 1;
    }
}

pub fn typeResolverResolve(self: *TypeResolver) void {
    var type_count = self.registry.types_len;
    if (type_count == 0) return;

    var ti: usize = 0;
    while (ti < type_count) {
        if (self.in_degree_items[ti] == 0) {
            worklistPush(self, @intCast(u32, ti));
        }
        ti += 1;
    }

    while (self.worklist_len > 0) {
        var tid_val = worklistPop(self);
        if (tid_val) |tid| {
            self.registry.types_items[@intCast(usize, tid)].state = @intCast(u8, 2);
            var ei: usize = 0;
            while (ei < self.depend_len) {
                if (self.depend_items[ei].from == tid) {
                    var dep = self.depend_items[ei].to;
                    var dep_idx = @intCast(usize, dep);
                    if (dep_idx < type_count) {
                        if (self.in_degree_items[dep_idx] > 0) {
                            self.in_degree_items[dep_idx] -= 1;
                            if (self.in_degree_items[dep_idx] == 0) {
                                worklistPush(self, dep);
                            }
                        }
                    }
                }
                ei += 1;
            }
        }
    }

    var ci: usize = 0;
    while (ci < type_count) {
        if (self.in_degree_items[ci] > 0) {
            var msg: []const u8 = "circular type dependency (infinite size)";
            diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0),
                @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3005_CIRCULAR_TYPE_DEPENDENCY)), @intCast(u32, 0),
                @intCast(u32, 0), @intCast(u32, 0), msg);
        }
        ci += 1;
    }
}
