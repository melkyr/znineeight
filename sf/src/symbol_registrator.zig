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
const pal_mod = @import("pal.zig");
const itoa_mod = @import("util/itoa.zig");
const type_resolver = @import("type_resolver.zig");

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
    if (self.cap > 0) {
        var grown = alloc_mod.sandTryReallocInPlace(self.alloc,
            @ptrCast([*]u8, self.items),
            self.cap * @intCast(usize, @sizeOf(DepEdge)),
            nc * @intCast(usize, @sizeOf(DepEdge)),
            @intCast(usize, 4));
        if (grown != null) {
            self.cap = nc;
            return;
        }
    }
    var raw = alloc_mod.sandAlloc(self.alloc, @intCast(usize, @sizeOf(DepEdge)) * nc, @intCast(usize, 4)) catch unreachable;
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
    var count: usize = @intCast(usize, max_type_id + @intCast(u32, 1));
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

fn populateTypePayload(type_reg: *type_mod.TypeRegistry, store: *AstStore, decl_kind: AstKind, decl_idx: u32, sym_reg: *SymbolRegistry) void {
    var node = store.nodes.items[@intCast(usize, decl_idx)];
    if (node.payload == 0) return;
    var children = ast_mod.astStoreGetExtraChildren(store, node.payload);
    if (children.len == 0) return;

    if (decl_kind == AstKind.struct_decl) {
        var fstart: u32 = @intCast(u32, type_reg.fe_len);
        var fcount: u32 = 0;
        var i: usize = 0;
        while (i < children.len) {
            var fd = store.nodes.items[@intCast(usize, children[i])];
            if (fd.kind == AstKind.field_decl) {
                type_mod.feAppend(type_reg, type_mod.FieldEntry{
                    .name_id = fd.payload,
                    .type_id = type_mod.TYPE_VOID,
                    .offset = @intCast(u32, 0),
                });
                fcount += 1;
            }
            i += 1;
        }
        if (fcount > 0) {
            type_mod.stAppend(type_reg, type_mod.StructPayload{
                .fields_start = @intCast(u32, fstart),
                .fields_count = @intCast(u16, fcount),
            });
        }
        var st_last: usize = type_reg.st_len - @intCast(usize, 1);
        var st_idx: u32 = @intCast(u32, st_last);
        var ty = type_reg.types_items[@intCast(usize, type_reg.types_len - @intCast(usize, 1))];
        ty.payload_idx = st_idx;
        type_reg.types_items[@intCast(usize, type_reg.types_len - @intCast(usize, 1))] = ty;
    }
    if (decl_kind == AstKind.union_decl) {
        var fstart: u32 = @intCast(u32, type_reg.fe_len);
        var fcount: u32 = 0;
        var i: usize = 0;
        while (i < children.len) {
            var fd = store.nodes.items[@intCast(usize, children[i])];
            if (fd.kind == AstKind.field_decl) {
                type_mod.feAppend(type_reg, type_mod.FieldEntry{
                    .name_id = fd.payload,
                    .type_id = type_mod.TYPE_VOID,
                    .offset = @intCast(u32, 0),
                });
                fcount += 1;
            }
            i += 1;
        }
        if ((@intCast(u16, node.flags) & 1) != 0) {
            type_mod.tuAppend(type_reg, type_mod.TaggedUnionPayload{
                .tag_type = type_mod.TYPE_U32,
                .fields_start = @intCast(u32, fstart),
                .fields_count = @intCast(u16, fcount),
            });
            var tu_last: usize = type_reg.tu_len - @intCast(usize, 1);
            var tu_idx: u32 = @intCast(u32, tu_last);
            var ty = type_reg.types_items[@intCast(usize, type_reg.types_len - @intCast(usize, 1))];
            ty.payload_idx = tu_idx;
            type_reg.types_items[@intCast(usize, type_reg.types_len - @intCast(usize, 1))] = ty;
        } else {
            type_mod.unAppend(type_reg, type_mod.UnionPayload{
                .fields_start = @intCast(u32, fstart),
                .fields_count = @intCast(u16, fcount),
                .tag_type = type_mod.TYPE_VOID,
            });
            var un_last: usize = type_reg.un_len - @intCast(usize, 1);
            var un_idx: u32 = @intCast(u32, un_last);
            var ty = type_reg.types_items[@intCast(usize, type_reg.types_len - @intCast(usize, 1))];
            ty.payload_idx = un_idx;
            type_reg.types_items[@intCast(usize, type_reg.types_len - @intCast(usize, 1))] = ty;
        }
    }
    if (decl_kind == AstKind.enum_decl) {
        var tre_env = type_resolver.TypeResolveEnv{ .store = store, .typereg = type_reg, .symbol_reg = sym_reg, .interner = type_reg.interner, .module_id = type_resolver.MODULE_ID_NONE };
        var backing_box: [1]u32 = [1]u32{ @intCast(u32, 0) };
        backing_box[0] = type_mod.TYPE_U32;
        if (node.child_0 != 0) {
            var bt = type_resolver.resolveTypeExprFull(&tre_env, node.child_0, @intCast(u32, 0));
            if (bt != type_mod.TYPE_UNDEFINED and bt != type_mod.TYPE_VOID) { backing_box[0] = bt; }
        }
        var mstart: u32 = @intCast(u32, type_reg.em_len);
        var mcount: u32 = 0;
        var auto_val: u32 = @intCast(u32, 0);
        var i: usize = 0;
        while (i < children.len) {
            var mnode = store.nodes.items[@intCast(usize, children[i])];
            if (mnode.kind == AstKind.field_decl) {
                var mval: u32 = auto_val;
                if (mnode.child_1 != 0) {
                    var ev = type_resolver.evalConstU32Full(&tre_env, mnode.child_1);
                    if (ev != @intCast(u32, 0xFFFFFFFF)) { mval = ev; }
                }
                type_mod.emAppend(type_reg, type_mod.EnumMember{ .name_id = mnode.payload, .value = @intCast(i64, mval) });
                mcount += 1;
                auto_val = mval + @intCast(u32, 1);
            }
            i += 1;
        }
        type_mod.enAppend(type_reg, type_mod.EnumPayload{
            .members_start = @intCast(u32, mstart),
            .members_count = @intCast(u16, mcount),
            .backing_type = backing_box[0],
        });
        var en_last: usize = type_reg.en_len - @intCast(usize, 1);
        var en_idx: u32 = @intCast(u32, en_last);
        var ty = type_reg.types_items[@intCast(usize, type_reg.types_len - @intCast(usize, 1))];
        ty.payload_idx = en_idx;
        type_reg.types_items[@intCast(usize, type_reg.types_len - @intCast(usize, 1))] = ty;
    }
    if (decl_kind == AstKind.error_set_decl) {
        var tags_start_idx: u32 = @intCast(u32, type_reg.xn_len);
        var i: usize = 0;
        while (i < children.len) : (i += 1) {
            type_mod.xnAppend(type_reg, children[i]);
        }
        type_mod.esAppend(type_reg, type_mod.ErrorSetPayload{
            .tags_start = tags_start_idx,
            .tags_count = @intCast(u16, children.len),
        });
        var es_last: usize = type_reg.es_len - @intCast(usize, 1);
        var es_idx: u32 = @intCast(u32, es_last);
        var ty = type_reg.types_items[@intCast(usize, type_reg.types_len - @intCast(usize, 1))];
        ty.payload_idx = es_idx;
        type_reg.types_items[@intCast(usize, type_reg.types_len - @intCast(usize, 1))] = ty;
    }
}

