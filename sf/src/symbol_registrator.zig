const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const mr_mod = @import("module_registry.zig");
const sym_mod = @import("symbol_table.zig");
const SymbolRegistry = sym_mod.SymbolRegistry;
const AstKind = @import("ast.zig").AstKind;
const ast_mod = @import("ast.zig");
const AstStore = @import("ast.zig").AstStore;
const type_mod = @import("type_registry.zig");
const TypeKind = type_mod.TypeKind;
const hash_mod = @import("util/hash.zig");

pub const DepEdge = struct { from: u32, to: u32 };

pub const DepGraph = struct {
    items: [*]DepEdge,
    len: usize,
    cap: usize,
    alloc: *Sand,
    in_degree_items: [*]u32,
    in_degree_cap: usize,
};

pub fn depGraphInit(alloc: *Sand) DepGraph {
    return DepGraph{
        .items = undefined,
        .len = @intCast(usize, 0),
        .cap = @intCast(usize, 0),
        .alloc = alloc,
        .in_degree_items = undefined,
        .in_degree_cap = @intCast(usize, 0),
    };
}

fn depGraphEnsureCapacity(self: *DepGraph) void {
    if (self.len < self.cap) return;
    var nc: usize = if (self.cap < 8) @intCast(usize, 8) else self.cap * 2;
    var raw = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 8) * nc, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]DepEdge, raw);
    for (self.items[0..self.len]) |item, i| { new_items[i] = item; }
    self.items = new_items;
    self.cap = nc;
}

pub fn depGraphAddEdge(self: *DepGraph, from: u32, to: u32) void {
    depGraphEnsureCapacity(self);
    self.items[self.len] = DepEdge{ .from = from, .to = to };
    self.len += 1;
}

pub fn depGraphFinalize(self: *DepGraph, max_type_id: u32) void {
    var count = @intCast(usize, max_type_id + @intCast(u32, 1));
    if (count > self.in_degree_cap) {
        var raw = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 4) * count, @intCast(usize, 4)) catch unreachable;
        self.in_degree_items = @ptrCast([*]u32, raw);
        self.in_degree_cap = count;
    }
    var i: usize = 0;
    while (i < count) { self.in_degree_items[i] = @intCast(u32, 0); i += 1; }
    i = 0;
    while (i < self.len) {
        self.in_degree_items[self.items[i].to] += 1;
        i += 1;
    }
}

fn addTypeDependencies(store: *AstStore, decl_idx: u32, tid: u32, g: *DepGraph) void {
    var node = store.nodes.items[decl_idx];
    if (node.payload == 0) return;
    var children = ast_mod.astStoreGetExtraChildren(store, node.payload);
    var i: usize = 0;
    while (i < children.len) {
        var field_node = store.nodes.items[children[i]];
        if (field_node.kind == AstKind.field_decl) {
            depGraphAddEdge(g, @intCast(u32, 0), tid);
        }
        i += 1;
    }
}

