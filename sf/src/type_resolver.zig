const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const pal_mod = @import("pal.zig");
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
const itoa_mod = @import("util/itoa.zig");
const interner_mod = @import("string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const sym_mod = @import("symbol_table.zig");
const SymbolRegistry = sym_mod.SymbolRegistry;
const ast_mod = @import("ast.zig");

pub const TypeResolveEnv = struct {
    store: *AstStore,
    typereg: *TypeRegistry,
    symbol_reg: *SymbolRegistry,
    interner: *StringInterner,
};

pub const ClassificationResult = struct {
    ids: [*]u32,
    len: u32,
};

pub const TypeResolver = struct {
    registry: *TypeRegistry,
    depend_items: [*]DepEdge,
    depend_len: usize,
    depend_cap: usize,
    in_degree_items: [*]u32,
    in_degree_cap: usize,
    sorted_items: [*]u32,
    sorted_len: usize,
    worklist_items: [*]u32,
    worklist_len: usize,
    worklist_cap: usize,
    diag: *DiagnosticCollector,
    alloc: *Sand,
};

fn dependEnsureCapacity(self: *TypeResolver) void {
    if (self.depend_len < self.depend_cap) return;
    var nc: usize = if (self.depend_cap < 8) @intCast(usize, 8) else self.depend_cap * 2;
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
    var nc: usize = if (self.worklist_cap < 64) @intCast(usize, 64) else self.worklist_cap * 2;
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
            } else {
                offset = alignUp(offset, ft.alignment);
                fe.offset = offset;
                self.registry.fe_items[fstart + fi] = fe;
                offset += ft.size;
                if (ft.alignment > max_align) max_align = ft.alignment;
            }
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
            if (ft.kind != TypeKind.void_type) {
                if (ft.size > max_sz) max_sz = ft.size;
                if (ft.alignment > max_align) max_align = ft.alignment;
            }
        }
        ty.size = alignUp(max_sz, max_align);
        ty.alignment = max_align;
        if (ty.size == @intCast(u32, 0)) { ty.size = @intCast(u32, 1); ty.alignment = @intCast(u32, 1); }
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
             var fer_nm: []const u8 = "FER:n"; pal_mod.markerWriteInt(fer_nm, @intCast(u32, fstart + fi));
             var fer_tm: []const u8 = "FER:t"; pal_mod.markerWriteInt(fer_tm, fe.type_id);
            var ft = self.registry.types_items[@intCast(usize, fe.type_id)];
            if (ft.kind != TypeKind.void_type) {
                if (ft.size > max_ps) max_ps = ft.size;
                if (ft.alignment > max_pa) max_pa = ft.alignment;
            }
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
        .sorted_items = undefined,
        .sorted_len = @intCast(usize, 0),
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
    var raw_sorted = alloc_mod.sandAlloc(self.alloc, type_count * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable;
    self.sorted_items = @ptrCast([*]u32, raw_sorted);
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
            self.sorted_items[self.sorted_len] = tid;
            self.sorted_len += @intCast(usize, 1);
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
            var msg: []const u8 = "circular type dependency detected (type refers to itself)";
            diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0),
                @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3005_CIRCULAR_TYPE_DEPENDENCY)), @intCast(u32, 0),
                @intCast(u32, 0), @intCast(u32, 0), msg);
            ty.kind = TypeKind.void_type;
            ty.size = @intCast(u32, 0);
            ty.alignment = @intCast(u32, 1);
            ty.state = @intCast(u8, 2);
            self.registry.types_items[ci] = ty;
        }
    }
}

fn fieldEmbedsByValue(kind: TypeKind) bool {
    if (kind == TypeKind.struct_type) return true;
    if (kind == TypeKind.tagged_union_type) return true;
    if (kind == TypeKind.union_type) return true;
    if (kind == TypeKind.array_type) return true;
    if (kind == TypeKind.tuple_type) return true;
    return false;
}