fn registerDecl(sym_reg: *SymbolRegistry, type_reg: *type_mod.TypeRegistry, store: *AstStore, mod_id: u32, decl_idx: u32, g: *DepGraph, reg: *mr_mod.ModuleRegistry, populate: bool) void {
    var node = store.nodes.items[decl_idx];
    switch (node.kind) {
         AstKind.var_decl => {
             var ra_msg: []const u8 = "Ra"; pal_mod.markerWrite(ra_msg);
             var name_id = node.payload;
             var d12m: []const u8 = "D12:n"; pal_mod.markerWrite(d12m);
             var d12b: [20]u8 = undefined; var d12l = itoa_mod.itoa(name_id, d12b[0..]); var d12s: usize = @intCast(usize, 19) - @intCast(usize, d12l); pal_mod.markerWrite(d12b[d12s..@intCast(usize, 19)]);
             var d12nl: []const u8 = "\n"; pal_mod.markerWrite(d12nl);
            var sym_kind = sym_mod.SymbolKind.global;
            var sym_mod_id = mod_id;
            var sym_type_id: u32 = @intCast(u32, 0);
            if (node.child_1 != 0) {
                var init_node = store.nodes.items[@intCast(usize, node.child_1)];
                if (init_node.kind == AstKind.import_expr) {
                    var target = hash_mod.u32ToU32MapGet(&reg.path_to_id, init_node.payload);
                    var m5m: []const u8 = "M5:p"; pal_mod.markerWrite(m5m);
                    var m5pb: [20]u8 = undefined; var m5pl = itoa_mod.itoa(init_node.payload, m5pb[0..]); var m5ps: usize = @intCast(usize, 19) - @intCast(usize, m5pl); pal_mod.markerWrite(m5pb[m5ps..@intCast(usize, 19)]);
                    if (target) |mtid| {
                        var rs_msg: []const u8 = "Rs"; pal_mod.markerWrite(rs_msg);
                        sym_kind = sym_mod.SymbolKind.module;
                        sym_mod_id = mtid;
                        var di_m: []const u8 = "FIX1:mid="; pal_mod.markerWrite(di_m);
                        var di_mb: [10]u8 = undefined; var di_ml = itoa_mod.itoa(sym_mod_id, di_mb[0..]); var di_ms: usize = @intCast(usize, 9) - @intCast(usize, di_ml); pal_mod.markerWrite(di_mb[di_ms..@intCast(usize, 9)]);
                        var di_t: []const u8 = "t"; pal_mod.markerWrite(di_t);
                        var di_tb: [10]u8 = undefined; var di_tl = itoa_mod.itoa(mtid, di_tb[0..]); var di_ts: usize = @intCast(usize, 9) - @intCast(usize, di_tl); pal_mod.markerWrite(di_tb[di_ts..@intCast(usize, 9)]);
                        var di_n: []const u8 = "n"; pal_mod.markerWrite(di_n);
                        var di_nb: [10]u8 = undefined; var di_nl = itoa_mod.itoa(mod_id, di_nb[0..]); var di_ns: usize = @intCast(usize, 9) - @intCast(usize, di_nl);                         pal_mod.markerWrite(di_nb[di_ns..@intCast(usize, 9)]);
                        sym_type_id = type_mod.typeRegistryGetOrCreateModule(type_reg, mtid);
                    } else {
                        var rf_msg: []const u8 = "Rf"; pal_mod.markerWrite(rf_msg);
                    }
                }
                if (init_node.kind == AstKind.struct_decl or init_node.kind == AstKind.enum_decl or init_node.kind == AstKind.union_decl or init_node.kind == AstKind.error_set_decl) {
                    var type_kind: TypeKind = switch (init_node.kind) {
                        AstKind.struct_decl => TypeKind.struct_type,
                        AstKind.enum_decl => TypeKind.enum_type,
                        AstKind.union_decl => if ((@intCast(u16, init_node.flags) & 1) != 0) TypeKind.tagged_union_type else TypeKind.union_type,
                        AstKind.error_set_decl => TypeKind.error_set_type,
                        else => TypeKind.void_type,
                    };
                    sym_type_id = type_mod.typeRegistryRegisterNamedType(type_reg, mod_id, name_id, type_kind);
                    if (populate) { populateTypePayload(type_reg, store, init_node.kind, node.child_1, sym_reg); }
                    addTypeDependencies(store, node.child_1, sym_type_id, g);
                    sym_kind = sym_mod.SymbolKind.type_alias;
                    sym_mod_id = mod_id;
                } else if (init_node.kind == AstKind.ident_expr) {
                    var rca_m: []const u8 = "RCA:p"; pal_mod.markerWriteInt(rca_m, init_node.payload);
                    var ident_name_id = store.identifiers.items[@intCast(usize, init_node.payload)];
                    var rca_i: []const u8 = "RCA:i"; pal_mod.markerWriteInt(rca_i, ident_name_id);
                    var cached = type_mod.nameCacheGet(type_reg, @intCast(u64, mod_id) * @intCast(u64, 4294967296) + @intCast(u64, ident_name_id));
                    if (cached == null) { cached = type_mod.nameCacheGet(type_reg, @intCast(u64, ident_name_id)); }
                    if (cached) |ct| {
                        var rca_h: []const u8 = "RCA:H"; pal_mod.markerWriteInt(rca_h, ct);
                        var ck: u64 = @intCast(u64, mod_id) * @intCast(u64, 4294967296) + @intCast(u64, name_id);
                        type_mod.nameCachePut(type_reg, ck, ct);
                        sym_type_id = ct;
                        sym_kind = sym_mod.SymbolKind.type_alias;
                        sym_mod_id = mod_id;
                    }
                } else if (init_node.kind == AstKind.array_type or init_node.kind == AstKind.slice_type or init_node.kind == AstKind.many_ptr_type) {
                    var at_m: []const u8 = "AT:p"; pal_mod.markerWriteInt(at_m, name_id);
                    var acached = type_mod.nameCacheGet(type_reg, @intCast(u64, mod_id) * @intCast(u64, 4294967296) + @intCast(u64, name_id));
                    if (acached == null) { acached = type_mod.nameCacheGet(type_reg, @intCast(u64, name_id)); }
                    if (acached) |act| {
                        sym_type_id = act;
                    }
                    sym_kind = sym_mod.SymbolKind.type_alias;
                    sym_mod_id = mod_id;
                }
            }

            var sym = sym_mod.Symbol{
                .name_id = name_id,
                .type_id = sym_type_id,
                .kind = sym_kind,
                .flags = @intCast(u16, node.flags),
                .decl_node = decl_idx,
                .module_id = sym_mod_id,
                .scope_level = @intCast(u32, 0),
            };
            var table = sym_mod.symbolRegistryGetTable(sym_reg, mod_id);
            var inserted = sym_mod.symbolTableInsert(table, sym);
            if (!inserted) {
                var vr: []const u8 = "VR";
                pal_mod.markerWrite(vr);
            }
            var vd: []const u8 = "VD";
            pal_mod.markerWrite(vd);
            var vb: [20]u8 = undefined;
            var vn = itoa_mod.itoa(name_id, vb[0..]);
            var vns: usize = @intCast(usize, 20) - @intCast(usize, 1) - @intCast(usize, vn);
            pal_mod.markerWrite(vb[vns..@intCast(usize, 20)]);
            var vc: []const u8 = ":";
            pal_mod.markerWrite(vc);
            var vk = itoa_mod.itoa(@intCast(u32, @enumToInt(sym_kind)), vb[0..]);
            var vks: usize = @intCast(usize, 20) - @intCast(usize, 1) - @intCast(usize, vk);
            pal_mod.markerWrite(vb[vks..@intCast(usize, 20)]);
            var ven: []const u8 = "\n";
            pal_mod.markerWrite(ven);
            var vi_msg: []const u8 = "Vi"; pal_mod.markerWrite(vi_msg);
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
            if (populate) { populateTypePayload(type_reg, store, node.kind, decl_idx, sym_reg); }
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
            if (populate) { populateTypePayload(type_reg, store, node.kind, decl_idx, sym_reg); }
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
                    .type_id = type_mod.typeRegistryGetOrCreateModule(type_reg, tid),
                    .kind = sym_mod.SymbolKind.module,
                     .flags = @intCast(u16, 0),
                     .decl_node = decl_idx,
                     .module_id = tid,
                     .scope_level = @intCast(u32, 0),
                 };
                 var table = sym_mod.symbolRegistryGetTable(sym_reg, mod_id);
                 _ = sym_mod.symbolTableInsert(table, sym);
                 var imr: []const u8 = "IMR:n"; pal.markerWrite(imr);
                 var imb: [10]u8 = undefined; var iml = itoa_mod.itoa(path_id, imb[0..]); var ims: usize = @intCast(usize, 9) - @intCast(usize, iml); pal.markerWrite(imb[ims..@intCast(usize, 9)]);
                 var imm: []const u8 = "m"; pal.markerWrite(imm);
                 var immb: [10]u8 = undefined; var imml = itoa_mod.itoa(tid, immb[0..]); var imms: usize = @intCast(usize, 9) - @intCast(usize, imml); pal.markerWrite(immb[imms..@intCast(usize, 9)]);
                 var imsnl: []const u8 = " "; pal.markerWrite(imsnl);
             }
         },
        else => {},
    }
}

