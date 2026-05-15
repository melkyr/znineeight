const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeKind = @import("type_registry.zig").TypeKind;
const TypeId = @import("type_registry.zig").TypeId;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const diag_mod = @import("diagnostics.zig");
const sym_reg = @import("symbol_registrator.zig");
const DepEdge = sym_reg.DepEdge;
const AstStore = @import("ast.zig").AstStore;
const AstKind = @import("ast.zig").AstKind;
const type_mod = @import("type_registry.zig");

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

fn alignUp(v: u32, a: u32) u32 {
    return (v + a - @intCast(u32, 1)) & ~(a - @intCast(u32, 1));
}

fn typeResolverResolveLayout(self: *TypeResolver, tid: u32) void {
    var idx = @intCast(usize, tid);
    var ty = self.registry.types_items[idx];
    if (ty.kind == TypeKind.struct_type) {
        var sp = self.registry.st_items[@intCast(usize, ty.payload_idx)];
        var fstart: usize = @intCast(usize, sp.fields_start);
        var fcount: usize = @intCast(usize, sp.fields_count);
        var offset: u32 = 0;
        var max_align: u32 = 1;
        var fi: usize = 0;
        while (fi < fcount) : (fi += 1) {
            var fe = self.registry.fe_items[fstart + fi];
            var ft = self.registry.types_items[@intCast(usize, fe.type_id)];
            if (ft.kind == TypeKind.void_type) {
                fe.offset = offset;
                self.registry.fe_items[fstart + fi] = fe;
                continue;
            }
            offset = alignUp(offset, ft.alignment);
            fe.offset = offset;
            self.registry.fe_items[fstart + fi] = fe;
            offset += ft.size;
            if (ft.alignment > max_align) max_align = ft.alignment;
        }
        ty.size = alignUp(offset, max_align);
        ty.alignment = max_align;
        if (ty.size == @intCast(u32, 0)) { ty.size = @intCast(u32, 1); ty.alignment = @intCast(u32, 1); }
        self.registry.types_items[idx] = ty;
    } else if (ty.kind == TypeKind.enum_type) {
        var ep = self.registry.en_items[@intCast(usize, ty.payload_idx)];
        var bt = self.registry.types_items[@intCast(usize, ep.backing_type)];
        ty.size = bt.size;
        ty.alignment = bt.alignment;
        self.registry.types_items[idx] = ty;
    } else if (ty.kind == TypeKind.union_type) {
        var up = self.registry.un_items[@intCast(usize, ty.payload_idx)];
        var fstart: usize = @intCast(usize, up.fields_start);
        var fcount: usize = @intCast(usize, up.fields_count);
        var max_sz: u32 = 0;
        var max_align: u32 = 1;
        var fi: usize = 0;
        while (fi < fcount) : (fi += 1) {
            var fe = self.registry.fe_items[fstart + fi];
            var ft = self.registry.types_items[@intCast(usize, fe.type_id)];
            if (ft.kind == TypeKind.void_type) continue;
            if (ft.size > max_sz) max_sz = ft.size;
            if (ft.alignment > max_align) max_align = ft.alignment;
        }
        ty.size = alignUp(max_sz, max_align);
        ty.alignment = max_align;
        self.registry.types_items[idx] = ty;
    } else if (ty.kind == TypeKind.tagged_union_type) {
        var tp = self.registry.tu_items[@intCast(usize, ty.payload_idx)];
        var tag_ty = self.registry.types_items[@intCast(usize, tp.tag_type)];
        var fstart: usize = @intCast(usize, tp.fields_start);
        var fcount: usize = @intCast(usize, tp.fields_count);
        var max_ps: u32 = 0;
        var max_pa: u32 = 1;
        var fi: usize = 0;
        while (fi < fcount) : (fi += 1) {
            var fe = self.registry.fe_items[fstart + fi];
            var ft = self.registry.types_items[@intCast(usize, fe.type_id)];
            if (ft.kind == TypeKind.void_type) continue;
            if (ft.size > max_ps) max_ps = ft.size;
            if (ft.alignment > max_pa) max_pa = ft.alignment;
        }
        var overall_align = if (tag_ty.alignment > max_pa) tag_ty.alignment else max_pa;
        var total = tag_ty.size;
        total = alignUp(total, max_pa);
        total += alignUp(max_ps, max_pa);
        ty.size = alignUp(total, overall_align);
        ty.alignment = overall_align;
        self.registry.types_items[idx] = ty;
    } else if (ty.kind == TypeKind.optional_type) {
        var op = self.registry.opt_items[@intCast(usize, ty.payload_idx)];
        var pt = self.registry.types_items[@intCast(usize, op.payload)];
        var pay_align = if (pt.alignment > @intCast(u32, 4)) pt.alignment else @intCast(u32, 4);
        ty.size = alignUp(alignUp(pt.size, @intCast(u32, 4)) + @intCast(u32, 4), pay_align);
        ty.alignment = pay_align;
        self.registry.types_items[idx] = ty;
    } else if (ty.kind == TypeKind.error_union_type) {
        var ep = self.registry.eu_items[@intCast(usize, ty.payload_idx)];
        var pt = self.registry.types_items[@intCast(usize, ep.payload)];
        var union_sz = if (pt.size > @intCast(u32, 4)) pt.size else @intCast(u32, 4);
        var union_align = if (pt.alignment > @intCast(u32, 4)) pt.alignment else @intCast(u32, 4);
        var total = alignUp(union_sz, union_align);
        total = alignUp(total, @intCast(u32, 4)) + @intCast(u32, 4);
        ty.size = alignUp(total, union_align);
        ty.alignment = union_align;
        self.registry.types_items[idx] = ty;
    } else if (ty.kind == TypeKind.array_type) {
        var ap = self.registry.array_items[@intCast(usize, ty.payload_idx)];
        var et = self.registry.types_items[@intCast(usize, ap.elem)];
        ty.size = et.size * ap.length;
        ty.alignment = et.alignment;
        self.registry.types_items[idx] = ty;
    } else if (ty.kind == TypeKind.tuple_type) {
        var tp = self.registry.tup_items[@intCast(usize, ty.payload_idx)];
        var estr: usize = @intCast(usize, tp.elems_start);
        var ecount: usize = @intCast(usize, tp.elems_count);
        var offset: u32 = 0;
        var max_align: u32 = 1;
        var ei: usize = 0;
        while (ei < ecount) : (ei += 1) {
            var elem_tid = self.registry.xt_items[estr + ei];
            var et = self.registry.types_items[@intCast(usize, elem_tid)];
            offset = alignUp(offset, et.alignment);
            offset += et.size;
            if (et.alignment > max_align) max_align = et.alignment;
        }
        ty.size = alignUp(offset, max_align);
        ty.alignment = max_align;
        if (ty.size == @intCast(u32, 0)) { ty.size = @intCast(u32, 1); ty.alignment = @intCast(u32, 1); }
        self.registry.types_items[idx] = ty;
    }
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
            typeResolverResolveLayout(self, tid);
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
    while (ci < type_count) : (ci += 1) {
        var ty = self.registry.types_items[ci];
        if (ty.state != @intCast(u8, 2) and self.in_degree_items[ci] > 0) {
            var msg: []const u8 = "circular type dependency (infinite size)";
            diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0),
                @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3005_CIRCULAR_TYPE_DEPENDENCY)), ty.module_id,
                @intCast(u32, 0), @intCast(u32, 0), msg);
            ty.kind = TypeKind.void_type;
            ty.size = @intCast(u32, 0);
            ty.alignment = @intCast(u32, 1);
            ty.state = @intCast(u8, 2);
            self.registry.types_items[ci] = ty;
        }
    }
}