pub fn classifyTypeEmissionGroups(self: *TypeResolver, perm_alloc: *Sand) ClassificationResult {
    var tl: usize = self.registry.types_len;

    var po_raw = alloc_mod.sandAlloc(perm_alloc, 1 * tl, 1) catch unreachable;
    var pointer_only: [*]u8 = @ptrCast([*]u8, po_raw);

    var wp_edge_cap: usize = tl * 4;
    var wp_to_raw = alloc_mod.sandAlloc(perm_alloc, 4 * wp_edge_cap, 4) catch unreachable;
    var wp_to: [*]u32 = @ptrCast([*]u32, wp_to_raw);
    var wp_next_raw = alloc_mod.sandAlloc(perm_alloc, 4 * wp_edge_cap, 4) catch unreachable;
    var wp_next: [*]u32 = @ptrCast([*]u32, wp_next_raw);
    var wp_head_raw = alloc_mod.sandAlloc(perm_alloc, 4 * tl, 4) catch unreachable;
    var wp_head: [*]u32 = @ptrCast([*]u32, wp_head_raw);
    var whi: usize = 0;
    while (whi < tl) : (whi += 1) { wp_head[whi] = @intCast(u32, 4294967295); }
    var wp_count: u32 = @intCast(u32, 0);

    var wl_raw = alloc_mod.sandAlloc(perm_alloc, 4 * tl, 4) catch unreachable;
    var worklist: [*]u32 = @ptrCast([*]u32, wl_raw);
    var wl_head: u32 = @intCast(u32, 0);
    var wl_tail: u32 = @intCast(u32, 0);

    var ti: usize = 0;
    while (ti < tl) : (ti += 1) {
        var ty = self.registry.types_items[ti];
        var is_po: u8 = @intCast(u8, 1);

        if (ty.kind == TypeKind.struct_type) {
            var sp = self.registry.st_items[@intCast(usize, ty.payload_idx)];
            var fi: usize = 0;
            while (fi < @intCast(usize, sp.fields_count) and is_po != 0) : (fi += 1) {
                var ft_id = self.registry.fe_items[@intCast(usize, sp.fields_start) + fi].type_id;
                var ft = self.registry.types_items[@intCast(usize, ft_id)];
                if (fieldEmbedsByValue(ft.kind)) {
                    is_po = @intCast(u8, 0);
                } else if (ft.kind == TypeKind.optional_type) {
                    var payload = self.registry.opt_items[@intCast(usize, ft.payload_idx)].payload;
                    growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                    wp_head[@intCast(usize, payload)] = wp_count;
                    wp_count += @intCast(u32, 1);
                } else if (ft.kind == TypeKind.error_union_type) {
                    var payload = self.registry.eu_items[@intCast(usize, ft.payload_idx)].payload;
                    growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                    wp_head[@intCast(usize, payload)] = wp_count;
                    wp_count += @intCast(u32, 1);
                }
            }
        } else if (ty.kind == TypeKind.tagged_union_type) {
            var tp = self.registry.tu_items[@intCast(usize, ty.payload_idx)];
            var fi: usize = 0;
            while (fi < @intCast(usize, tp.fields_count) and is_po != 0) : (fi += 1) {
                var ft_id = self.registry.fe_items[@intCast(usize, tp.fields_start) + fi].type_id;
                var ft = self.registry.types_items[@intCast(usize, ft_id)];
                if (fieldEmbedsByValue(ft.kind)) {
                    is_po = @intCast(u8, 0);
                } else if (ft.kind == TypeKind.optional_type) {
                    var payload = self.registry.opt_items[@intCast(usize, ft.payload_idx)].payload;
                    growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                    wp_head[@intCast(usize, payload)] = wp_count;
                    wp_count += @intCast(u32, 1);
                } else if (ft.kind == TypeKind.error_union_type) {
                    var payload = self.registry.eu_items[@intCast(usize, ft.payload_idx)].payload;
                    growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                    wp_head[@intCast(usize, payload)] = wp_count;
                    wp_count += @intCast(u32, 1);
                }
            }
        } else if (ty.kind == TypeKind.union_type) {
            var up = self.registry.un_items[@intCast(usize, ty.payload_idx)];
            var fi: usize = 0;
            while (fi < @intCast(usize, up.fields_count) and is_po != 0) : (fi += 1) {
                var ft_id = self.registry.fe_items[@intCast(usize, up.fields_start) + fi].type_id;
                var ft = self.registry.types_items[@intCast(usize, ft_id)];
                if (fieldEmbedsByValue(ft.kind)) {
                    is_po = @intCast(u8, 0);
                } else if (ft.kind == TypeKind.optional_type) {
                    var payload = self.registry.opt_items[@intCast(usize, ft.payload_idx)].payload;
                    growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                    wp_head[@intCast(usize, payload)] = wp_count;
                    wp_count += @intCast(u32, 1);
                } else if (ft.kind == TypeKind.error_union_type) {
                    var payload = self.registry.eu_items[@intCast(usize, ft.payload_idx)].payload;
                    growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                    wp_head[@intCast(usize, payload)] = wp_count;
                    wp_count += @intCast(u32, 1);
                }
            }
        } else if (ty.kind == TypeKind.array_type) {
            var et = self.registry.array_items[@intCast(usize, ty.payload_idx)].elem;
            var et_ty = self.registry.types_items[@intCast(usize, et)];
            if (fieldEmbedsByValue(et_ty.kind)) {
                is_po = @intCast(u8, 0);
            } else if (et_ty.kind == TypeKind.optional_type) {
                var payload = self.registry.opt_items[@intCast(usize, et_ty.payload_idx)].payload;
                growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                wp_head[@intCast(usize, payload)] = wp_count;
                wp_count += @intCast(u32, 1);
            } else if (et_ty.kind == TypeKind.error_union_type) {
                var payload = self.registry.eu_items[@intCast(usize, et_ty.payload_idx)].payload;
                growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                wp_head[@intCast(usize, payload)] = wp_count;
                wp_count += @intCast(u32, 1);
            }
        } else if (ty.kind == TypeKind.error_union_type) {
            var eup = self.registry.eu_items[@intCast(usize, ty.payload_idx)].payload;
            var eup_ty = self.registry.types_items[@intCast(usize, eup)];
            if (fieldEmbedsByValue(eup_ty.kind)) {
                is_po = @intCast(u8, 0);
            } else if (eup_ty.kind == TypeKind.optional_type) {
                var payload = self.registry.opt_items[@intCast(usize, eup_ty.payload_idx)].payload;
                growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                wp_head[@intCast(usize, payload)] = wp_count;
                wp_count += @intCast(u32, 1);
            } else if (eup_ty.kind == TypeKind.error_union_type) {
                var payload = self.registry.eu_items[@intCast(usize, eup_ty.payload_idx)].payload;
                growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                wp_head[@intCast(usize, payload)] = wp_count;
                wp_count += @intCast(u32, 1);
            }
        }

        pointer_only[ti] = is_po;
        if (is_po == @intCast(u8, 0)) {
            worklist[@intCast(usize, wl_tail)] = @intCast(u32, ti);
            wl_tail += @intCast(u32, 1);
        }
    }

    while (wl_head < wl_tail) {
        var cur = worklist[@intCast(usize, wl_head)];
        wl_head += @intCast(u32, 1);
        var e: u32 = wp_head[@intCast(usize, cur)];
        while (e != @intCast(u32, 4294967295)) {
            var parent_tid = wp_to[@intCast(usize, e)];
            if (pointer_only[@intCast(usize, parent_tid)] != @intCast(u8, 0)) {
                pointer_only[@intCast(usize, parent_tid)] = @intCast(u8, 0);
                worklist[@intCast(usize, wl_tail)] = parent_tid;
                wl_tail += @intCast(u32, 1);
            }
            e = wp_next[@intCast(usize, e)];
        }
    }

    var ids_raw = alloc_mod.sandAlloc(perm_alloc, 4 * tl, 4) catch unreachable;
    var ids: [*]u32 = @ptrCast([*]u32, ids_raw);
    var plen: u32 = @intCast(u32, 0);
    ti = 0;
    while (ti < tl) : (ti += 1) {
        if (pointer_only[ti] != @intCast(u8, 0)) {
            ids[@intCast(usize, plen)] = @intCast(u32, ti);
            plen += @intCast(u32, 1);
        }
    }

    var cls_m: []const u8 = "CLS:c"; pal_mod.markerWrite(cls_m);
    var cls_b: [10]u8 = undefined;
    var cls_l = itoa_mod.itoa(plen, cls_b[0..]);
    var cls_s: usize = @intCast(usize, 9) - @intCast(usize, cls_l);
    pal_mod.markerWrite(cls_b[cls_s..@intCast(usize, 9)]);
    var cls_nl: []const u8 = "\n"; pal_mod.markerWrite(cls_nl);
    ti = 0;
    while (ti < tl) : (ti += 1) {
        if (pointer_only[ti] != @intCast(u8, 0)) {
            var pfx: []const u8 = "CLS:p"; pal_mod.markerWrite(pfx);
        } else {
            var pfx: []const u8 = "CLS:v"; pal_mod.markerWrite(pfx);
        }
        var ctb: [10]u8 = undefined;
        var ctl = itoa_mod.itoa(@intCast(u32, ti), ctb[0..]);
        var cts: usize = @intCast(usize, 9) - @intCast(usize, ctl);
        pal_mod.markerWrite(ctb[cts..@intCast(usize, 9)]);
        var ck: []const u8 = "k";
        pal_mod.markerWrite(ck);
        var ckb: [10]u8 = undefined;
        var ckl = itoa_mod.itoa(@intCast(u32, @enumToInt(self.registry.types_items[ti].kind)), ckb[0..]);
        var cks: usize = @intCast(usize, 9) - @intCast(usize, ckl);
        pal_mod.markerWrite(ckb[cks..@intCast(usize, 9)]);
        var cnl: []const u8 = "\n"; pal_mod.markerWrite(cnl);
    }

    return ClassificationResult{ .ids = ids, .len = plen };
}