pub fn registerModuleSymbols(reg: *mr_mod.ModuleRegistry, sym_reg: *SymbolRegistry, type_reg: *type_mod.TypeRegistry, store: *AstStore, module_id: u32, g: *DepGraph, populate: bool) void {
    var entry = reg.modules.items[@intCast(usize, module_id)];
    if ((entry.state != mr_mod.ModuleState.parsed and entry.state != mr_mod.ModuleState.resolved) or entry.ast_root == 0) return;
    var root = store.nodes.items[@intCast(usize, entry.ast_root)];
    if (root.kind != AstKind.module_root) return;
    var decls = ast_mod.astStoreGetExtraChildren(store, root.payload);
    if (module_id == @intCast(u32, 0)) {
        var dg: []const u8 = "RS"; pal_mod.markerWrite(dg);
        var pb: [20]u8 = undefined;
        var pl = itoa_mod.itoa(root.payload, pb[0..]);
        var ps: usize = @intCast(usize, 19) - @intCast(usize, pl);
        pal_mod.markerWrite(pb[ps..@intCast(usize, 19)]);
        var sc: []const u8 = ":"; pal_mod.markerWrite(sc);
        var i2: usize = 0;
        while (i2 < decls.len) : (i2 += 1) {
            var ii_buf: [20]u8 = undefined;
            var ii_len = itoa_mod.itoa(decls[i2], ii_buf[0..]);
            var ii_start: usize = @intCast(usize, 19) - @intCast(usize, ii_len);
            pal_mod.markerWrite(ii_buf[ii_start..@intCast(usize, 19)]);
            var ss: []const u8 = "="; pal_mod.markerWrite(ss);
            var dc = store.nodes.items[@intCast(usize, decls[i2])];
            var dk: u32 = @intCast(u32, @enumToInt(dc.kind));
            var db: [20]u8 = undefined;
            var dl = itoa_mod.itoa(dk, db[0..]);
            var ds: usize = @intCast(usize, 19) - @intCast(usize, dl);
            pal_mod.markerWrite(db[ds..@intCast(usize, 19)]);
            var dsp: []const u8 = " "; pal_mod.markerWrite(dsp);
        }
        var dn: []const u8 = "\n"; pal_mod.markerWrite(dn);
    }
    var i: usize = 0;
    while (i < decls.len) {
        registerDecl(sym_reg, type_reg, store, module_id, decls[i], g, reg, populate);
        i += 1;
    }
}