fn registerDecl(sym_reg: *SymbolRegistry, type_reg: *type_mod.TypeRegistry, store: *AstStore, mod_id: u32, decl_idx: u32, g: *DepGraph, reg: *mr_mod.ModuleRegistry) void {
    var node = store.nodes.items[decl_idx];
    switch (node.kind) {
        AstKind.var_decl => {
            var name_id = node.payload;
            var sym_kind = sym_mod.SymbolKind.global;
            var sym_mod_id = mod_id;
            if (node.child_1 != 0) {
                var init_node = store.nodes.items[@intCast(usize, node.child_1)];
                if (init_node.kind == AstKind.import_expr) {
                    var target = hash_mod.u32ToU32MapGet(&reg.path_to_id, init_node.payload);
                    if (target) |tid| {
                        sym_kind = sym_mod.SymbolKind.module;
                        sym_mod_id = tid;
                    }
                }
            }

            var sym = sym_mod.Symbol{
                .name_id = name_id,
                .type_id = @intCast(u32, 0),
                .kind = sym_kind,
                .flags = @intCast(u16, node.flags),
                .decl_node = decl_idx,
                .module_id = sym_mod_id,
                .scope_level = @intCast(u32, 0),
            };
            var table = sym_mod.symbolRegistryGetTable(sym_reg, mod_id);
            _ = sym_mod.symbolTableInsert(table, sym);
        },
        AstKind.fn_decl => {
            var proto = store.fn_protos.items[@intCast(usize, node.payload)];
            var sym = sym_mod.Symbol{
                .name_id = proto.name_id,
                .type_id = @intCast(u32, 0),
                .kind = sym_mod.SymbolKind.function,
                .flags = @intCast(u16, node.flags),
                .decl_node = decl_idx,
                .module_id = mod_id,
                .scope_level = @intCast(u32, 0),
            };
            var table = sym_mod.symbolRegistryGetTable(sym_reg, mod_id);
            _ = sym_mod.symbolTableInsert(table, sym);
        },
        AstKind.test_decl => {
            if (node.payload != 0) {
                var sym = sym_mod.Symbol{
                    .name_id = node.payload,
                    .type_id = @intCast(u32, 0),
                    .kind = sym_mod.SymbolKind.test_sym,
                    .flags = @intCast(u16, node.flags),
                    .decl_node = decl_idx,
                    .module_id = mod_id,
                    .scope_level = @intCast(u32, 0),
                };
                var table = sym_mod.symbolRegistryGetTable(sym_reg, mod_id);
                _ = sym_mod.symbolTableInsert(table, sym);
            }
        },
        AstKind.struct_decl, AstKind.enum_decl, AstKind.union_decl => {
            var name_id = node.payload;
            var type_kind: TypeKind = switch (node.kind) {
                AstKind.struct_decl => TypeKind.struct_type,
                AstKind.enum_decl => TypeKind.enum_type,
                AstKind.union_decl => if ((@intCast(u16, node.flags) & 1) != 0) TypeKind.tagged_union_type else TypeKind.union_type,
                else => TypeKind.void_type,
            };
            var tid = type_mod.typeRegistryRegisterNamedType(type_reg, mod_id, name_id, type_kind);
            addTypeDependencies(store, decl_idx, tid, g);
            var sym = sym_mod.Symbol{
                .name_id = name_id,
                .type_id = tid,
                .kind = sym_mod.SymbolKind.type_alias,
                .flags = @intCast(u16, node.flags),
                .decl_node = decl_idx,
                .module_id = mod_id,
                .scope_level = @intCast(u32, 0),
            };
            var table = sym_mod.symbolRegistryGetTable(sym_reg, mod_id);
            _ = sym_mod.symbolTableInsert(table, sym);
        },
        AstKind.error_set_decl => {
            var name_id = node.payload;
            var tid = type_mod.typeRegistryRegisterNamedType(type_reg, mod_id, name_id, TypeKind.error_set_type);
            var sym = sym_mod.Symbol{
                .name_id = name_id,
                .type_id = tid,
                .kind = sym_mod.SymbolKind.type_alias,
                .flags = @intCast(u16, node.flags),
                .decl_node = decl_idx,
                .module_id = mod_id,
                .scope_level = @intCast(u32, 0),
            };
            var table = sym_mod.symbolRegistryGetTable(sym_reg, mod_id);
            _ = sym_mod.symbolTableInsert(table, sym);
        },
        AstKind.import_expr => {
            var path_id = node.payload;
            var target_mod_id = hash_mod.u32ToU32MapGet(&reg.path_to_id, path_id);
            if (target_mod_id) |tid| {
                var sym = sym_mod.Symbol{
                    .name_id = path_id,
                    .type_id = @intCast(u32, 0),
                    .kind = sym_mod.SymbolKind.module,
                    .flags = @intCast(u16, 0),
                    .decl_node = decl_idx,
                    .module_id = tid,
                    .scope_level = @intCast(u32, 0),
                };
                var table = sym_mod.symbolRegistryGetTable(sym_reg, mod_id);
                _ = sym_mod.symbolTableInsert(table, sym);
            }
        },
        else => {},
    }
}

pub fn registerModuleSymbols(reg: *mr_mod.ModuleRegistry, sym_reg: *SymbolRegistry, type_reg: *type_mod.TypeRegistry, store: *AstStore, module_id: u32, g: *DepGraph) void {
    var entry = reg.modules.items[@intCast(usize, module_id)];
    if (entry.state != mr_mod.ModuleState.resolved or entry.ast_root == 0) return;
    var root = store.nodes.items[@intCast(usize, entry.ast_root)];
    if (root.kind != AstKind.module_root) return;
    var decls = ast_mod.astStoreGetExtraChildren(store, root.payload);
    var i: usize = 0;
    while (i < decls.len) {
        registerDecl(sym_reg, type_reg, store, module_id, decls[i], g, reg);
        i += 1;
    }
}