fn growWpEdges(perm_a: *Sand, wp_to_ptr: *[*]u32, wp_next_ptr: *[*]u32, cap_ptr: *usize, count: u32) void {
    if (@intCast(usize, count) < cap_ptr.*) return;
    var old_cap = cap_ptr.*;
    var new_cap: usize = old_cap * 2;
    var new_to_raw = alloc_mod.sandAlloc(perm_a, 4 * new_cap, 4) catch unreachable;
    var new_nx_raw = alloc_mod.sandAlloc(perm_a, 4 * new_cap, 4) catch unreachable;
    var new_to: [*]u32 = @ptrCast([*]u32, new_to_raw);
    var new_nx: [*]u32 = @ptrCast([*]u32, new_nx_raw);
    var ci: usize = 0;
    while (ci < @intCast(usize, count)) : (ci += 1) {
        new_to[ci] = wp_to_ptr.*[ci];
        new_nx[ci] = wp_next_ptr.*[ci];
    }
    wp_to_ptr.* = new_to;
    wp_next_ptr.* = new_nx;
    cap_ptr.* = new_cap;
}

pub fn typeResolverGetSorted(self: *TypeResolver) []u32 {
    return self.sorted_items[0..self.sorted_len];
}

pub fn evalConstU32Full(env: *TypeResolveEnv, node_idx: u32) u32 {
    if (node_idx == @intCast(u32, 0)) return @intCast(u32, 0xFFFFFFFF);
    var node = env.store.nodes.items[@intCast(usize, node_idx)];
    if (node.kind == AstKind.int_literal) {
        return @intCast(u32, env.store.int_values.items[@intCast(usize, node.payload)]);
    }
    if (node.kind == AstKind.ident_expr) {
        var name_id = env.store.identifiers.items[@intCast(usize, node.payload)];
        var c_sym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, @intCast(u32, 0), name_id);
        if (c_sym) |cs| {
            if ((cs.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                var c_decl = env.store.nodes.items[@intCast(usize, cs.decl_node)];
                if (c_decl.child_1 != 0) {
                    return evalConstU32Full(env, c_decl.child_1);
                }
            }
        }
    }
    return @intCast(u32, 0xFFFFFFFF);
}