pub fn typeResolverResolveTypeExpr(self: *TypeResolver, store: *AstStore, depth: u32, node_idx: u32, module_id: u32) u32 {
    if (node_idx == @intCast(u32, 0)) return @intCast(u32, 0);
    if (depth > @intCast(u32, 12)) return @intCast(u32, 0);

    var idx = @intCast(usize, node_idx);
    var node = store.nodes.items[idx];
    var kind = node.kind;
    var is_const: u8 = 0;
    if ((node.flags & @intCast(u8, 1)) != @intCast(u8, 0)) is_const = @intCast(u8, 1);
    var ic_bool = is_const != @intCast(u8, 0);

    if (kind == AstKind.ident_expr) {
        var name_id = store.identifiers.items[@intCast(usize, node.payload)];
        var key: u64 = @intCast(u64, module_id) * @intCast(u64, 4294967296) + @intCast(u64, name_id);
        var existing: ?u32 = type_mod.nameCacheGet(self.registry, key);
        if (existing) |tid| return tid;
        return type_mod.typeRegistryRegisterNamedType(self.registry, module_id, name_id, TypeKind.unresolved_name);
    }

    if (kind == AstKind.ptr_type) {
        var base = typeResolverResolveTypeExpr(self, store, depth + @intCast(u32, 1), node.child_0, module_id);
        if (base == @intCast(u32, 0)) return @intCast(u32, 0);
        return type_mod.typeRegistryGetOrCreatePtr(self.registry, base, ic_bool);
    }

    if (kind == AstKind.many_ptr_type) {
        var base = typeResolverResolveTypeExpr(self, store, depth + @intCast(u32, 1), node.child_0, module_id);
        if (base == @intCast(u32, 0)) return @intCast(u32, 0);
        return type_mod.typeRegistryGetOrCreateManyPtr(self.registry, base, ic_bool);
    }

    if (kind == AstKind.slice_type) {
        var base = typeResolverResolveTypeExpr(self, store, depth + @intCast(u32, 1), node.child_0, module_id);
        if (base == @intCast(u32, 0)) return @intCast(u32, 0);
        return type_mod.typeRegistryGetOrCreateSlice(self.registry, base, ic_bool);
    }

    if (kind == AstKind.optional_type) {
        var pay = typeResolverResolveTypeExpr(self, store, depth + @intCast(u32, 1), node.child_0, module_id);
        if (pay == @intCast(u32, 0)) return @intCast(u32, 0);
        return type_mod.typeRegistryGetOrCreateOptional(self.registry, pay);
    }

    if (kind == AstKind.error_union_type) {
        var pay = typeResolverResolveTypeExpr(self, store, depth + @intCast(u32, 1), node.child_0, module_id);
        if (pay == @intCast(u32, 0)) return @intCast(u32, 0);
        var es = typeResolverResolveTypeExpr(self, store, depth + @intCast(u32, 1), node.child_1, module_id);
        return type_mod.typeRegistryGetOrCreateErrorUnion(self.registry, pay, es);
    }

    if (kind == AstKind.array_type) {
        var elem = typeResolverResolveTypeExpr(self, store, depth + @intCast(u32, 1), node.child_0, module_id);
        if (elem == @intCast(u32, 0)) return @intCast(u32, 0);
        var arr_len: u32 = 0;
        if (node.child_1 != @intCast(u32, 0)) {
            var sz_idx = @intCast(usize, node.child_1);
            var sz_node = store.nodes.items[sz_idx];
            if (sz_node.kind == AstKind.int_literal) {
                arr_len = @intCast(u32, store.int_values.items[@intCast(usize, sz_node.payload)]);
            }
        }
        if (arr_len == @intCast(u32, 0)) return @intCast(u32, 0);
        return type_mod.typeRegistryGetOrCreateArray(self.registry, elem, arr_len);
    }

    if (kind == AstKind.error_set_decl) return @intCast(u32, 1);
    if (kind == AstKind.struct_decl) return @intCast(u32, 1);
    if (kind == AstKind.enum_decl) return @intCast(u32, 1);
    if (kind == AstKind.union_decl) return @intCast(u32, 1);

    return @intCast(u32, 0);
}