pub fn resolveTypeExprFull(env: *TypeResolveEnv, node_idx: u32, depth: u32) type_mod.TypeId {
    if (depth > @intCast(u32, 16)) return type_mod.TYPE_UNDEFINED;
    var node = env.store.nodes.items[@intCast(usize, node_idx)];
    var rtd_nm: []const u8 = "RTD:n"; pal_mod.markerWriteInt(rtd_nm, node_idx); var rtd_km: []const u8 = "RTD:k"; pal_mod.markerWriteInt(rtd_km, @intCast(u32, @enumToInt(node.kind)));
    if (node.kind == AstKind.ident_expr) {
        var name_id = env.store.identifiers.items[@intCast(usize, node.payload)];
        var opm4_m: []const u8 = "OPTVOID:id"; pal_mod.markerWriteInt(opm4_m, name_id);
        var text = interner_mod.stringInternerGet(env.interner, name_id);
        var canonical_id = interner_mod.stringInternerIntern(env.interner, text);
        var tid = type_mod.nameCacheGet(env.typereg, @intCast(u64, canonical_id));
        var opnc_m: []const u8 = "OPTVOID:nc"; pal_mod.markerWriteInt(opnc_m, canonical_id);
        if (tid) |t| return t;
        var nf: []const u8 = "NF"; pal_mod.markerWrite(nf);
        var mi: usize = 0;
        while (mi < @intCast(usize, env.symbol_reg.tables_len)) : (mi += 1) {
            var ck: u64 = @intCast(u64, mi) * @intCast(u64, 4294967296) + @intCast(u64, canonical_id);
            var tc = type_mod.nameCacheGet(env.typereg, ck);
            if (tc) |t| return t;
        }
        var n2: []const u8 = "N2"; pal_mod.markerWrite(n2);
        var si: usize = 0;
        while (si < @intCast(usize, env.symbol_reg.tables_len)) : (si += 1) {
            var sym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, @intCast(u32, si), name_id);
            if (sym) |s| {
                if (s.type_id != @intCast(u32, 0)) {
                    var ops_m: []const u8 = "OPTVOID:ids"; pal_mod.markerWriteInt(ops_m, s.type_id);
                    return s.type_id;
                }
            }
        }
        var opm4f_m: []const u8 = "OPTVOID:idF"; pal_mod.markerWriteInt(opm4f_m, name_id);
        return type_mod.TYPE_UNDEFINED;
    }
    if (node.kind == AstKind.struct_decl) {
        var sd_id: [12]u8 = undefined;
        var sd_idl = itoa_mod.itoa(node_idx, sd_id[0..]);
        var sd_ids: usize = @intCast(usize, 11) - @intCast(usize, sd_idl);
        var sd_nm: [24]u8 = undefined;
        sd_nm[0] = @intCast(u8, 97); sd_nm[1] = @intCast(u8, 110); sd_nm[2] = @intCast(u8, 111); sd_nm[3] = @intCast(u8, 110); sd_nm[4] = @intCast(u8, 95);
        var sd_di: usize = 0;
        while (sd_di < @intCast(usize, sd_idl)) : (sd_di += 1) {
            sd_nm[@intCast(usize, 5) + sd_di] = sd_id[sd_ids + sd_di];
        }
        var sd_namelen: usize = @intCast(usize, 5) + @intCast(usize, sd_idl);
        var sd_name_id = interner_mod.stringInternerIntern(env.interner, sd_nm[0..sd_namelen]);
        var sd_existing = type_mod.nameCacheGet(env.typereg, @intCast(u64, sd_name_id));
        if (sd_existing) |se| return se;
        var sd_tid = type_mod.typeRegistryRegisterNamedType(env.typereg, @intCast(u32, 0), sd_name_id, type_mod.TypeKind.struct_type);
        if (node.payload != 0) {
            var sd_children = ast_mod.astStoreGetExtraChildren(env.store, node.payload);
            var sd_fty: [32]u32 = undefined;
            var sd_fnm: [32]u32 = undefined;
            var sd_fc: usize = 0;
            var sd_i: usize = 0;
            while (sd_i < sd_children.len and sd_fc < @intCast(usize, 32)) : (sd_i += 1) {
                var sd_fd = env.store.nodes.items[@intCast(usize, sd_children[sd_i])];
                if (sd_fd.kind == AstKind.field_decl) {
                    var sd_ft = resolveTypeExprFull(env, sd_fd.child_0, depth + @intCast(u32, 1));
                    sd_fty[sd_fc] = sd_ft;
                    sd_fnm[sd_fc] = sd_fd.payload;
                    sd_fc += 1;
                }
            }
            if (sd_fc > @intCast(usize, 0)) {
                var sd_fstart: u32 = @intCast(u32, env.typereg.fe_len);
                var sd_j: usize = 0;
                while (sd_j < sd_fc) : (sd_j += 1) {
                    type_mod.feAppend(env.typereg, type_mod.FieldEntry{
                        .name_id = sd_fnm[sd_j],
                        .type_id = sd_fty[sd_j],
                        .offset = @intCast(u32, 0),
                    });
                }
                type_mod.stAppend(env.typereg, type_mod.StructPayload{
                    .fields_start = @intCast(u16, sd_fstart),
                    .fields_count = @intCast(u16, sd_fc),
                });
                var sd_st_idx: u32 = @intCast(u32, env.typereg.st_len - @intCast(usize, 1));
                var sd_ty = env.typereg.types_items[@intCast(usize, sd_tid)];
                sd_ty.payload_idx = sd_st_idx;
                env.typereg.types_items[@intCast(usize, sd_tid)] = sd_ty;
            }
        }
        return sd_tid;
    }
    if (node.kind == AstKind.field_access) {
        var fah_matched: u8 = @intCast(u8, 0);
        var base_type = resolveTypeExprFull(env, node.child_0, depth + @intCast(u32, 1));
        if (base_type == type_mod.TYPE_UNDEFINED) {
            var base_node = env.store.nodes.items[@intCast(usize, node.child_0)];
            if (base_node.kind == AstKind.ident_expr) {
                var base_name_id = env.store.identifiers.items[@intCast(usize, base_node.payload)];
                var smi: usize = 0;
                while (smi < @intCast(usize, env.symbol_reg.tables_len)) : (smi += 1) {
                    var base_sym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, @intCast(u32, smi), base_name_id);
                    if (base_sym) |bs| {
                        if (bs.kind == sym_mod.SymbolKind.module) {
                            var mod_id = bs.module_id;
                            var payload_sym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, mod_id, node.payload);
                            if (payload_sym) |ps| {
                                if (ps.type_id != @intCast(u32, 0)) {
                                    fah_matched = @intCast(u8, 1);
                                    var fam: []const u8 = "FAH:r"; pal_mod.markerWriteInt(fam, ps.type_id);
                                    return ps.type_id;
                                }
                            }
                        }
                    }
                }
            }
            var fam_m: []const u8 = "FAH:m"; pal_mod.markerWriteInt(fam_m, node.child_0);
            return type_mod.TYPE_UNDEFINED;
        }
        var base_ty = env.typereg.types_items[@intCast(usize, base_type)];
        if (base_ty.kind == type_mod.TypeKind.module_type) {
            var mod_id = base_ty.module_id;
            var sym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, mod_id, node.payload);
            if (sym) |s| {
                if (s.type_id != @intCast(u32, 0)) {
                    fah_matched = @intCast(u8, 1);
                    var fam: []const u8 = "FAH:r"; pal_mod.markerWriteInt(fam, s.type_id);
                    return s.type_id;
                }
            }
        }
        if (fah_matched == @intCast(u8, 0)) {
            var fnm: []const u8 = "FAH:N"; pal_mod.markerWriteInt(fnm, node_idx);
        }
    }
    if (node.kind == AstKind.error_union_type) {
        var eu_payload_type = resolveTypeExprFull(env, node.child_1, depth + @intCast(u32, 1));
        if (eu_payload_type == type_mod.TYPE_UNDEFINED) return type_mod.TYPE_UNDEFINED;
        var eu_es_box: [1]u32 = [1]u32{ @intCast(u32, 0) };
        if (node.child_0 != 0) {
            var eu_resolved_es = resolveTypeExprFull(env, node.child_0, depth + @intCast(u32, 1));
            if (eu_resolved_es == type_mod.TYPE_UNDEFINED) return type_mod.TYPE_UNDEFINED;
            eu_es_box[0] = eu_resolved_es;
        } else {
            eu_es_box[0] = type_mod.typeRegistryGetOrCreateErrorSet(env.typereg, @intCast(u16, 0), @intCast(u16, 0));
        }
        return type_mod.typeRegistryGetOrCreateErrorUnion(env.typereg, eu_payload_type, eu_es_box[0]);
    }
    if (node.kind == AstKind.fn_type) {
        var fnt_ret_box: [1]u32 = [1]u32{ @intCast(u32, 0) };
        fnt_ret_box[0] = type_mod.TYPE_VOID;
        if (node.child_0 != 0) {
            fnt_ret_box[0] = resolveTypeExprFull(env, node.child_0, depth + @intCast(u32, 1));
            var opm2_m: []const u8 = "OPTVOID:fntR"; pal_mod.markerWriteInt(opm2_m, fnt_ret_box[0]);
            if (fnt_ret_box[0] == type_mod.TYPE_UNDEFINED) return type_mod.TYPE_UNDEFINED;
        }
        var fnt_ptypes: [16]u32 = undefined;
        var fnt_pc: usize = @intCast(usize, 0);
        if (node.payload != 0) {
            var fnt_extra = ast_mod.astStoreGetExtraChildren(env.store, node.payload);
            var fnt_i: usize = @intCast(usize, 0);
            while (fnt_i < fnt_extra.len and fnt_pc < @intCast(usize, 16)) : (fnt_i += @intCast(usize, 1)) {
                var fnt_pt = resolveTypeExprFull(env, fnt_extra[fnt_i], depth + @intCast(u32, 1));
                if (fnt_pt == type_mod.TYPE_UNDEFINED) return type_mod.TYPE_UNDEFINED;
                fnt_ptypes[fnt_pc] = fnt_pt;
                fnt_pc += @intCast(usize, 1);
            }
        }
        var fnt_nb: [96]u8 = undefined;
        var fnt_np: usize = @intCast(usize, 0);
        var fnt_pre: []const u8 = "fnt_";
        var fnt_pri: usize = @intCast(usize, 0);
        while (fnt_pri < fnt_pre.len and fnt_np < @intCast(usize, 95)) : (fnt_pri += @intCast(usize, 1)) {
            fnt_nb[fnt_np] = fnt_pre[fnt_pri];
            fnt_np += @intCast(usize, 1);
        }
        var fnt_rb: [12]u8 = undefined;
        var fnt_rl = itoa_mod.itoa(fnt_ret_box[0], fnt_rb[0..]);
        var fnt_rs: usize = @intCast(usize, 11) - @intCast(usize, fnt_rl);
        while (fnt_rs < @intCast(usize, 11) and fnt_np < @intCast(usize, 95)) : (fnt_rs += @intCast(usize, 1)) {
            fnt_nb[fnt_np] = fnt_rb[fnt_rs];
            fnt_np += @intCast(usize, 1);
        }
        var fnt_k: usize = @intCast(usize, 0);
        while (fnt_k < fnt_pc and fnt_np < @intCast(usize, 95)) : (fnt_k += @intCast(usize, 1)) {
            if (fnt_np < @intCast(usize, 95)) {
                fnt_nb[fnt_np] = @intCast(u8, 95);
                fnt_np += @intCast(usize, 1);
            }
            var fnt_pb: [12]u8 = undefined;
            var fnt_pl = itoa_mod.itoa(fnt_ptypes[fnt_k], fnt_pb[0..]);
            var fnt_ps: usize = @intCast(usize, 11) - @intCast(usize, fnt_pl);
            while (fnt_ps < @intCast(usize, 11) and fnt_np < @intCast(usize, 95)) : (fnt_ps += @intCast(usize, 1)) {
                fnt_nb[fnt_np] = fnt_pb[fnt_ps];
                fnt_np += @intCast(usize, 1);
            }
        }
        var fnt_name_id = interner_mod.stringInternerIntern(env.interner, fnt_nb[0..fnt_np]);
        var fnt_pstart: u32 = @intCast(u32, env.typereg.xt_len);
        var fnt_a: usize = @intCast(usize, 0);
        while (fnt_a < fnt_pc) : (fnt_a += @intCast(usize, 1)) {
            type_mod.xtAppend(env.typereg, fnt_ptypes[fnt_a]);
        }
        var fnt_tid = type_mod.typeRegistryGetOrCreateFn(env.typereg, fnt_name_id, @intCast(u32, 0), @intCast(u8, 0), @intCast(u16, fnt_pstart), @intCast(u16, fnt_pc), fnt_ret_box[0]);
        var opm3_m: []const u8 = "OPTVOID:fntT"; pal_mod.markerWriteInt(opm3_m, fnt_tid);
        type_mod.typeRegistryMarkFnPtrUsed(env.typereg, fnt_tid);
        return type_mod.typeRegistryGetOrCreatePtr(env.typereg, fnt_tid, false);
    }
    if (node.child_0 != 0) {
        var child_type = resolveTypeExprFull(env, node.child_0, depth + @intCast(u32, 1));
        if (child_type == type_mod.TYPE_UNDEFINED) return type_mod.TYPE_UNDEFINED;
        if (node.kind == AstKind.ptr_type or node.kind == AstKind.many_ptr_type) {
            var ptm: []const u8 = "PTR:i"; pal_mod.markerWrite(ptm);
            var ptib: [10]u8 = undefined; var ptil = itoa_mod.itoa(node_idx, ptib[0..]); var ptis: usize = @intCast(usize, 9) - @intCast(usize, ptil); pal_mod.markerWrite(ptib[ptis..@intCast(usize, 9)]);
            var ptkm: []const u8 = "k"; pal_mod.markerWrite(ptkm);
            var ptkb: [10]u8 = undefined; var ptkl = itoa_mod.itoa(@intCast(u32, @enumToInt(node.kind)), ptkb[0..]); var ptks: usize = @intCast(usize, 9) - @intCast(usize, ptkl); pal_mod.markerWrite(ptkb[ptks..@intCast(usize, 9)]);
            var ptcm: []const u8 = "c"; pal_mod.markerWrite(ptcm);
            var ptcb: [10]u8 = undefined; var ptcl = itoa_mod.itoa(child_type, ptcb[0..]); var ptcs: usize = @intCast(usize, 9) - @intCast(usize, ptcl); pal_mod.markerWrite(ptcb[ptcs..@intCast(usize, 9)]);
            var is_const: bool = (node.flags & @intCast(u8, 1)) != @intCast(u8, 0);
            if (node.kind == AstKind.ptr_type) {
                var ptr_tid = type_mod.typeRegistryGetOrCreatePtr(env.typereg, child_type, is_const);
                var ppm: []const u8 = "P"; pal_mod.markerWrite(ppm);
                var ppb: [10]u8 = undefined; var ppl = itoa_mod.itoa(ptr_tid, ppb[0..]); var pps: usize = @intCast(usize, 9) - @intCast(usize, ppl); pal_mod.markerWrite(ppb[pps..@intCast(usize, 9)]);
                var pnl: []const u8 = "\n"; pal_mod.markerWrite(pnl);
                return ptr_tid;
            } else {
                var ptr_tid2 = type_mod.typeRegistryGetOrCreateManyPtr(env.typereg, child_type, is_const);
                var ppm2: []const u8 = "M"; pal_mod.markerWrite(ppm2);
                var ppb2: [10]u8 = undefined; var ppl2 = itoa_mod.itoa(ptr_tid2, ppb2[0..]); var pps2: usize = @intCast(usize, 9) - @intCast(usize, ppl2); pal_mod.markerWrite(ppb2[pps2..@intCast(usize, 9)]);
                var pnl2: []const u8 = "\n"; pal_mod.markerWrite(pnl2);
                return ptr_tid2;
            }
        }
        if (node.kind == AstKind.slice_type) {
            var is_const: bool = (node.flags & @intCast(u8, 1)) != @intCast(u8, 0);
            var sl_tid = type_mod.typeRegistryGetOrCreateSlice(env.typereg, child_type, is_const);
            var sl_e: [20]u8 = undefined;
            var sl_el = itoa_mod.itoa(child_type, sl_e[0..]);
            var sl_es: usize = @intCast(usize, 19) - @intCast(usize, sl_el);
            var sm: []const u8 = "SL:e"; pal_mod.markerWrite(sm); pal_mod.markerWrite(sl_e[sl_es..@intCast(usize, 19)]);
            var sl_r: [20]u8 = undefined;
            var sl_rl = itoa_mod.itoa(sl_tid, sl_r[0..]);
            var sl_rs: usize = @intCast(usize, 19) - @intCast(usize, sl_rl);
            var s2: []const u8 = "s"; pal_mod.markerWrite(s2); pal_mod.markerWrite(sl_r[sl_rs..@intCast(usize, 19)]);
            var s3: []const u8 = "\n"; pal_mod.markerWrite(s3);
            return sl_tid;
        }
        if (node.kind == AstKind.optional_type) {
            var optvd_m: []const u8 = "OPTVOID:opt"; pal_mod.markerWriteInt(optvd_m, child_type);
            var optvd_tid = type_mod.typeRegistryGetOrCreateOptional(env.typereg, child_type);
            var optvd_rm: []const u8 = "OPTVOID:optR"; pal_mod.markerWriteInt(optvd_rm, optvd_tid);
            return optvd_tid;
        }
        if (node.kind == AstKind.array_type) {
            var t0m: []const u8 = "T0"; pal_mod.markerWrite(t0m);
            var t1m: []const u8 = "T1e"; pal_mod.markerWrite(t1m);
            var t1b: [20]u8 = undefined;
            var t1l = itoa_mod.itoa(child_type, t1b[0..]);
            var t1s: usize = @intCast(usize, 19) - @intCast(usize, t1l);
            pal_mod.markerWrite(t1b[t1s..@intCast(usize, 19)]);
            if (node.child_1 != 0) {
                var sz_node = env.store.nodes.items[@intCast(usize, node.child_1)];
                var arr_len: u32 = @intCast(u32, 0);
                if (sz_node.kind == AstKind.int_literal) {
                    arr_len = @intCast(u32, env.store.int_values.items[@intCast(usize, sz_node.payload)]);
                } else if (sz_node.kind == AstKind.add or sz_node.kind == AstKind.sub) {
                    var lhs = evalConstU32Full(env, sz_node.child_0);
                    var rhs = evalConstU32Full(env, sz_node.child_1);
                    if (lhs != @intCast(u32, 0xFFFFFFFF) and rhs != @intCast(u32, 0xFFFFFFFF)) {
                        if (sz_node.kind == AstKind.add) arr_len = lhs + rhs;
                        else arr_len = lhs - rhs;
                    }
                } else if (sz_node.kind == AstKind.ident_expr) {
                    var c_name_id = env.store.identifiers.items[@intCast(usize, sz_node.payload)];
                    var c_sym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, @intCast(u32, 0), c_name_id);
                    if (c_sym) |cs| {
                         if ((cs.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                            var c_decl = env.store.nodes.items[@intCast(usize, cs.decl_node)];
                            if (c_decl.child_1 != 0) {
                                var c_init = env.store.nodes.items[@intCast(usize, c_decl.child_1)];
                                if (c_init.kind == AstKind.int_literal) {
                                    arr_len = @intCast(u32, env.store.int_values.items[@intCast(usize, c_init.payload)]);
                                }
                            }
                        }
                    }
                }
                var t2m: []const u8 = "T2L"; pal_mod.markerWrite(t2m);
                var t2b: [20]u8 = undefined;
                var t2l = itoa_mod.itoa(arr_len, t2b[0..]);
                var t2s: usize = @intCast(usize, 19) - @intCast(usize, t2l);
                pal_mod.markerWrite(t2b[t2s..@intCast(usize, 19)]);
                if (arr_len != @intCast(u32, 0)) {
                    var at = type_mod.typeRegistryGetOrCreateArray(env.typereg, child_type, arr_len);
                    var t3m: []const u8 = "T3a"; pal_mod.markerWrite(t3m);
                    var t3b: [20]u8 = undefined;
                    var t3l = itoa_mod.itoa(at, t3b[0..]);
                    var t3s: usize = @intCast(usize, 19) - @intCast(usize, t3l);
                    pal_mod.markerWrite(t3b[t3s..@intCast(usize, 19)]);
                    if (at != type_mod.TYPE_UNDEFINED) { var am: []const u8 = "A"; pal_mod.markerWrite(am); }
                    else { var am: []const u8 = "a"; pal_mod.markerWrite(am); }
                    return at;
                }
            }
            return type_mod.TYPE_UNDEFINED;
        }
    }
    var und_nm2: []const u8 = "UND:n"; pal_mod.markerWriteInt(und_nm2, node_idx);
    var und_km: []const u8 = "UND:k"; pal_mod.markerWriteInt(und_km, @intCast(u32, @enumToInt(node.kind)));
    return type_mod.TYPE_UNDEFINED;
}

pub fn resolveDeclAggregateFieldTypes(env: *TypeResolveEnv, mod_id: u32, decl_idx: u32) void {
    var decl = env.store.nodes.items[@intCast(usize, decl_idx)];
    var init = env.store.nodes.items[@intCast(usize, decl.child_1)];
    var spid = type_mod.nameCacheGet(env.typereg, (@intCast(u64, mod_id) << @intCast(u64, 32)) | @intCast(u64, decl.payload));
    if (spid) |stid| {
        var sty = env.typereg.types_items[@intCast(usize, stid)];
        var fchildren = ast_mod.astStoreGetExtraChildren(env.store, init.payload);
        var fi2: usize = 0;
        if (sty.kind == type_mod.TypeKind.struct_type) {
            var sp = env.typereg.st_items[@intCast(usize, sty.payload_idx)];
            while (fi2 < @intCast(usize, sp.fields_count)) : (fi2 += 1) {
                var fd = env.store.nodes.items[@intCast(usize, fchildren[fi2])];
                if (fd.kind == AstKind.field_decl and fd.child_0 != 0) {
                    var ft = resolveTypeExprFull(env, fd.child_0, @intCast(u32, 0));
                    var b2_pn: []const u8 = "B2:p"; pal_mod.markerWrite(b2_pn);
                    var b2_pb: [20]u8 = undefined; var b2_pl = itoa_mod.itoa(fd.payload, b2_pb[0..]); var b2_ps: usize = @intCast(usize, 19) - @intCast(usize, b2_pl); pal_mod.markerWrite(b2_pb[b2_ps..@intCast(usize, 19)]);
                    var b2_tn: []const u8 = "t"; pal_mod.markerWrite(b2_tn);
                    var b2_tb: [20]u8 = undefined; var b2_tl = itoa_mod.itoa(ft, b2_tb[0..]); var b2_ts: usize = @intCast(usize, 19) - @intCast(usize, b2_tl); pal_mod.markerWrite(b2_tb[b2_ts..@intCast(usize, 19)]);
                    if (ft != type_mod.TYPE_UNDEFINED) {
                        env.typereg.fe_items[@intCast(usize, sp.fields_start) + fi2].type_id = ft;
                        var fsw_nm: []const u8 = "FSW:n"; pal_mod.markerWriteInt(fsw_nm, @intCast(u32, @intCast(usize, sp.fields_start) + fi2));
                        var fsw_tm: []const u8 = "FSW:t"; pal_mod.markerWriteInt(fsw_tm, ft);
                    }
                }
            }
        } else if (sty.kind == type_mod.TypeKind.tagged_union_type) {
            var tp = env.typereg.tu_items[@intCast(usize, sty.payload_idx)];
            var tui_fsm: []const u8 = "TUI:fs"; pal_mod.markerWriteInt(tui_fsm, @intCast(u32, tp.fields_start));
            var tui_fcm: []const u8 = "TUI:fc"; pal_mod.markerWriteInt(tui_fcm, @intCast(u32, tp.fields_count));
            while (fi2 < @intCast(usize, tp.fields_count)) : (fi2 += 1) {
                var fd = env.store.nodes.items[@intCast(usize, fchildren[fi2])];
                if (fd.kind == AstKind.field_decl and fd.child_0 != 0) {
                    var ft = resolveTypeExprFull(env, fd.child_0, @intCast(u32, 0));
                    var dft_nm: []const u8 = "DFT:n"; pal_mod.markerWriteInt(dft_nm, @intCast(u32, fi2));
                    var dft_tm: []const u8 = "DFT:t"; pal_mod.markerWriteInt(dft_tm, ft);
                    var b2_pn: []const u8 = "B2:p"; pal_mod.markerWrite(b2_pn);
                    var b2_pb: [20]u8 = undefined; var b2_pl = itoa_mod.itoa(fd.payload, b2_pb[0..]); var b2_ps: usize = @intCast(usize, 19) - @intCast(usize, b2_pl); pal_mod.markerWrite(b2_pb[b2_ps..@intCast(usize, 19)]);
                    var b2_tn: []const u8 = "t"; pal_mod.markerWrite(b2_tn);
                    var b2_tb: [20]u8 = undefined; var b2_tl = itoa_mod.itoa(ft, b2_tb[0..]); var b2_ts: usize = @intCast(usize, 19) - @intCast(usize, b2_tl); pal_mod.markerWrite(b2_tb[b2_ts..@intCast(usize, 19)]);
                    var dtwr_m: []const u8 = "DTWR\n"; pal_mod.markerWrite(dtwr_m);
                    if (ft != type_mod.TYPE_UNDEFINED) {
                        env.typereg.fe_items[@intCast(usize, tp.fields_start) + fi2].type_id = ft;
                        var ftw_nm: []const u8 = "FTW:n"; pal_mod.markerWriteInt(ftw_nm, @intCast(u32, @intCast(usize, tp.fields_start) + fi2));
                        var ftw_tm: []const u8 = "FTW:t"; pal_mod.markerWriteInt(ftw_tm, ft);
                    } else {
                        var dtsk_m: []const u8 = "DTSK\n"; pal_mod.markerWrite(dtsk_m);
                    }
                }
            }
        }
    }
}
