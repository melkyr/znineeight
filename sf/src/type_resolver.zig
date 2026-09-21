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
const mr_mod = @import("module_registry.zig");
const rtt_mod = @import("resolved_type_table.zig");
const hash_mod = @import("util/hash.zig");

pub const MODULE_ID_NONE: u32 = @intCast(u32, 0xFFFFFFFF);

// Maximum number of parameters a function type may carry. Module scope (next to
// the other file-wide consts) so `resolveFnSignatures`' parameter buffer size
// and its overflow guard share this one source of truth. Exceeding it is a hard
// `@panic` in `resolveFnSignatures`, never a silent truncation.
const MAX_FN_PARAMS: usize = 64;

pub const TypeResolveEnv = struct {

    store: *AstStore,
    typereg: *TypeRegistry,
    symbol_reg: *SymbolRegistry,
    interner: *StringInterner,
    module_id: u32,
    // Task 2c-F fix round 1: the source file of the module currently being
    // resolved, so the array-size hard error carries a real filename/line. The
    // module-iterating passes set this per module; passes with `diag = null`
    // leave it 0.
    source_file_id: u32,
    // Task 2c-F: optional hard-error sink for the array-size fallback. Only
    // passes with a live DiagnosticCollector set this (front_resolution, sema,
    // typeResolverResolveNames); lower/symbol_registrator/comptime_eval pass
    // null so they never emit.
    diag: ?*DiagnosticCollector,
    // Task 2c-F: the enclosing function's local-const scope (variant (e)),
    // consulted by `evalConstU32Full`'s ident_expr arm before the module symbol
    // tables. null outside a function body.
    local_consts: ?*LocalConstScope,
    // Task B2: the enclosing function's local-type scope (name -> TypeId),
    // consulted by `resolveTypeExprFull`'s ident_expr arm before the module
    // symbol tables so a function-local named type works inside a compound type
    // expression (`E!T`, `*E`, `[N]E`, `?E`). null outside a function body.
    local_types: ?*LocalTypeScope,
};

// Task B2: a name -> TypeId scope for function-local named types (the four
// container decls bound by a local `const`). A local type is a statement
// (parsed as a `var_decl`), so it is invisible to `symbolLookupAllModules`;
// this scope lets `resolveTypeExprFull` resolve it inside a compound type
// expression. Lookups scan newest -> oldest, so inner declarations shadow
// outer ones (mirrors `LocalConstScope`).
pub const LocalTypeScope = struct {
    names: [*]u32,
    types: [*]u32,
    count: usize,
    cap: usize,
    alloc: *Sand,
};

pub fn localTypeScopeInit(alloc: *Sand) LocalTypeScope {
    return LocalTypeScope{
        .names = undefined,
        .types = undefined,
        .count = @intCast(usize, 0),
        .cap = @intCast(usize, 0),
        .alloc = alloc,
    };
}

pub fn localTypeScopePush(scope: *LocalTypeScope, name_id: u32, type_id: u32) void {
    if (scope.count >= scope.cap) {
        var nc: usize = if (scope.cap < @intCast(usize, 8)) @intCast(usize, 8) else scope.cap * 2;
        var raw_n = alloc_mod.sandAlloc(scope.alloc, nc * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable;
        var raw_t = alloc_mod.sandAlloc(scope.alloc, nc * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable;
        var nn = @ptrCast([*]u32, raw_n);
        var nt = @ptrCast([*]u32, raw_t);
        var i: usize = 0;
        while (i < scope.count) : (i += 1) { nn[i] = scope.names[i]; nt[i] = scope.types[i]; }
        scope.names = nn;
        scope.types = nt;
        scope.cap = nc;
    }
    scope.names[scope.count] = name_id;
    scope.types[scope.count] = type_id;
    scope.count += @intCast(usize, 1);
}

pub fn localTypeScopeLookup(scope: *LocalTypeScope, name_id: u32) ?u32 {
    var i: usize = scope.count;
    while (i > @intCast(usize, 0)) {
        i -= @intCast(usize, 1);
        if (scope.names[i] == name_id) return scope.types[i];
    }
    return null;
}

// Task 2c-F: a name -> var_decl-node scope for function-local `const`s. A local
// const is a statement (parsed as a `var_decl`), so it is invisible to
// `symbolLookupAllModules`; this scope lets the array-size evaluator recurse
// into its initializer. Lookups scan newest -> oldest, so inner declarations
// shadow outer ones.
pub const LocalConstScope = struct {
    names: [*]u32,
    nodes: [*]u32,
    count: usize,
    cap: usize,
    alloc: *Sand,
};

pub fn localConstScopeInit(alloc: *Sand) LocalConstScope {
    return LocalConstScope{
        .names = undefined,
        .nodes = undefined,
        .count = @intCast(usize, 0),
        .cap = @intCast(usize, 0),
        .alloc = alloc,
    };
}

pub fn localConstScopePush(scope: *LocalConstScope, name_id: u32, decl_node: u32) void {
    if (scope.count >= scope.cap) {
        var nc: usize = if (scope.cap < @intCast(usize, 8)) @intCast(usize, 8) else scope.cap * 2;
        var raw_n = alloc_mod.sandAlloc(scope.alloc, nc * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable;
        var raw_d = alloc_mod.sandAlloc(scope.alloc, nc * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable;
        var nn = @ptrCast([*]u32, raw_n);
        var nd = @ptrCast([*]u32, raw_d);
        var i: usize = 0;
        while (i < scope.count) : (i += 1) { nn[i] = scope.names[i]; nd[i] = scope.nodes[i]; }
        scope.names = nn;
        scope.nodes = nd;
        scope.cap = nc;
    }
    scope.names[scope.count] = name_id;
    scope.nodes[scope.count] = decl_node;
    scope.count += @intCast(usize, 1);
}

pub fn localConstScopeLookup(scope: *LocalConstScope, name_id: u32) ?u32 {
    var i: usize = scope.count;
    while (i > @intCast(usize, 0)) {
        i -= @intCast(usize, 1);
        if (scope.names[i] == name_id) return scope.nodes[i];
    }
    return null;
}

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
    if (self.depend_cap > 0) {
        var grown = alloc_mod.sandTryReallocInPlace(self.alloc,
            @ptrCast([*]u8, self.depend_items),
            self.depend_cap * @intCast(usize, 8),
            nc * @intCast(usize, 8),
            @intCast(usize, 4));
        if (grown != null) {
            self.depend_cap = nc;
            return;
        }
    }
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
    if (self.worklist_cap > 0) {
        var grown = alloc_mod.sandTryReallocInPlace(self.alloc,
            @ptrCast([*]u8, self.worklist_items),
            self.worklist_cap * @intCast(usize, 4),
            nc * @intCast(usize, 4),
            @intCast(usize, 4));
        if (grown != null) {
            self.worklist_cap = nc;
            return;
        }
    }
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

// Task 11H (Option B, AMENDMENT 10): the ONE shared, order-independent layout
// math. `layoutCompute` is the verbatim former body of
// `typeResolverResolveLayout`; it does NOT touch `state` and must be called only
// once every direct dependency is complete (`state == 2`). The normal
// topological pass and the on-demand array-size fold both reach the layout math
// through `layoutEnsure`, so there is exactly one layout implementation and one
// dependency walk (no duplicated math that could silently diverge).
fn layoutCompute(registry: *TypeRegistry, tid: u32) void {
    var idx = @intCast(usize, tid);
    var ty = registry.types_items[idx];
    if (ty.kind == TypeKind.struct_type) {
        if ((ty.flags & @intCast(u8, 0x10)) != @intCast(u8, 0)) {
            type_mod.typeRegistryComputePackedLayout(registry, tid);
        } else {
            var sp = registry.st_items[@intCast(usize, ty.payload_idx)];
            var fstart: usize = @intCast(usize, sp.fields_start);
            var fcount: usize = @intCast(usize, sp.fields_count);
            var offset: u32 = 0;
            var max_align: u32 = 1;
            var fi: usize = 0;
            while (fi < fcount) : (fi += 1) {
                var fe = registry.fe_items[fstart + fi];
                var ft = registry.types_items[@intCast(usize, fe.type_id)];
                if (ft.kind == TypeKind.void_type) {
                    fe.offset = offset;
                    registry.fe_items[fstart + fi] = fe;
                } else {
                    offset = alignUp(offset, ft.alignment);
                    fe.offset = offset;
                    registry.fe_items[fstart + fi] = fe;
                    offset += ft.size;
                    if (ft.alignment > max_align) max_align = ft.alignment;
                }
            }
            ty.size = alignUp(offset, max_align);
            ty.alignment = max_align;
            if (ty.size == @intCast(u32, 0)) { ty.size = @intCast(u32, 1); ty.alignment = @intCast(u32, 1); }
            registry.types_items[idx] = ty;
        }
    } else if (ty.kind == TypeKind.enum_type) {
        var ep = registry.en_items[@intCast(usize, ty.payload_idx)];
        var bt = registry.types_items[@intCast(usize, ep.backing_type)];
        ty.size = bt.size;
        ty.alignment = bt.alignment;
        registry.types_items[idx] = ty;
    } else if (ty.kind == TypeKind.union_type) {
        var up = registry.un_items[@intCast(usize, ty.payload_idx)];
        var fstart: usize = @intCast(usize, up.fields_start);
        var fcount: usize = @intCast(usize, up.fields_count);
        var max_sz: u32 = 0;
        var max_align: u32 = 1;
        var fi: usize = 0;
        while (fi < fcount) : (fi += 1) {
            var fe = registry.fe_items[fstart + fi];
            var ft = registry.types_items[@intCast(usize, fe.type_id)];
            if (ft.kind != TypeKind.void_type) {
                if (ft.size > max_sz) max_sz = ft.size;
                if (ft.alignment > max_align) max_align = ft.alignment;
            }
        }
        ty.size = alignUp(max_sz, max_align);
        ty.alignment = max_align;
        if (ty.size == @intCast(u32, 0)) { ty.size = @intCast(u32, 1); ty.alignment = @intCast(u32, 1); }
        registry.types_items[idx] = ty;
     } else if (ty.kind == TypeKind.packed_union_type) {
        type_mod.typeRegistryComputePackedUnionLayout(registry, tid);
     } else if (ty.kind == TypeKind.tagged_union_type) {
         var tp = registry.tu_items[@intCast(usize, ty.payload_idx)];
         var tag_ty = registry.types_items[@intCast(usize, tp.tag_type)];
         var fstart: usize = @intCast(usize, tp.fields_start);
         var fcount: usize = @intCast(usize, tp.fields_count);
         var max_ps: u32 = 0;
         var max_pa: u32 = 1;
         var fi: usize = 0;
         while (fi < fcount) : (fi += 1) {
             var fe = registry.fe_items[fstart + fi];
             var fer_nm: []const u8 = "FER:n"; pal_mod.markerWriteInt(fer_nm, @intCast(u32, fstart + fi));
             var fer_tm: []const u8 = "FER:t"; pal_mod.markerWriteInt(fer_tm, fe.type_id);
            var ft = registry.types_items[@intCast(usize, fe.type_id)];
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
        registry.types_items[idx] = ty;
    } else if (ty.kind == TypeKind.optional_type) {
        var op = registry.opt_items[@intCast(usize, ty.payload_idx)];
        var pt = registry.types_items[@intCast(usize, op.payload)];
        var pay_align = if (pt.alignment > @intCast(u32, 4)) pt.alignment else @intCast(u32, 4);
        ty.size = alignUp(alignUp(pt.size, @intCast(u32, 4)) + @intCast(u32, 4), pay_align);
        ty.alignment = pay_align;
        registry.types_items[idx] = ty;
    } else if (ty.kind == TypeKind.error_union_type) {
        var ep = registry.eu_items[@intCast(usize, ty.payload_idx)];
        var pt = registry.types_items[@intCast(usize, ep.payload)];
        var union_sz = if (pt.size > @intCast(u32, 4)) pt.size else @intCast(u32, 4);
        var union_align = if (pt.alignment > @intCast(u32, 4)) pt.alignment else @intCast(u32, 4);
        var total = alignUp(union_sz, union_align);
        total = alignUp(total, @intCast(u32, 4)) + @intCast(u32, 4);
        ty.size = alignUp(total, union_align);
        ty.alignment = union_align;
        registry.types_items[idx] = ty;
    } else if (ty.kind == TypeKind.array_type) {
        var ap = registry.array_items[@intCast(usize, ty.payload_idx)];
        var et = registry.types_items[@intCast(usize, ap.elem)];
        ty.size = et.size * ap.length;
        ty.alignment = et.alignment;
        registry.types_items[idx] = ty;
    } else if (ty.kind == TypeKind.tuple_type) {
        var tp = registry.tup_items[@intCast(usize, ty.payload_idx)];
        var estr: usize = @intCast(usize, tp.elems_start);
        var ecount: usize = @intCast(usize, tp.elems_count);
        var offset: u32 = 0;
        var max_align: u32 = 1;
        var ei: usize = 0;
        while (ei < ecount) : (ei += 1) {
            var elem_tid = registry.xt_items[estr + ei];
            var et = registry.types_items[@intCast(usize, elem_tid)];
            offset = alignUp(offset, et.alignment);
            offset += et.size;
            if (et.alignment > max_align) max_align = et.alignment;
        }
        ty.size = alignUp(offset, max_align);
        ty.alignment = max_align;
        if (ty.size == @intCast(u32, 0)) { ty.size = @intCast(u32, 1); ty.alignment = @intCast(u32, 1); }
        registry.types_items[idx] = ty;
    }
}

// Task 11H: a direct dependency is usable for an on-demand layout only when it
// is a real, complete type. `0` and `TYPE_UNDEFINED` are never types;
// `TYPE_VOID` (id 1) is the symbol-registration placeholder for a field whose
// type was not resolved (`symbol_registrator.zig:111`), so it must be deferred
// — treating it as a real zero-size void field is what produced the silent
// wrong `[1]` for a forward-referenced aggregate.
fn layoutDepOk(registry: *TypeRegistry, dep: u32, depth: u32) bool {
    if (dep == @intCast(u32, 0)) return false;
    if (dep == type_mod.TYPE_UNDEFINED) return false;
    if (dep == type_mod.TYPE_VOID) return false;
    return layoutEnsure(registry, dep, depth);
}

fn layoutFieldDepsOk(registry: *TypeRegistry, fstart: u32, fcount: u16, depth: u32) bool {
    var fi: usize = 0;
    while (fi < @intCast(usize, fcount)) : (fi += 1) {
        if (!layoutDepOk(registry, registry.fe_items[@intCast(usize, fstart) + fi].type_id, depth)) return false;
    }
    return true;
}

// Task 11H: make `tid` complete on demand, order-independently. Returns true
// only when `tid` is (or was made) `state == 2`. Never reads `size`/`alignment`
// of an incomplete dependency: every direct dependency is walked first and the
// layout math runs only when all of them are complete. A depth cap (mirrors
// `resolveTypeExprFull`'s 16) turns a cyclic/mutual graph into a safe `false`
// (the array-size fold then leaves `ERR_3050`).
pub fn layoutEnsure(registry: *TypeRegistry, tid: u32, depth: u32) bool {
    if (tid == @intCast(u32, 0)) return false;
    if (@intCast(usize, tid) >= registry.types_len) return false;
    var ty = registry.types_items[@intCast(usize, tid)];
    if (ty.state == @intCast(u8, 2)) return true;
    if (depth > @intCast(u32, 16)) return false;
    var deps_ok: bool = true;
    var handled: bool = true;
    if (ty.kind == TypeKind.struct_type) {
        var sp = registry.st_items[@intCast(usize, ty.payload_idx)];
        deps_ok = layoutFieldDepsOk(registry, sp.fields_start, sp.fields_count, depth + @intCast(u32, 1));
    } else if (ty.kind == TypeKind.enum_type) {
        var ep = registry.en_items[@intCast(usize, ty.payload_idx)];
        deps_ok = layoutDepOk(registry, ep.backing_type, depth + @intCast(u32, 1));
    } else if (ty.kind == TypeKind.union_type) {
        var up = registry.un_items[@intCast(usize, ty.payload_idx)];
        deps_ok = layoutFieldDepsOk(registry, up.fields_start, up.fields_count, depth + @intCast(u32, 1));
    } else if (ty.kind == TypeKind.packed_union_type) {
        var pup = registry.un_items[@intCast(usize, ty.payload_idx)];
        deps_ok = layoutFieldDepsOk(registry, pup.fields_start, pup.fields_count, depth + @intCast(u32, 1));
    } else if (ty.kind == TypeKind.tagged_union_type) {
        var tp = registry.tu_items[@intCast(usize, ty.payload_idx)];
        deps_ok = layoutDepOk(registry, tp.tag_type, depth + @intCast(u32, 1));
        if (deps_ok) {
            deps_ok = layoutFieldDepsOk(registry, tp.fields_start, tp.fields_count, depth + @intCast(u32, 1));
        }
    } else if (ty.kind == TypeKind.array_type) {
        var ap = registry.array_items[@intCast(usize, ty.payload_idx)];
        deps_ok = layoutDepOk(registry, ap.elem, depth + @intCast(u32, 1));
    } else if (ty.kind == TypeKind.tuple_type) {
        var tup = registry.tup_items[@intCast(usize, ty.payload_idx)];
        var ei: usize = 0;
        while (ei < @intCast(usize, tup.elems_count)) : (ei += 1) {
            if (!layoutDepOk(registry, registry.xt_items[@intCast(usize, tup.elems_start) + ei], depth + @intCast(u32, 1))) {
                deps_ok = false;
            }
        }
    } else if (ty.kind == TypeKind.optional_type) {
        var op = registry.opt_items[@intCast(usize, ty.payload_idx)];
        deps_ok = layoutDepOk(registry, op.payload, depth + @intCast(u32, 1));
    } else if (ty.kind == TypeKind.error_union_type) {
        var eup = registry.eu_items[@intCast(usize, ty.payload_idx)];
        deps_ok = layoutDepOk(registry, eup.payload, depth + @intCast(u32, 1));
    } else {
        handled = false;
    }
    if (!handled) return false;
    if (!deps_ok) return false;
    layoutCompute(registry, tid);
    registry.types_items[@intCast(usize, tid)].state = @intCast(u8, 2);
    return true;
}

// Task 11H: the normal topological pass entry point. Dependencies of a popped
// (acyclic) type are complete by construction, so `layoutEnsure` normally
// computes and marks `state == 2`. When the walk declines — a legitimate
// zero-size `void` field, a depth cap, or a kind with no layout math — fall
// back to the verbatim math, preserving the historical normal-pass behavior.
// The on-demand array-size fold never takes this fallback.
fn typeResolverResolveLayout(self: *TypeResolver, tid: u32) void {
    if (!layoutEnsure(self.registry, tid, @intCast(u32, 0))) {
        layoutCompute(self.registry, tid);
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
    if (kind == TypeKind.packed_union_type) return true;
    if (kind == TypeKind.array_type) return true;
    if (kind == TypeKind.tuple_type) return true;
    if (kind == TypeKind.enum_type) return true;          // ADD — inline typedef integer alias
    if (kind == TypeKind.error_set_type) return true;     // ADD — inline typedef integer alias
    return false;
}

fn requiresFullDef(kind: TypeKind) bool {
    if (kind == TypeKind.struct_type) return true;
    if (kind == TypeKind.tagged_union_type) return true;
    if (kind == TypeKind.union_type) return true;
    if (kind == TypeKind.packed_union_type) return true;
    if (kind == TypeKind.array_type) return true;
    if (kind == TypeKind.tuple_type) return true;
    if (kind == TypeKind.optional_type) return true;
    if (kind == TypeKind.error_union_type) return true;
    return false;
}

fn layoutFieldNeedsEdge(kind: TypeKind) bool {
    if (kind == TypeKind.struct_type) return true;
    if (kind == TypeKind.tagged_union_type) return true;
    if (kind == TypeKind.union_type) return true;
    if (kind == TypeKind.packed_union_type) return true;
    if (kind == TypeKind.enum_type) return true;
    if (kind == TypeKind.array_type) return true;
    if (kind == TypeKind.tuple_type) return true;
    if (kind == TypeKind.optional_type) return true;
    if (kind == TypeKind.error_union_type) return true;
    return false;
}

fn layoutAddTypeEdge(self: *TypeResolver, field_type: u32, container_tid: u32) void {
    if (field_type >= @intCast(u32, self.registry.types_len)) return;
    var ft = self.registry.types_items[@intCast(usize, field_type)];
    if (layoutFieldNeedsEdge(ft.kind)) {
        typeResolverAddEdge(self, field_type, container_tid);
    }
}

fn layoutAddFieldEdges(self: *TypeResolver, fstart: u32, fcount: u16, container_tid: u32) void {
    var fi: usize = 0;
    while (fi < @intCast(usize, fcount)) : (fi += 1) {
        layoutAddTypeEdge(self, self.registry.fe_items[@intCast(usize, fstart) + fi].type_id, container_tid);
    }
}

pub fn typeResolverBuildDependencyGraph(self: *TypeResolver) void {
    var ti: usize = 0;
    while (ti < self.registry.types_len) : (ti += 1) {
        var ty = self.registry.types_items[ti];
        var container_tid = @intCast(u32, ti);
        if (ty.kind == TypeKind.struct_type) {
            var sp = self.registry.st_items[@intCast(usize, ty.payload_idx)];
            layoutAddFieldEdges(self, sp.fields_start, sp.fields_count, container_tid);
        } else if (ty.kind == TypeKind.tagged_union_type) {
            var tp = self.registry.tu_items[@intCast(usize, ty.payload_idx)];
            layoutAddFieldEdges(self, tp.fields_start, tp.fields_count, container_tid);
        } else if (ty.kind == TypeKind.union_type) {
            var up = self.registry.un_items[@intCast(usize, ty.payload_idx)];
            layoutAddFieldEdges(self, up.fields_start, up.fields_count, container_tid);
        } else if (ty.kind == TypeKind.packed_union_type) {
            var pup = self.registry.un_items[@intCast(usize, ty.payload_idx)];
            layoutAddFieldEdges(self, pup.fields_start, pup.fields_count, container_tid);
        } else if (ty.kind == TypeKind.array_type) {
            layoutAddTypeEdge(self, self.registry.array_items[@intCast(usize, ty.payload_idx)].elem, container_tid);
        } else if (ty.kind == TypeKind.tuple_type) {
            var tp = self.registry.tup_items[@intCast(usize, ty.payload_idx)];
            var ei: usize = 0;
            while (ei < @intCast(usize, tp.elems_count)) : (ei += 1) {
                layoutAddTypeEdge(self, self.registry.xt_items[@intCast(usize, tp.elems_start) + ei], container_tid);
            }
        } else if (ty.kind == TypeKind.optional_type) {
            layoutAddTypeEdge(self, self.registry.opt_items[@intCast(usize, ty.payload_idx)].payload, container_tid);
        } else if (ty.kind == TypeKind.error_union_type) {
            layoutAddTypeEdge(self, self.registry.eu_items[@intCast(usize, ty.payload_idx)].payload, container_tid);
        }
    }
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
                    growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, ft_id)];
                    wp_head[@intCast(usize, ft_id)] = wp_count;
                    wp_count += @intCast(u32, 1);
                } else if (ft.kind == TypeKind.error_union_type) {
                    growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, ft_id)];
                    wp_head[@intCast(usize, ft_id)] = wp_count;
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
                    growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, ft_id)];
                    wp_head[@intCast(usize, ft_id)] = wp_count;
                    wp_count += @intCast(u32, 1);
                } else if (ft.kind == TypeKind.error_union_type) {
                    growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, ft_id)];
                    wp_head[@intCast(usize, ft_id)] = wp_count;
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
                    growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, ft_id)];
                    wp_head[@intCast(usize, ft_id)] = wp_count;
                    wp_count += @intCast(u32, 1);
                } else if (ft.kind == TypeKind.error_union_type) {
                    growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, ft_id)];
                    wp_head[@intCast(usize, ft_id)] = wp_count;
                    wp_count += @intCast(u32, 1);
                }
            }
        } else if (ty.kind == TypeKind.packed_union_type) {
            var p_up = self.registry.un_items[@intCast(usize, ty.payload_idx)];
            var pfi: usize = 0;
            while (pfi < @intCast(usize, p_up.fields_count) and is_po != 0) : (pfi += 1) {
                var ft_id = self.registry.fe_items[@intCast(usize, p_up.fields_start) + pfi].type_id;
                var ft = self.registry.types_items[@intCast(usize, ft_id)];
                if (fieldEmbedsByValue(ft.kind)) {
                    is_po = @intCast(u8, 0);
                } else if (ft.kind == TypeKind.optional_type) {
                    growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, ft_id)];
                    wp_head[@intCast(usize, ft_id)] = wp_count;
                    wp_count += @intCast(u32, 1);
                } else if (ft.kind == TypeKind.error_union_type) {
                    growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, ft_id)];
                    wp_head[@intCast(usize, ft_id)] = wp_count;
                    wp_count += @intCast(u32, 1);
                }
            }
        } else if (ty.kind == TypeKind.array_type) {
            var et = self.registry.array_items[@intCast(usize, ty.payload_idx)].elem;
            var et_ty = self.registry.types_items[@intCast(usize, et)];
            if (fieldEmbedsByValue(et_ty.kind)) {
                is_po = @intCast(u8, 0);
            } else if (et_ty.kind == TypeKind.optional_type) {
                growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, et)];
                wp_head[@intCast(usize, et)] = wp_count;
                wp_count += @intCast(u32, 1);
            } else if (et_ty.kind == TypeKind.error_union_type) {
                growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, et)];
                wp_head[@intCast(usize, et)] = wp_count;
                wp_count += @intCast(u32, 1);
            }
        } else if (ty.kind == TypeKind.error_union_type) {
            var eup = self.registry.eu_items[@intCast(usize, ty.payload_idx)].payload;
            var eup_ty = self.registry.types_items[@intCast(usize, eup)];
            if (fieldEmbedsByValue(eup_ty.kind)) {
                is_po = @intCast(u8, 0);
            } else if (eup_ty.kind == TypeKind.optional_type) {
                growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, eup)];
                wp_head[@intCast(usize, eup)] = wp_count;
                wp_count += @intCast(u32, 1);
            } else if (eup_ty.kind == TypeKind.error_union_type) {
                growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, eup)];
                wp_head[@intCast(usize, eup)] = wp_count;
                wp_count += @intCast(u32, 1);
            }
        } else if (ty.kind == TypeKind.optional_type) {
            var op_p = self.registry.opt_items[@intCast(usize, ty.payload_idx)].payload;
            var op_ty = self.registry.types_items[@intCast(usize, op_p)];
            if (requiresFullDef(op_ty.kind)) {
                is_po = @intCast(u8, 0);
            } else if (op_ty.kind == TypeKind.optional_type) {
                growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, op_p)];
                wp_head[@intCast(usize, op_p)] = wp_count;
                wp_count += @intCast(u32, 1);
            } else if (op_ty.kind == TypeKind.error_union_type) {
                growWpEdges(perm_alloc, &wp_to, &wp_next, &wp_edge_cap, wp_count);
                wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, op_p)];
                wp_head[@intCast(usize, op_p)] = wp_count;
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

// Task 2b-F (#1): resolve the module a field-access base expression denotes,
// walking a module-alias chain (`mid` -> `mid.leaf` -> ...). A base is a module
// reference when it is a `SymbolKind.module` symbol (a direct `@import` alias)
// or when its resolved type is `module_type` (a nested module alias). Returns
// the module id, or 0 when the expression is not a module reference. Mirrors
// the module lookup in `resolveTypeExprFull`'s field_access arm.
fn evalConstModuleOfExpr(env: *TypeResolveEnv, node_idx: u32) u32 {
    if (node_idx == @intCast(u32, 0)) return @intCast(u32, 0);
    var node = ast_mod.astStoreNodeAt(env.store, node_idx);
    if (node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(env.store, node_idx);
        if (env.module_id != MODULE_ID_NONE) {
            if (sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, env.module_id, name_id)) |s| {
                if (s.kind == sym_mod.SymbolKind.module) return s.module_id;
                if (s.type_id != @intCast(u32, 0) and @intCast(usize, s.type_id) < env.typereg.types_len) {
                    var sty = env.typereg.types_items[@intCast(usize, s.type_id)];
                    if (sty.kind == type_mod.TypeKind.module_type) return sty.module_id;
                }
            }
        }
        var si: usize = 0;
        while (si < @intCast(usize, env.symbol_reg.tables_len)) : (si += 1) {
            var sym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, @intCast(u32, si), name_id);
            if (sym) |s2| {
                if (s2.kind == sym_mod.SymbolKind.module) return s2.module_id;
                if (s2.type_id != @intCast(u32, 0) and @intCast(usize, s2.type_id) < env.typereg.types_len) {
                    var sty2 = env.typereg.types_items[@intCast(usize, s2.type_id)];
                    if (sty2.kind == type_mod.TypeKind.module_type) return sty2.module_id;
                }
            }
        }
        return @intCast(u32, 0);
    }
    if (node.kind == AstKind.field_access) {
        var base_mod = evalConstModuleOfExpr(env, node.child_0);
        if (base_mod == @intCast(u32, 0)) return @intCast(u32, 0);
        var field_name_id = ast_mod.astStoreNodePayload(env.store, node_idx);
        if (sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, base_mod, field_name_id)) |msym| {
            if (msym.kind == sym_mod.SymbolKind.module) return msym.module_id;
            if (msym.type_id != @intCast(u32, 0) and @intCast(usize, msym.type_id) < env.typereg.types_len) {
                var mty = env.typereg.types_items[@intCast(usize, msym.type_id)];
                if (mty.kind == type_mod.TypeKind.module_type) return mty.module_id;
            }
        }
        return @intCast(u32, 0);
    }
    return @intCast(u32, 0);
}

// Task 11F: true for the primitive/alias type kinds whose `@sizeOf`/`@alignOf`/
// `@bitSizeOf` are safe to fold during array-size resolution. The aggregate
// kinds are deliberately EXCLUDED: struct/aggregate introspection in an
// array-size position is deferred to Task 11G/11H, and the `state == 2` gate
// alone does not make those folds safe at every resolution point (a field type
// resolved by `resolveAggregateFieldTypesAll` can precede layout).
fn evalConstScalarKind(kind: TypeKind) bool {
    if (kind == TypeKind.struct_type) return false;
    if (kind == TypeKind.union_type) return false;
    if (kind == TypeKind.tagged_union_type) return false;
    if (kind == TypeKind.packed_union_type) return false;
    if (kind == TypeKind.tuple_type) return false;
    if (kind == TypeKind.array_type) return false;
    if (kind == TypeKind.slice_type) return false;
    if (kind == TypeKind.optional_type) return false;
    if (kind == TypeKind.error_union_type) return false;
    if (kind == TypeKind.fn_type) return false;
    if (kind == TypeKind.module_type) return false;
    if (kind == TypeKind.type_type) return false;
    if (kind == TypeKind.unresolved_name) return false;
    if (kind == TypeKind.none_sentinel) return false;
    return true;
}

pub fn evalConstU32Full(env: *TypeResolveEnv, node_idx: u32, depth: u32) u32 {
    // Task 2c-F fix round 1: mirror `resolveTypeExprFull`'s depth cap (`:925`)
    // so a const cycle in array-size position (`const A = A + 1`, or
    // `const A = B; const B = A`) terminates as an unfoldable value — a clean
    // hard error via the array-size fallback — never unbounded recursion / ICE.
    if (depth > @intCast(u32, 16)) return @intCast(u32, 0xFFFFFFFF);
    if (node_idx == @intCast(u32, 0)) return @intCast(u32, 0xFFFFFFFF);
    var node = ast_mod.astStoreNodeAt(env.store, node_idx);
    if (node.kind == AstKind.int_literal) {
        return @intCast(u32, ast_mod.astStoreIntValue(env.store, node_idx));
    }
    // Task 2c-F: fold an arithmetic expression node. A module `const C = A * B`
    // recurses from the ident_expr arm into its initializer, which is one of
    // these binary nodes; mirror the array_type arm's inline semantics
    // (0xFFFFFFFF = unfoldable sentinel; div/mod by zero is unfoldable).
    if (node.kind == AstKind.add or node.kind == AstKind.sub or
        node.kind == AstKind.mul or node.kind == AstKind.div or node.kind == AstKind.mod_op) {
        var bl = evalConstU32Full(env, node.child_0, depth + @intCast(u32, 1));
        var br = evalConstU32Full(env, node.child_1, depth + @intCast(u32, 1));
        if (bl != @intCast(u32, 0xFFFFFFFF) and br != @intCast(u32, 0xFFFFFFFF)) {
            if (node.kind == AstKind.add) { return bl + br; }
            if (node.kind == AstKind.sub) { return bl - br; }
            if (node.kind == AstKind.mul) { return bl * br; }
            if (node.kind == AstKind.div) {
                if (br != @intCast(u32, 0)) { return bl / br; }
                return @intCast(u32, 0xFFFFFFFF);
            }
            if (br != @intCast(u32, 0)) { return bl % br; }
        }
        return @intCast(u32, 0xFFFFFFFF);
    }
    // Task 2c-F: `-v` folds as `0 - v` (mirrors evalConstI64Full's negate arm).
    if (node.kind == AstKind.negate) {
        if (node.child_0 != @intCast(u32, 0)) {
            var nv = evalConstU32Full(env, node.child_0, depth + @intCast(u32, 1));
            if (nv != @intCast(u32, 0xFFFFFFFF)) {
                return @intCast(u32, 0) - nv;
            }
        }
        return @intCast(u32, 0xFFFFFFFF);
    }
    if (node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(env.store, node_idx);
        // Task 2c-F (variant (e)): consult the enclosing function's local-const
        // scope before the module symbol tables. A local `const N = <expr>` is a
        // statement, not a module symbol, so only this scope can see it.
        if (env.local_consts) |lcs| {
            if (localConstScopeLookup(lcs, name_id)) |l_decl_node| {
                var l_decl = ast_mod.astStoreNodeAt(env.store, l_decl_node);
                if (l_decl.child_1 != 0) {
                    return evalConstU32Full(env, l_decl.child_1, depth + @intCast(u32, 1));
                }
            }
        }
        var c_sym = symbolLookupAllModules(env, name_id);
        if (c_sym) |cs| {
            if ((cs.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                var c_decl = ast_mod.astStoreNodeAt(env.store, cs.decl_node);
                if (c_decl.child_1 != 0) {
                    return evalConstU32Full(env, c_decl.child_1, depth + @intCast(u32, 1));
                }
            }
        }
    }
    // Task 2b-F (#1): a field-access const in array-size position
    // (`[mid.leaf.HEADER_SIZE]`). Resolve the base module through the alias
    // chain, then fold the member const's initializer recursively. The existing
    // `ident_expr` recursion above then also covers `const N = <member>`.
    if (node.kind == AstKind.field_access) {
        var fa_mod_id = evalConstModuleOfExpr(env, node.child_0);
        if (fa_mod_id != @intCast(u32, 0)) {
            var fa_field_id = ast_mod.astStoreNodePayload(env.store, node_idx);
            if (sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, fa_mod_id, fa_field_id)) |fa_sym| {
                if ((fa_sym.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                    var fa_decl = ast_mod.astStoreNodeAt(env.store, fa_sym.decl_node);
                    if (fa_decl.child_1 != 0) {
                        return evalConstU32Full(env, fa_decl.child_1, depth + @intCast(u32, 1));
                    }
                }
            }
        }
    }
    // Task 11F: fold the clear integer-valued builtins in an array-size
    // position. The general fold evaluator (`comptime_eval.zig`) runs in a
    // LATER pipeline phase and is never consulted by type resolution, so
    // `[@intCast(u32, n)]`, `[@sizeOf(u32)]`, `[@alignOf(u32)]`, and
    // `[@bitSizeOf(u32)]` all fell through to the `ERR_3050` fallback. Fold
    // only the integer-valued builtins, and only on COMPLETE (`state == 2`)
    // primitive/alias types. Everything else — `@isWindows` (bool),
    // `@intToFloat`/`@floatCast` (float), and `@offsetOf`/`@bitOffsetOf`
    // (aggregate field introspection, deferred to Task 11G/11H) — stays the
    // unfoldable sentinel so the caller keeps rejecting it, consistent with
    // `[true]`/`[4.0]`.
    if (node.kind == AstKind.builtin_call) {
        var s_size: []const u8 = "@sizeOf";
        var size_id = interner_mod.stringInternerIntern(env.interner, s_size);
        var s_align: []const u8 = "@alignOf";
        var align_id = interner_mod.stringInternerIntern(env.interner, s_align);
        var s_bitsz: []const u8 = "@bitSizeOf";
        var bitsz_id = interner_mod.stringInternerIntern(env.interner, s_bitsz);
        var s_intc: []const u8 = "@intCast";
        var intc_id = interner_mod.stringInternerIntern(env.interner, s_intc);
        var bc_n = ast_mod.astStoreNodeExtraChildCount(env.store, node_idx);
        // `@intCast(T, e)`: resolve the target `T`, fold the operand `e` (the
        // existing `ident_expr`/binary/`negate` arms above handle local consts,
        // module const chains, and arithmetic operands), and range-check it
        // against `T` (Task 11S (a)).
        if (node.child_0 == intc_id) {
            if (bc_n >= @intCast(u32, 2)) {
                // Task 11S (a): resolve the target type and range-check the
                // folded operand against it. `@intCast(u8, 300)` in an
                // array-size position is invalid Zig; before this gate the arm
                // discarded the target and folded 300 as the dimension. The
                // operand MUST fold through `evalConstU32Full` (not the i64
                // twin) so a function-local `const N = 7` still resolves.
                var ic_tid = resolveTypeExprFull(env, ast_mod.astStoreNodeExtraChildAt(env.store, node_idx, @intCast(u32, 0)), depth + @intCast(u32, 1));
                var ic_v = evalConstU32Full(env, ast_mod.astStoreNodeExtraChildAt(env.store, node_idx, @intCast(u32, 1)), depth + @intCast(u32, 1));
                if (ic_tid != type_mod.TYPE_UNDEFINED and ic_v != @intCast(u32, 0xFFFFFFFF)) {
                    if (intValueFitsType(env, ic_tid, @intCast(i64, ic_v))) {
                        return ic_v;
                    }
                    if (env.diag) |dg| {
                        if (diag_mod.diagnosticCollectorMarkNodeOnce(dg, node_idx)) {
                            var ic_msg: []const u8 = "@intCast value does not fit the target type";
                            _ = diag_mod.diagnosticCollectorAdd(dg, @intCast(u8, 0),
                                @intCast(u16, 3000),
                                env.source_file_id, node.span_start,
                                node.span_start + @intCast(u32, node.span_len), ic_msg);
                        }
                    }
                }
            }
            return @intCast(u32, 0xFFFFFFFF);
        }
        if (node.child_0 == size_id or node.child_0 == align_id or node.child_0 == bitsz_id) {
            if (bc_n >= @intCast(u32, 1)) {
                var bt_tid = resolveTypeExprFull(env, ast_mod.astStoreNodeExtraChildAt(env.store, node_idx, @intCast(u32, 0)), depth + @intCast(u32, 1));
                if (bt_tid != type_mod.TYPE_UNDEFINED) {
                    var bt_ty = env.typereg.types_items[@intCast(usize, bt_tid)];
                    // Task 11H: an aggregate in an array-size position is made
                    // complete on demand through the SAME shared,
                    // order-independent `layoutEnsure` the normal pass uses.
                    // Only the in-scope aggregate kind (a struct, packed or
                    // not) is completed here; tuple/slice/union/etc. stay
                    // unfolded (`ERR_3050`). The `state == 2` gate below is
                    // MANDATORY: reading `size`/`alignment` before layout yields
                    // a silently WRONG array length.
                    if (bt_ty.state != @intCast(u8, 2) and bt_ty.kind == TypeKind.struct_type) {
                        _ = layoutEnsure(env.typereg, bt_tid, @intCast(u32, 0));
                        bt_ty = env.typereg.types_items[@intCast(usize, bt_tid)];
                    }
                    var bt_foldable = evalConstScalarKind(bt_ty.kind);
                    if (bt_ty.kind == TypeKind.struct_type) { bt_foldable = true; }
                    if (bt_ty.state == @intCast(u8, 2) and bt_foldable) {
                        if (node.child_0 == size_id) { return bt_ty.size; }
                        if (node.child_0 == align_id) { return bt_ty.alignment; }
                        var bt_bits: u32 = bt_ty.size * @intCast(u32, 8);
                        if (type_mod.typeRegistryIsInteger(env.typereg, bt_tid)) {
                            bt_bits = @intCast(u32, type_mod.typeRegistryIntWidthBits(env.typereg, bt_tid));
                        }
                        if (bt_ty.kind == TypeKind.enum_type) {
                            bt_bits = @intCast(u32, type_mod.typeRegistryIntWidthBits(env.typereg, type_mod.typeRegistryEnumBackingType(env.typereg, bt_tid)));
                        }
                        if (bt_ty.kind == TypeKind.bool_type) { bt_bits = @intCast(u32, 1); }
                        if (bt_ty.kind == TypeKind.struct_type and (bt_ty.flags & @intCast(u8, 0x10)) != @intCast(u8, 0)) {
                            bt_bits = @intCast(u32, type_mod.typeRegistryGetPackedTotalBits(env.typereg, bt_tid));
                        }
                        return bt_bits;
                    }
                }
            }
            return @intCast(u32, 0xFFFFFFFF);
        }
        return @intCast(u32, 0xFFFFFFFF);
    }
    return @intCast(u32, 0xFFFFFFFF);
}
// Task 11J fix round 1 (AMENDMENT 13): true when `v` fits the integer type
// `tid` (width + signedness). A non-integer target is never a fit. Used to
// reject an out-of-range or non-integer-target `@as`/`@intCast` in an enum
// initializer (e.g. `@as(f32,3)`, `@as(u8,300)`).
fn intValueFitsType(env: *TypeResolveEnv, tid: u32, v: i64) bool {
    if (tid == @intCast(u32, 0)) return false;
    if (@intCast(usize, tid) >= env.typereg.types_len) return false;
    if (!type_mod.typeRegistryIsInteger(env.typereg, tid)) return false;
    var wb: u32 = @intCast(u32, type_mod.typeRegistryIntWidthBits(env.typereg, tid));
    if (wb >= @intCast(u32, 64)) return true;
    if (wb == @intCast(u32, 0)) return false;
    if (type_mod.typeRegistryIntIsSigned(env.typereg, tid)) {
        var minv: i64 = -(@intCast(i64, 1) << @intCast(i64, wb - @intCast(u32, 1)));
        var maxv: i64 = (@intCast(i64, 1) << @intCast(i64, wb - @intCast(u32, 1))) - @intCast(i64, 1);
        if (v < minv or v > maxv) return false;
        return true;
    }
    if (v < @intCast(i64, 0)) return false;
    var vu: u64 = @bitCast(u64, v);
    var umax: u64 = (@intCast(u64, 1) << @intCast(u64, wb)) - @intCast(u64, 1);
    if (vu > umax) return false;
    return true;
}


pub fn evalConstI64Full(env: *TypeResolveEnv, node_idx: u32, depth: u32) ?i64 {
    // Task 11J: cycle guard, mirroring `evalConstU32Full`'s depth cap (16). A
    // self- or mutually-recursive const (`const X = X`) terminates as an
    // unfoldable value instead of recursing forever.
    if (depth > @intCast(u32, 16)) return null;
    if (node_idx == @intCast(u32, 0)) return null;
    var node = ast_mod.astStoreNodeAt(env.store, node_idx);
    if (node.kind == AstKind.int_literal) {
        return @bitCast(i64, ast_mod.astStoreIntValue(env.store, node_idx));
    }
    // Task 11J: a character literal is an 8-bit integer literal.
    if (node.kind == AstKind.char_literal) {
        return @bitCast(i64, ast_mod.astStoreIntValue(env.store, node_idx));
    }
    if (node.kind == AstKind.negate) {
        if (node.child_0 != @intCast(u32, 0)) {
            var nv_opt = evalConstI64Full(env, node.child_0, depth + @intCast(u32, 1));
            if (nv_opt) |nv| {
                var as_u: u64 = @bitCast(u64, nv);
                var neg_u: u64 = @intCast(u64, 0) - as_u;
                return @bitCast(i64, neg_u);
            }
        }
        return null;
    }
    // Task 11J: parenthesized expression.
    if (node.kind == AstKind.paren_expr) {
        return evalConstI64Full(env, node.child_0, depth + @intCast(u32, 1));
    }
    // Task 11J: integer binary/bitwise/shift expressions, mirroring
    // `comptime_eval.zig`'s `comptimeEvalBinOp` (div/mod by zero and a shift
    // count >= 64 are unfoldable). Computed on the 64-bit pattern so the
    // backing-width fit-check downstream is the authority on range.
    if (node.kind == AstKind.add or node.kind == AstKind.sub or
        node.kind == AstKind.mul or node.kind == AstKind.div or node.kind == AstKind.mod_op or
        node.kind == AstKind.bit_and or node.kind == AstKind.bit_or or node.kind == AstKind.bit_xor or
        node.kind == AstKind.shl or node.kind == AstKind.shr) {
        var l_opt = evalConstI64Full(env, node.child_0, depth + @intCast(u32, 1));
        var r_opt = evalConstI64Full(env, node.child_1, depth + @intCast(u32, 1));
        if (l_opt) |li| {
            if (r_opt) |ri| {
                var lv: u64 = @bitCast(u64, li);
                var rv: u64 = @bitCast(u64, ri);
                if (node.kind == AstKind.add) return @bitCast(i64, lv + rv);
                if (node.kind == AstKind.sub) return @bitCast(i64, lv - rv);
                if (node.kind == AstKind.mul) return @bitCast(i64, lv * rv);
                if (node.kind == AstKind.div) {
                    if (rv == @intCast(u64, 0)) return null;
                    return @bitCast(i64, lv / rv);
                }
                if (node.kind == AstKind.mod_op) {
                    if (rv == @intCast(u64, 0)) return null;
                    return @bitCast(i64, lv % rv);
                }
                if (node.kind == AstKind.bit_and) return @bitCast(i64, lv & rv);
                if (node.kind == AstKind.bit_or) return @bitCast(i64, lv | rv);
                if (node.kind == AstKind.bit_xor) return @bitCast(i64, lv ^ rv);
                if (node.kind == AstKind.shl) {
                    if (rv >= @intCast(u64, 64)) return null;
                    return @bitCast(i64, lv << rv);
                }
                if (rv >= @intCast(u64, 64)) return null;
                return @bitCast(i64, lv >> rv);
            }
        }
        return null;
    }
    if (node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(env.store, node_idx);
        var c_sym = symbolLookupAllModules(env, name_id);
        if (c_sym) |cs| {
            if ((cs.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                var c_decl = ast_mod.astStoreNodeAt(env.store, cs.decl_node);
                if (c_decl.child_1 != 0) {
                    return evalConstI64Full(env, c_decl.child_1, depth + @intCast(u32, 1));
                }
            }
        }
    }
    // Task 11J: a module-const reference through a field access (`mid.N`).
    if (node.kind == AstKind.field_access) {
        var fa_mod_id = evalConstModuleOfExpr(env, node.child_0);
        if (fa_mod_id != @intCast(u32, 0)) {
            var fa_field_id = ast_mod.astStoreNodePayload(env.store, node_idx);
            if (sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, fa_mod_id, fa_field_id)) |fa_sym| {
                if ((fa_sym.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                    var fa_decl = ast_mod.astStoreNodeAt(env.store, fa_sym.decl_node);
                    if (fa_decl.child_1 != 0) {
                        return evalConstI64Full(env, fa_decl.child_1, depth + @intCast(u32, 1));
                    }
                }
            }
        }
    }
    // Task 11J: integer-valued builtins. `@as`/`@intCast` fold their operand;
    // `@sizeOf`/`@alignOf`/`@bitSizeOf`/`@offsetOf`/`@bitOffsetOf` fold the
    // resolved type/field (named aggregates are complete post-layout). `~`, the
    // bool/float builtins (`@isWindows`, `@intToFloat`, `@floatCast`), function
    // calls, and enum-member references deliberately have no arm: they fall
    // through to `null` and are rejected by the caller (ERR_3055), never a
    // silent auto-increment.
    if (node.kind == AstKind.builtin_call) {
        var s_size: []const u8 = "@sizeOf";
        var size_id = interner_mod.stringInternerIntern(env.interner, s_size);
        var s_align: []const u8 = "@alignOf";
        var align_id = interner_mod.stringInternerIntern(env.interner, s_align);
        var s_bitsz: []const u8 = "@bitSizeOf";
        var bitsz_id = interner_mod.stringInternerIntern(env.interner, s_bitsz);
        var s_intc: []const u8 = "@intCast";
        var intc_id = interner_mod.stringInternerIntern(env.interner, s_intc);
        var s_as: []const u8 = "@as";
        var as_id = interner_mod.stringInternerIntern(env.interner, s_as);
        var s_off: []const u8 = "@offsetOf";
        var off_id = interner_mod.stringInternerIntern(env.interner, s_off);
        var s_bitoff: []const u8 = "@bitOffsetOf";
        var bitoff_id = interner_mod.stringInternerIntern(env.interner, s_bitoff);
        var bc_n = ast_mod.astStoreNodeExtraChildCount(env.store, node_idx);
        if (node.child_0 == intc_id or node.child_0 == as_id) {
            if (bc_n >= @intCast(u32, 2)) {
                // Task 11J fix round 1 (AMENDMENT 13): the target must be an
                // integer type and the folded value must fit it. `@as(f32,3)` is
                // not a valid enum field value and `@as(u8,300)` does not fit
                // u8; both are rejected (ERR_3055), never a silent value.
                var ct_tid = resolveTypeExprFull(env, ast_mod.astStoreNodeExtraChildAt(env.store, node_idx, @intCast(u32, 0)), depth + @intCast(u32, 1));
                if (ct_tid != type_mod.TYPE_UNDEFINED) {
                    var cv_opt = evalConstI64Full(env, ast_mod.astStoreNodeExtraChildAt(env.store, node_idx, @intCast(u32, 1)), depth + @intCast(u32, 1));
                    if (cv_opt) |cv| {
                        if (intValueFitsType(env, ct_tid, cv)) return cv;
                    }
                }
            }
            return null;
        }

        if (node.child_0 == size_id or node.child_0 == align_id or node.child_0 == bitsz_id) {
            if (bc_n >= @intCast(u32, 1)) {
                var bt_tid = resolveTypeExprFull(env, ast_mod.astStoreNodeExtraChildAt(env.store, node_idx, @intCast(u32, 0)), depth + @intCast(u32, 1));
                if (bt_tid != type_mod.TYPE_UNDEFINED) {
                    var bt_ty = env.typereg.types_items[@intCast(usize, bt_tid)];
                    if (bt_ty.state != @intCast(u8, 2) and bt_ty.kind == TypeKind.struct_type) {
                        _ = layoutEnsure(env.typereg, bt_tid, @intCast(u32, 0));
                        bt_ty = env.typereg.types_items[@intCast(usize, bt_tid)];
                    }
                    var bt_foldable = evalConstScalarKind(bt_ty.kind);
                    if (bt_ty.kind == TypeKind.struct_type) { bt_foldable = true; }
                    if (bt_ty.state == @intCast(u8, 2) and bt_foldable) {
                        if (node.child_0 == size_id) { return @intCast(i64, bt_ty.size); }
                        if (node.child_0 == align_id) { return @intCast(i64, bt_ty.alignment); }
                        var bt_bits: u32 = bt_ty.size * @intCast(u32, 8);
                        if (type_mod.typeRegistryIsInteger(env.typereg, bt_tid)) {
                            bt_bits = @intCast(u32, type_mod.typeRegistryIntWidthBits(env.typereg, bt_tid));
                        }
                        if (bt_ty.kind == TypeKind.enum_type) {
                            bt_bits = @intCast(u32, type_mod.typeRegistryIntWidthBits(env.typereg, type_mod.typeRegistryEnumBackingType(env.typereg, bt_tid)));
                        }
                        if (bt_ty.kind == TypeKind.bool_type) { bt_bits = @intCast(u32, 1); }
                        if (bt_ty.kind == TypeKind.struct_type and (bt_ty.flags & @intCast(u8, 0x10)) != @intCast(u8, 0)) {
                            bt_bits = @intCast(u32, type_mod.typeRegistryGetPackedTotalBits(env.typereg, bt_tid));
                        }
                        return @intCast(i64, bt_bits);
                    }
                }
            }
            return null;
        }
        if (node.child_0 == off_id or node.child_0 == bitoff_id) {
            if (bc_n >= @intCast(u32, 2)) {
                var ot_tid = resolveTypeExprFull(env, ast_mod.astStoreNodeExtraChildAt(env.store, node_idx, @intCast(u32, 0)), depth + @intCast(u32, 1));
                if (ot_tid != type_mod.TYPE_UNDEFINED) {
                    var ot_ty = env.typereg.types_items[@intCast(usize, ot_tid)];
                    if (ot_ty.state == @intCast(u8, 2) and ot_ty.kind == TypeKind.struct_type) {
                        var fields: []type_mod.FieldEntry = undefined;
                        type_mod.typeRegistryGetStructFields(env.typereg, ot_tid, &fields);
                        var packed_fields: []type_mod.PackedBitField = undefined;
                        var has_pk = type_mod.typeRegistryGetPackedBitFields(env.typereg, ot_tid, &packed_fields);
                        var fname_node = ast_mod.astStoreNodeAt(env.store, ast_mod.astStoreNodeExtraChildAt(env.store, node_idx, @intCast(u32, 1)));
                        if (fname_node.kind == AstKind.string_literal) {
                            var sv_idx = ast_mod.astStoreNodePayload(env.store, ast_mod.astStoreNodeExtraChildAt(env.store, node_idx, @intCast(u32, 1)));
                            var want_id = env.store.string_values.items[@intCast(usize, sv_idx)];
                            var fi: usize = 0;
                            while (fi < fields.len) : (fi += 1) {
                                if (fields[fi].name_id == want_id) {
                                    var bo: u64 = @intCast(u64, fields[fi].offset);
                                    if (has_pk) {
                                        var pk_bo: u64 = @intCast(u64, 0);
                                        if (fi < packed_fields.len) { pk_bo = @intCast(u64, packed_fields[fi].bit_offset); }
                                        if (node.child_0 == bitoff_id) { bo = pk_bo; } else { bo = pk_bo / @intCast(u64, 8); }
                                    } else {
                                        if (node.child_0 == bitoff_id) { bo = bo * @intCast(u64, 8); }
                                    }
                                    return @bitCast(i64, bo);
                                }
                            }
                        }
                    } else if (ot_ty.state == @intCast(u8, 2) and ot_ty.kind == TypeKind.packed_union_type) {
                        var u_fields: []type_mod.FieldEntry = undefined;
                        type_mod.typeRegistryGetUnionFields(env.typereg, ot_tid, &u_fields);
                        var fname_node2 = ast_mod.astStoreNodeAt(env.store, ast_mod.astStoreNodeExtraChildAt(env.store, node_idx, @intCast(u32, 1)));
                        if (fname_node2.kind == AstKind.string_literal) {
                            var sv_idx2 = ast_mod.astStoreNodePayload(env.store, ast_mod.astStoreNodeExtraChildAt(env.store, node_idx, @intCast(u32, 1)));
                            var want_id2 = env.store.string_values.items[@intCast(usize, sv_idx2)];
                            var fi2: usize = 0;
                            while (fi2 < u_fields.len) : (fi2 += 1) {
                                if (u_fields[fi2].name_id == want_id2) { return @intCast(i64, 0); }
                            }
                        }
                    }
                }
            }
            return null;
        }
        return null;
    }
    return null;
}


fn symbolLookupAllModules(env: *TypeResolveEnv, name_id: u32) ?*sym_mod.Symbol {
    var si: usize = 0;
    while (si < @intCast(usize, env.symbol_reg.tables_len)) : (si += 1) {
        var sym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, @intCast(u32, si), name_id);
        if (sym != null) return sym;
    }
    return null;
}
// Task 11J: the ONE shared enum-member walk (AMENDMENT 10: no duplicated
// fold/cascade logic). Computes every member value with a fresh `auto_val`
// cascade, exactly mirroring Zig's ordinal rule: `value = auto_val` unless an
// explicit initializer folds, then `auto_val = value + 1`. Used at symbol
// registration (append=true, strict=false), by the post-layout re-evaluation
// pass (append=false, strict=true), and as a check-only validation for
// function-local enums (check_only=true, which writes no registry storage).
// In strict mode an unfoldable explicit initializer (`out_fail_kind = 1`) or a
// duplicate tag value (`out_fail_kind = 2`) fails the walk; the caller emits
// ERR_3055.
pub fn enumMembersResolve(
    env: *TypeResolveEnv,
    enum_node: u32,
    append: bool,
    mstart: u32,
    strict: bool,
    check_only: bool,
    out_count: *u32,
    out_fail_node: *u32,
    out_fail_kind: *u32,
) bool {
    // check_only (function-local enums, whose type is not registered) keeps the
    // previously computed member values here instead of in `em_items`.
    var seen: [256]i64 = undefined;
    var children_n = ast_mod.astStoreNodeExtraChildCount(env.store, enum_node);
    var auto_val: i64 = @intCast(i64, 0);
    var k: u32 = 0;
    var i: usize = 0;
    while (i < children_n) : (i += 1) {
        var mnode = ast_mod.astStoreNodeAt(env.store, ast_mod.astStoreNodeExtraChildAt(env.store, enum_node, @intCast(u32, i)));
        if (mnode.kind != AstKind.field_decl) continue;
        var mval: i64 = auto_val;
        if (mnode.child_1 != @intCast(u32, 0)) {
            var ev_opt = evalConstI64Full(env, mnode.child_1, @intCast(u32, 0));
            if (ev_opt) |ev| {
                mval = ev;
            } else if (strict) {
                out_fail_node.* = mnode.child_1;
                out_fail_kind.* = @intCast(u32, 1);
                out_count.* = k;
                return false;
            }
        }
        if (strict) {
            var dj_lim: u32 = k;
            if (check_only and dj_lim > @intCast(u32, 256)) dj_lim = @intCast(u32, 256);
            var dj: u32 = 0;
            while (dj < dj_lim) : (dj += 1) {
                var prev: i64 = undefined;
                if (check_only) {
                    prev = seen[@intCast(usize, dj)];
                } else {
                    prev = env.typereg.em_items[@intCast(usize, mstart) + @intCast(usize, dj)].value;
                }
                if (prev == mval) {
                    out_fail_node.* = ast_mod.astStoreNodeExtraChildAt(env.store, enum_node, @intCast(u32, i));
                    out_fail_kind.* = @intCast(u32, 2);
                    out_count.* = k;
                    return false;
                }
            }
        }
        if (check_only) {
            if (k < @intCast(u32, 256)) { seen[@intCast(usize, k)] = mval; }
        } else if (append) {
            type_mod.emAppend(env.typereg, type_mod.EnumMember{
                .name_id = ast_mod.astStoreNodePayload(env.store, ast_mod.astStoreNodeExtraChildAt(env.store, enum_node, @intCast(u32, i))),
                .value = mval,
            });
        } else {
            env.typereg.em_items[@intCast(usize, mstart) + @intCast(usize, k)].value = mval;
        }
        k += 1;
        auto_val = mval + @intCast(i64, 1);
    }
    out_count.* = k;
    return true;
}


// Task 11J: post-layout enum re-evaluation (Option B, P1). Runs at the end of
// `phase_TypeResolution`, after `typeResolverResolve` has laid out every type
// and before `phase_FrontResolution`/`phase_SemanticAnalysis`, so every
// consumer of `em_items[].value` sees the corrected value. Re-walks each module
// enum decl with a fresh `auto_val` cascade (the shared walk) and overwrites
// the stored member values in place; an unfoldable explicit initializer or a
// duplicate tag becomes a clean ERR_3055 (rc=2, 0 `.c`), never a silent value.
pub fn enumReevaluateAll(
    store: *AstStore,
    typereg: *TypeRegistry,
    symbol_reg: *SymbolRegistry,
    interner: *StringInterner,
    module_reg: *mr_mod.ModuleRegistry,
    diag: *DiagnosticCollector,
) void {
    var mods = mr_mod.moduleRegistryGetModules(module_reg);
    var mi: usize = 0;
    while (mi < mods.len) : (mi += 1) {
        var ast_root = mods[mi].ast_root;
        if (ast_root == @intCast(u32, 0)) continue;
        var decls_n = ast_mod.astStoreNodeExtraChildCount(store, ast_root);
        var di: usize = 0;
        while (di < decls_n) : (di += 1) {
            var decl_idx = ast_mod.astStoreNodeExtraChildAt(store, ast_root, @intCast(u32, di));
            var dnode = ast_mod.astStoreNodeAt(store, decl_idx);
            var enum_node: u32 = @intCast(u32, 0);
            var enum_name_id: u32 = @intCast(u32, 0);
            if (dnode.kind == AstKind.enum_decl and dnode.child_1 != @intCast(u32, 0)) {
                enum_node = decl_idx;
                enum_name_id = dnode.child_0;
            } else if (dnode.kind == AstKind.var_decl and dnode.child_1 != @intCast(u32, 0)) {
                var inn = ast_mod.astStoreNodeAt(store, dnode.child_1);
                if (inn.kind == AstKind.enum_decl) {
                    enum_node = dnode.child_1;
                    enum_name_id = ast_mod.astStoreNodePayload(store, decl_idx);
                }
            }
            if (enum_node == @intCast(u32, 0)) continue;
            var key: u64 = @intCast(u64, mods[mi].id) * @intCast(u64, 4294967296) + @intCast(u64, enum_name_id);
            var tid_box: [1]u32 = [1]u32{ @intCast(u32, 0) };
            if (type_mod.nameCacheGet(typereg, key)) |t| { tid_box[0] = t; } else { continue; }
            var tid = tid_box[0];
            if (@intCast(usize, tid) >= typereg.types_len) continue;
            var ety = typereg.types_items[@intCast(usize, tid)];
            if (ety.kind != TypeKind.enum_type) continue;
            var ep = typereg.en_items[@intCast(usize, ety.payload_idx)];
            var env = TypeResolveEnv{
                .store = store, .typereg = typereg, .symbol_reg = symbol_reg, .interner = interner,
                .module_id = mods[mi].id, .source_file_id = mods[mi].source_file_id,
                .diag = diag, .local_consts = null, .local_types = null,
            };
            var count: u32 = 0;
            var fail_node: u32 = 0;
            var fail_kind: u32 = 0;
            if (!enumMembersResolve(&env, enum_node, false, ep.members_start, true, false, &count, &fail_node, &fail_kind)) {
                var fn_ = ast_mod.astStoreNodeAt(store, fail_node);
                var sp = fn_.span_start;
                var ep_ = sp + @intCast(u32, fn_.span_len);
                var msg: []const u8 = "enum member value is not a comptime-known integer expression";
                if (fail_kind == @intCast(u32, 2)) { msg = "duplicate enum tag value (tag values must be unique)"; }
                _ = diag_mod.diagnosticCollectorAdd(diag, @intCast(u8, 0),
                    @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3055_ENUM_VALUE_NOT_CONSTANT)),
                    mods[mi].source_file_id, sp, ep_, msg);
            }
        }
    }
}

// Task B2: intern the synthesized name `anon_<node_idx>` shared by every
// anonymous / function-local container type. A unique node-indexed name avoids
// the `(module_id, name_id)` collision two same-named locals would otherwise
// hit in `typeRegistryRegisterNamedType`; module 0 matches the pre-existing
// inline-struct arm so its emitted C stays byte-identical.
fn containerAnonNameId(env: *TypeResolveEnv, node_idx: u32) u32 {
    var idb: [12]u8 = undefined;
    var idl = itoa_mod.itoa(node_idx, idb[0..]);
    var ids: usize = @intCast(usize, 11) - @intCast(usize, idl);
    var nm: [24]u8 = undefined;
    nm[0] = @intCast(u8, 97); nm[1] = @intCast(u8, 110); nm[2] = @intCast(u8, 111); nm[3] = @intCast(u8, 110); nm[4] = @intCast(u8, 95);
    var di: usize = 0;
    while (di < @intCast(usize, idl)) : (di += 1) { nm[@intCast(usize, 5) + di] = idb[ids + di]; }
    var namelen: usize = @intCast(usize, 5) + @intCast(usize, idl);
    return interner_mod.stringInternerIntern(env.interner, nm[0..namelen]);
}

// Task B2: the four container decls that bind a first-class `type` value.
pub fn isContainerDeclKind(kind: AstKind) bool {
    return kind == AstKind.struct_decl or kind == AstKind.enum_decl or kind == AstKind.union_decl or kind == AstKind.error_set_decl;
}

// Task B2 fix round 1: strict validation of a local/inline enum declaration.
// Runs the ONE shared member walk (`enumMembersResolve`) in check-only strict
// mode so a duplicate tag value or an unfoldable initializer is a clean
// ERR_3055, exactly as for a module enum. Shared by `registerContainerType`
// (inline enums in ANY type position) and the semantic analyzer's
// `semanticAnalyzerCheckLocalEnum` (the binding / expression forms), so the two
// can never diverge. A null `env.diag` pass is a no-op.
pub fn validateLocalEnum(env: *TypeResolveEnv, enum_node: u32) void {
    if (enum_node == @intCast(u32, 0)) return;
    var diag = env.diag orelse return;
    if (!diag_mod.diagnosticCollectorMarkNodeOnce(diag, enum_node)) return;
    var count: u32 = 0;
    var fail_node: u32 = 0;
    var fail_kind: u32 = 0;
    if (!enumMembersResolve(env, enum_node, false, @intCast(u32, 0), true, true, &count, &fail_node, &fail_kind)) {
        var fn_ = ast_mod.astStoreNodeAt(env.store, fail_node);
        var sp = fn_.span_start;
        var ep = sp + @intCast(u32, fn_.span_len);
        var msg: []const u8 = "enum member value is not a comptime-known integer expression";
        if (fail_kind == @intCast(u32, 2)) { msg = "duplicate enum tag value (tag values must be unique)"; }
        _ = diag_mod.diagnosticCollectorAdd(diag, @intCast(u8, 0),
            @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3055_ENUM_VALUE_NOT_CONSTANT)),
            env.source_file_id, sp, ep, msg);
    }
}

// Task B2: register one container type (struct/enum/union/error-set) under its
// synthesized `anon_<node_idx>` name and populate its payload, returning the
// TypeId. Struct/union field types are resolved directly here (the module-only
// `resolveAggregateFieldTypesAll` pass never visits function-local/inline
// aggregates, and `populateTypePayload` leaves their fields `VOID`); enum and
// error-set payloads have no such post-pass dependency and reuse the shared
// registrator logic. Idempotent across passes via the name cache.
pub fn registerContainerType(env: *TypeResolveEnv, node_idx: u32, kind: AstKind, depth: u32) type_mod.TypeId {
    var node = ast_mod.astStoreNodeAt(env.store, node_idx);
    // Task B2 fix round 1: validate an inline enum BEFORE the name-cache
    // short-circuit, so an enum first seen in a diag-less pass is still
    // validated when a later diag-carrying pass resolves it.
    if (kind == AstKind.enum_decl) {
        validateLocalEnum(env, node_idx);
    }
    var name_id = containerAnonNameId(env, node_idx);
    var existing = type_mod.nameCacheGet(env.typereg, @intCast(u64, name_id));
    if (existing) |e| return e;
    var type_kind: type_mod.TypeKind = switch (kind) {
        AstKind.struct_decl => type_mod.TypeKind.struct_type,
        AstKind.enum_decl => type_mod.TypeKind.enum_type,
        AstKind.union_decl => if ((@intCast(u16, node.flags) & @intCast(u16, 0x10)) != 0) type_mod.TypeKind.packed_union_type else if ((@intCast(u16, node.flags) & 1) != 0) type_mod.TypeKind.tagged_union_type else type_mod.TypeKind.union_type,
        AstKind.error_set_decl => type_mod.TypeKind.error_set_type,
        else => type_mod.TypeKind.void_type,
    };
    var tid = type_mod.typeRegistryRegisterNamedType(env.typereg, @intCast(u32, 0), name_id, type_kind);
    if ((kind == AstKind.struct_decl or kind == AstKind.union_decl) and (@intCast(u16, node.flags) & @intCast(u16, 0x10)) != @intCast(u16, 0)) {
        type_mod.typeRegistrySetPacked(env.typereg, tid);
    }
    if (kind == AstKind.struct_decl) {
        if (ast_mod.astStoreNodePayload(env.store, node_idx) != @intCast(u32, 0)) {
            var sd_children_n = ast_mod.astStoreNodeExtraChildCount(env.store, node_idx);
            var sd_fty: [32]u32 = undefined;
            var sd_fnm: [32]u32 = undefined;
            var sd_fc: usize = 0;
            var sd_i: usize = 0;
            while (sd_i < @intCast(usize, sd_children_n) and sd_fc < @intCast(usize, 32)) : (sd_i += 1) {
                var sd_child = ast_mod.astStoreNodeExtraChildAt(env.store, node_idx, @intCast(u32, sd_i));
                var sd_fd = ast_mod.astStoreNodeAt(env.store, sd_child);
                if (sd_fd.kind == AstKind.field_decl) {
                    sd_fty[sd_fc] = resolveTypeExprFull(env, sd_fd.child_0, depth + @intCast(u32, 1));
                    sd_fnm[sd_fc] = ast_mod.astStoreNodePayload(env.store, sd_child);
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
                    .fields_start = @intCast(u32, sd_fstart),
                    .fields_count = @intCast(u16, sd_fc),
                });
                var sd_st_idx: u32 = @intCast(u32, env.typereg.st_len - @intCast(usize, 1));
                var sd_ty = env.typereg.types_items[@intCast(usize, tid)];
                sd_ty.payload_idx = sd_st_idx;
                env.typereg.types_items[@intCast(usize, tid)] = sd_ty;
            }
        }
    } else if (kind == AstKind.union_decl) {
        if (ast_mod.astStoreNodePayload(env.store, node_idx) != @intCast(u32, 0)) {
            var un_children_n = ast_mod.astStoreNodeExtraChildCount(env.store, node_idx);
            if (un_children_n != 0) {
                var un_fty: [32]u32 = undefined;
                var un_fnm: [32]u32 = undefined;
                var un_fc: usize = 0;

                var un_i: usize = 0;
                while (un_i < @intCast(usize, un_children_n) and un_fc < @intCast(usize, 32)) : (un_i += 1) {
                    var un_child = ast_mod.astStoreNodeExtraChildAt(env.store, node_idx, @intCast(u32, un_i));
                    var un_fd = ast_mod.astStoreNodeAt(env.store, un_child);
                    if (un_fd.kind == AstKind.field_decl) {
                        un_fty[un_fc] = resolveTypeExprFull(env, un_fd.child_0, depth + @intCast(u32, 1));
                        un_fnm[un_fc] = ast_mod.astStoreNodePayload(env.store, un_child);
                        un_fc += 1;
                    }
                }
                // Task B2 fix round 1: capture `fields_start` AFTER the resolve
                // loop — resolving a nested aggregate field appends its own `fe`
                // entries, so capturing before would point the union payload into
                // the nested type's fields (mirrors the struct branch).
                var un_fstart: u32 = @intCast(u32, env.typereg.fe_len);
                var un_j: usize = 0;
                while (un_j < un_fc) : (un_j += 1) {
                    type_mod.feAppend(env.typereg, type_mod.FieldEntry{
                        .name_id = un_fnm[un_j],
                        .type_id = un_fty[un_j],
                        .offset = @intCast(u32, 0),
                    });
                }
                if ((@intCast(u16, node.flags) & 1) != 0) {
                    type_mod.tuAppend(env.typereg, type_mod.TaggedUnionPayload{
                        .tag_type = type_mod.TYPE_U32,
                        .fields_start = @intCast(u32, un_fstart),
                        .fields_count = @intCast(u16, un_fc),
                    });
                    var un_tu_idx: u32 = @intCast(u32, env.typereg.tu_len - @intCast(usize, 1));
                    var un_tu_ty = env.typereg.types_items[@intCast(usize, tid)];
                    un_tu_ty.payload_idx = un_tu_idx;
                    env.typereg.types_items[@intCast(usize, tid)] = un_tu_ty;
                } else {
                    type_mod.unAppend(env.typereg, type_mod.UnionPayload{
                        .fields_start = @intCast(u32, un_fstart),
                        .fields_count = @intCast(u16, un_fc),
                        .tag_type = type_mod.TYPE_VOID,
                    });
                    var un_un_idx: u32 = @intCast(u32, env.typereg.un_len - @intCast(usize, 1));
                    var un_un_ty = env.typereg.types_items[@intCast(usize, tid)];
                    un_un_ty.payload_idx = un_un_idx;
                    env.typereg.types_items[@intCast(usize, tid)] = un_un_ty;
                }
            }
        }
    } else {
        sym_reg.populateTypePayload(env.typereg, env.store, kind, node_idx, env.symbol_reg);
    }
    return tid;
}

pub fn resolveTypeExprFull(env: *TypeResolveEnv, node_idx: u32, depth: u32) type_mod.TypeId {
    if (depth > @intCast(u32, 16)) return type_mod.TYPE_UNDEFINED;
    var node = ast_mod.astStoreNodeAt(env.store, node_idx);
    var rtd_nm: []const u8 = "RTD:n"; pal_mod.markerWriteInt(rtd_nm, node_idx); var rtd_km: []const u8 = "RTD:k"; pal_mod.markerWriteInt(rtd_km, @intCast(u32, @enumToInt(node.kind)));
    if (node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(env.store, node_idx);
        var opm4_m: []const u8 = "OPTVOID:id"; pal_mod.markerWriteInt(opm4_m, name_id);
        // Task B2: a function-local named type shadows module-level names inside
        // the enclosing function body. Consulted before every module table so a
        // local type used in a compound type expression resolves to its tid.
        if (env.local_types) |lts| {
            if (localTypeScopeLookup(lts, name_id)) |lt| return lt;
        }
        var text = interner_mod.stringInternerGet(env.interner, name_id);
        var canonical_id = interner_mod.stringInternerIntern(env.interner, text);
        if (env.module_id != MODULE_ID_NONE) {
            var ck_cur: u64 = @intCast(u64, env.module_id) * @intCast(u64, 4294967296) + @intCast(u64, canonical_id);
            var tc_cur = type_mod.nameCacheGet(env.typereg, ck_cur);
            if (tc_cur) |t| return t;
        }
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
        if (env.module_id != MODULE_ID_NONE) {
            var sym_cur = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, env.module_id, name_id);
            if (sym_cur) |s| {
                if (s.type_id != @intCast(u32, 0)) {
                    return s.type_id;
                }
            }
        }
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
        var arbu: bool = false;
        var arbw = type_mod.parseArbIntWidth(text, &arbu);
        if (arbw != @intCast(u32, 0)) {
            return type_mod.typeRegistryGetOrCreateArbInt(env.typereg, text);
        }
        return type_mod.TYPE_UNDEFINED;
    }
    if (node.kind == AstKind.struct_decl or node.kind == AstKind.enum_decl or node.kind == AstKind.union_decl) {
        return registerContainerType(env, node_idx, node.kind, depth);
    }
    if (node.kind == AstKind.field_access) {
        var fah_matched: u8 = @intCast(u8, 0);
        var base_type = resolveTypeExprFull(env, node.child_0, depth + @intCast(u32, 1));
        if (base_type == type_mod.TYPE_UNDEFINED) {
            var base_node = ast_mod.astStoreNodeAt(env.store, node.child_0);
            if (base_node.kind == AstKind.ident_expr) {
                var base_name_id = ast_mod.astStoreIdentifier(env.store, node.child_0);
                var smi: usize = 0;
                while (smi < @intCast(usize, env.symbol_reg.tables_len)) : (smi += 1) {
                    var base_sym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, @intCast(u32, smi), base_name_id);
                    if (base_sym) |bs| {
                        if (bs.kind == sym_mod.SymbolKind.module) {
                            var mod_id = bs.module_id;
                            var payload_sym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, mod_id, ast_mod.astStoreNodePayload(env.store, node_idx));
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
            var sym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, mod_id, ast_mod.astStoreNodePayload(env.store, node_idx));
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
    if (node.kind == AstKind.error_set_decl) {
        var esd_start_box: [1]u32 = [1]u32{ @intCast(u32, env.typereg.xn_len) };
        var esd_count_box: [1]u16 = [1]u16{ @intCast(u16, 0) };
        if (ast_mod.astStoreNodePayload(env.store, node_idx) != @intCast(u32, 0)) {
            var esd_children_n = ast_mod.astStoreNodeExtraChildCount(env.store, node_idx);
            esd_count_box[0] = @intCast(u16, esd_children_n);
            var esd_i: usize = 0;
            while (esd_i < @intCast(usize, esd_children_n)) : (esd_i += 1) {
                type_mod.xnAppend(env.typereg, ast_mod.astStoreNodeExtraChildAt(env.store, node_idx, @intCast(u32, esd_i)));
            }
        }
        return type_mod.typeRegistryGetOrCreateErrorSet(env.typereg, esd_start_box[0], esd_count_box[0]);
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
            eu_es_box[0] = @intCast(u32, 0);
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
        if (ast_mod.astStoreNodePayload(env.store, node_idx) != @intCast(u32, 0)) {
            var fnt_extra_n = ast_mod.astStoreNodeExtraChildCount(env.store, node_idx);
            var fnt_i: usize = @intCast(usize, 0);
            while (fnt_i < @intCast(usize, fnt_extra_n) and fnt_pc < @intCast(usize, 16)) : (fnt_i += @intCast(usize, 1)) {
                var fnt_pt = resolveTypeExprFull(env, ast_mod.astStoreNodeExtraChildAt(env.store, node_idx, @intCast(u32, fnt_i)), depth + @intCast(u32, 1));
                if (fnt_pt == type_mod.TYPE_UNDEFINED) return type_mod.TYPE_UNDEFINED;
                fnt_ptypes[fnt_pc] = fnt_pt;
                fnt_pc += @intCast(usize, 1);
            }
        }
        var fnt_conv: u8 = @intCast(u8, 0);
        if ((node.flags & @intCast(u8, 1)) != @intCast(u8, 0)) fnt_conv = @intCast(u8, 1);
        var fnt_nb: [96]u8 = undefined;
        var fnt_np: usize = @intCast(usize, 0);
        var fnt_pre: []const u8 = "fnt_";
        if (fnt_conv == @intCast(u8, 1)) fnt_pre = "fnts_";
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
        var fnt_tid = type_mod.typeRegistryGetOrCreateFn(env.typereg, fnt_name_id, @intCast(u32, 0), @intCast(u8, 0), @intCast(u8, 0), @intCast(u32, fnt_pstart), @intCast(u16, fnt_pc), fnt_ret_box[0], fnt_conv);
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
            var is_volatile: bool = (node.flags & @intCast(u8, 2)) != @intCast(u8, 0);
            if (node.kind == AstKind.ptr_type) {
                var ptr_tid = type_mod.typeRegistryGetOrCreatePtrQ(env.typereg, child_type, is_const, is_volatile);
                var ppm: []const u8 = "P"; pal_mod.markerWrite(ppm);
                var ppb: [10]u8 = undefined; var ppl = itoa_mod.itoa(ptr_tid, ppb[0..]); var pps: usize = @intCast(usize, 9) - @intCast(usize, ppl); pal_mod.markerWrite(ppb[pps..@intCast(usize, 9)]);
                var pnl: []const u8 = "\n"; pal_mod.markerWrite(pnl);
                return ptr_tid;
            } else {
                var ptr_tid2 = type_mod.typeRegistryGetOrCreateManyPtrQ(env.typereg, child_type, is_const, is_volatile);
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
                var sz_node = ast_mod.astStoreNodeAt(env.store, node.child_1);
                var arr_len: u32 = @intCast(u32, 0);
                var arr_resolved: bool = false;
                if (sz_node.kind == AstKind.int_literal) {
                    arr_len = @intCast(u32, ast_mod.astStoreIntValue(env.store, node.child_1));
                    arr_resolved = true;
                } else if (sz_node.kind == AstKind.add or sz_node.kind == AstKind.sub) {
                    var lhs = evalConstU32Full(env, sz_node.child_0, @intCast(u32, 0));
                    var rhs = evalConstU32Full(env, sz_node.child_1, @intCast(u32, 0));
                    if (lhs != @intCast(u32, 0xFFFFFFFF) and rhs != @intCast(u32, 0xFFFFFFFF)) {
                        arr_resolved = true;
                        if (sz_node.kind == AstKind.add) { arr_len = lhs + rhs; }
                        else { arr_len = lhs - rhs; }
                    }
                } else if (sz_node.kind == AstKind.mul or sz_node.kind == AstKind.div or sz_node.kind == AstKind.mod_op) {
                    var lhs = evalConstU32Full(env, sz_node.child_0, @intCast(u32, 0));
                    var rhs = evalConstU32Full(env, sz_node.child_1, @intCast(u32, 0));
                    if (lhs != @intCast(u32, 0xFFFFFFFF) and rhs != @intCast(u32, 0xFFFFFFFF) and rhs != @intCast(u32, 0)) {
                        arr_resolved = true;
                        if (sz_node.kind == AstKind.mul) { arr_len = lhs * rhs; }
                        else if (sz_node.kind == AstKind.div) { arr_len = lhs / rhs; }
                        else { arr_len = lhs % rhs; }
                    }
                } else if (sz_node.kind == AstKind.ident_expr) {
                    var al = evalConstU32Full(env, node.child_1, @intCast(u32, 0));
                    if (al != @intCast(u32, 0xFFFFFFFF)) {
                        arr_len = al;
                        arr_resolved = true;
                    }
                } else {
                    // Task 2b-F (#1): any other const-foldable size expression
                    // (notably a module-member `field_access` such as
                    // `[mid.leaf.HEADER_SIZE]`) is folded by the const evaluator.
                    var alf = evalConstU32Full(env, node.child_1, @intCast(u32, 0));
                    if (alf != @intCast(u32, 0xFFFFFFFF)) {
                        arr_len = alf;
                        arr_resolved = true;
                    }
                }
                var t2m: []const u8 = "T2L"; pal_mod.markerWrite(t2m);
                var t2b: [20]u8 = undefined;
                var t2l = itoa_mod.itoa(arr_len, t2b[0..]);
                var t2s: usize = @intCast(usize, 19) - @intCast(usize, t2l);
                pal_mod.markerWrite(t2b[t2s..@intCast(usize, 19)]);
                if (arr_resolved) {
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
                // Task 2c-F: the size expression could not be const-folded.
                // Emit a hard error (deduped per node) instead of silently
                // returning TYPE_UNDEFINED and letting invalid C be emitted
                // downstream. `[_]T` (inferred length) is handled by the
                // array-init path, not here, so it is never an error.
                var sz_is_inferred: bool = false;
                if (sz_node.kind == AstKind.ident_expr) {
                    var sz_name = ast_mod.astStoreIdentifier(env.store, node.child_1);
                    var sz_text = interner_mod.stringInternerGet(env.interner, sz_name);
                    if (sz_text.len == @intCast(usize, 1) and sz_text[0] == @intCast(u8, '_')) { sz_is_inferred = true; }
                }
                if (!sz_is_inferred) {
                    if (env.diag) |dg| {
                        if (diag_mod.diagnosticCollectorMarkNodeOnce(dg, node_idx)) {
                            var asn_msg: []const u8 = "array size is not a constant expression";
                            _ = diag_mod.diagnosticCollectorAdd(dg, @intCast(u8, 0),
                                @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3050_ARRAY_SIZE_NOT_CONSTANT)),
                                env.source_file_id, sz_node.span_start,
                                sz_node.span_start + @intCast(u32, sz_node.span_len), asn_msg);
                        }
                    }
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
    env.module_id = mod_id;
    var decl = ast_mod.astStoreNodeAt(env.store, decl_idx);
    var init = ast_mod.astStoreNodeAt(env.store, decl.child_1);
    var spid = type_mod.nameCacheGet(env.typereg, (@intCast(u64, mod_id) << @intCast(u64, 32)) | @intCast(u64, ast_mod.astStoreNodePayload(env.store, decl_idx)));
    if (spid) |stid| {
        var sty = env.typereg.types_items[@intCast(usize, stid)];
        var fchildren_n = ast_mod.astStoreNodeExtraChildCount(env.store, decl.child_1);
        var fi2: usize = 0;
        if (sty.kind == type_mod.TypeKind.struct_type) {
            var sp = env.typereg.st_items[@intCast(usize, sty.payload_idx)];
            while (fi2 < @intCast(usize, sp.fields_count)) : (fi2 += 1) {
                var fchild = ast_mod.astStoreNodeExtraChildAt(env.store, decl.child_1, @intCast(u32, fi2));
                var fd = ast_mod.astStoreNodeAt(env.store, fchild);
                if (fd.kind == AstKind.field_decl and fd.child_0 != 0) {
                    var ft = resolveTypeExprFull(env, fd.child_0, @intCast(u32, 0));
                    var b2_pn: []const u8 = "B2:p"; pal_mod.markerWrite(b2_pn);
                    var b2_pb: [20]u8 = undefined; var b2_pl = itoa_mod.itoa(ast_mod.astStoreNodePayload(env.store, fchild), b2_pb[0..]); var b2_ps: usize = @intCast(usize, 19) - @intCast(usize, b2_pl); pal_mod.markerWrite(b2_pb[b2_ps..@intCast(usize, 19)]);
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
                var fd = ast_mod.astStoreNodeAt(env.store, ast_mod.astStoreNodeExtraChildAt(env.store, decl.child_1, @intCast(u32, fi2)));
                if (fd.kind == AstKind.field_decl and fd.child_0 != 0) {
                    var ft = resolveTypeExprFull(env, fd.child_0, @intCast(u32, 0));
                    var dft_nm: []const u8 = "DFT:n"; pal_mod.markerWriteInt(dft_nm, @intCast(u32, fi2));
                    var dft_tm: []const u8 = "DFT:t"; pal_mod.markerWriteInt(dft_tm, ft);
                    var b2_pn: []const u8 = "B2:p"; pal_mod.markerWrite(b2_pn);
                    var b2_pb: [20]u8 = undefined; var b2_pl = itoa_mod.itoa(ast_mod.astStoreNodePayload(env.store, ast_mod.astStoreNodeExtraChildAt(env.store, decl.child_1, @intCast(u32, fi2))), b2_pb[0..]); var b2_ps: usize = @intCast(usize, 19) - @intCast(usize, b2_pl); pal_mod.markerWrite(b2_pb[b2_ps..@intCast(usize, 19)]);
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
        } else if (sty.kind == type_mod.TypeKind.union_type or sty.kind == type_mod.TypeKind.packed_union_type) {
            var up = env.typereg.un_items[@intCast(usize, sty.payload_idx)];
            while (fi2 < @intCast(usize, up.fields_count)) : (fi2 += 1) {
                var fd = ast_mod.astStoreNodeAt(env.store, ast_mod.astStoreNodeExtraChildAt(env.store, decl.child_1, @intCast(u32, fi2)));
                if (fd.kind == AstKind.field_decl and fd.child_0 != 0) {
                    var ft = resolveTypeExprFull(env, fd.child_0, @intCast(u32, 0));
                    if (ft != type_mod.TYPE_UNDEFINED) {
                        env.typereg.fe_items[@intCast(usize, up.fields_start) + fi2].type_id = ft;
                    }
                }
            }
        }
    }
}

fn varDeclInitNeedsNameCache(init_kind: AstKind) bool {
    if (init_kind == AstKind.struct_decl) return false;
    if (init_kind == AstKind.union_decl) return false;
    if (init_kind == AstKind.enum_decl) return false;
    if (init_kind == AstKind.error_set_decl) return false;
    if (init_kind == AstKind.ident_expr) return false;
    if (init_kind == AstKind.import_expr) return false;
    if (init_kind == AstKind.fn_decl) return false;
    return true;
}


fn resolveNamedTypeExpressions(env: *TypeResolveEnv, mods: []mr_mod.ModuleEntry) void {
    var ci: usize = 0;
    while (ci < mods.len) : (ci += 1) {
        var cr = mods[ci].ast_root;
        if (cr == @intCast(u32, 0)) continue;
        env.module_id = mods[ci].id;
        env.source_file_id = mods[ci].source_file_id;
        var crn = ast_mod.astStoreNodeAt(env.store, cr);
        var cd_n = ast_mod.astStoreNodeExtraChildCount(env.store, cr);
        var cdi: usize = 0;
        while (cdi < @intCast(usize, cd_n)) : (cdi += 1) {
            var cd_i = ast_mod.astStoreNodeExtraChildAt(env.store, cr, @intCast(u32, cdi));
            var cdcl = ast_mod.astStoreNodeAt(env.store, cd_i);
            if (cdcl.kind == AstKind.var_decl and cdcl.child_1 != @intCast(u32, 0)) {
                var cdinit = ast_mod.astStoreNodeAt(env.store, cdcl.child_1);
                if (varDeclInitNeedsNameCache(cdinit.kind)) {
                    var cdtype = resolveTypeExprFull(env, cdcl.child_1, @intCast(u32, 0));
                    if (cdtype != type_mod.TYPE_UNDEFINED) {
                        var ck: u64 = @intCast(u64, mods[ci].id) * @intCast(u64, 4294967296) + @intCast(u64, ast_mod.astStoreNodePayload(env.store, cd_i));
                        type_mod.nameCachePut(env.typereg, ck, cdtype);
                        var cdsym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, mods[ci].id, ast_mod.astStoreNodePayload(env.store, cd_i));
                        if (cdsym) |sp| { sp.type_id = cdtype; }
                    }
                }
            }
        }
    }
}

fn resolveImportFieldAlias(env: *TypeResolveEnv, module_reg: *mr_mod.ModuleRegistry,
    importer_mod_id: u32, target_mod_id: u32, field_name_id: u32, depth: u32) u32 {
    if (depth > @intCast(u32, 8)) return type_mod.TYPE_UNDEFINED;
    var fs = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, target_mod_id, field_name_id);
    if (fs) |fss| {
        if (fss.type_id != @intCast(u32, 0)) return fss.type_id;
        var fd = ast_mod.astStoreNodeAt(env.store, fss.decl_node);
        if (fd.kind != AstKind.var_decl) return type_mod.TYPE_UNDEFINED;
        var fi = ast_mod.astStoreNodeAt(env.store, fd.child_1);
        if (fi.kind != AstKind.field_access) return type_mod.TYPE_UNDEFINED;
        var fb = ast_mod.astStoreNodeAt(env.store, fi.child_0);
        if (fb.kind != AstKind.import_expr) return type_mod.TYPE_UNDEFINED;
        var t2 = mr_mod.moduleRegistryPathToIdGet(module_reg, ast_mod.astStoreNodePayload(env.store, fi.child_0));
        if (t2) |m2| return resolveImportFieldAlias(env, module_reg, importer_mod_id, m2, ast_mod.astStoreNodePayload(env.store, fd.child_1), depth + @intCast(u32, 1));
    }
    return type_mod.TYPE_UNDEFINED;
}

fn resolveImportFieldAliases(env: *TypeResolveEnv, mods: []mr_mod.ModuleEntry, module_reg: *mr_mod.ModuleRegistry) void {
    var mi: usize = 0;
    while (mi < mods.len) : (mi += 1) {
        var root = mods[mi].ast_root;
        if (root == @intCast(u32, 0)) continue;
        var rnode = ast_mod.astStoreNodeAt(env.store, root);
        var decls_n = ast_mod.astStoreNodeExtraChildCount(env.store, root);
        var di: usize = 0;
        while (di < @intCast(usize, decls_n)) : (di += 1) {
            var decl_idx = ast_mod.astStoreNodeExtraChildAt(env.store, root, @intCast(u32, di));
            var decl = ast_mod.astStoreNodeAt(env.store, decl_idx);
            if (decl.kind != AstKind.var_decl) { continue; }
            if (decl.child_1 == @intCast(u32, 0)) { continue; }
            var init = ast_mod.astStoreNodeAt(env.store, decl.child_1);
            if (init.kind != AstKind.field_access) { continue; }
            var base = ast_mod.astStoreNodeAt(env.store, init.child_0);
            if (base.kind != AstKind.import_expr) { continue; }
            var target = mr_mod.moduleRegistryPathToIdGet(module_reg, ast_mod.astStoreNodePayload(env.store, init.child_0));
            if (target) |mtid| {
                var resolved = resolveImportFieldAlias(env, module_reg, mods[mi].id, mtid, ast_mod.astStoreNodePayload(env.store, decl.child_1), @intCast(u32, 0));
                if (resolved != type_mod.TYPE_UNDEFINED) {
                    var sym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, mods[mi].id, ast_mod.astStoreNodePayload(env.store, decl_idx));
                    if (sym) |sp| {
                        sp.type_id = resolved;
                    }
                    var ck: u64 = @intCast(u64, mods[mi].id) * @intCast(u64, 4294967296) + @intCast(u64, ast_mod.astStoreNodePayload(env.store, decl_idx));
                    type_mod.nameCachePut(env.typereg, ck, resolved);
                }
            }

        }
    }
}

fn resolveAggregateFieldTypesAll(env: *TypeResolveEnv, mods: []mr_mod.ModuleEntry) void {
    var mi: usize = 0;
    while (mi < mods.len) : (mi += 1) {
        var root = mods[mi].ast_root;
        if (root == @intCast(u32, 0)) continue;
        env.source_file_id = mods[mi].source_file_id;
        var rnode = ast_mod.astStoreNodeAt(env.store, root);
        var decls_n = ast_mod.astStoreNodeExtraChildCount(env.store, root);
        var di: usize = 0;
        while (di < @intCast(usize, decls_n)) : (di += 1) {
            var decl_idx = ast_mod.astStoreNodeExtraChildAt(env.store, root, @intCast(u32, di));
            var decl = ast_mod.astStoreNodeAt(env.store, decl_idx);
            if (decl.kind == AstKind.var_decl and decl.child_1 != 0) {
                var init = ast_mod.astStoreNodeAt(env.store, decl.child_1);
                if (init.kind == AstKind.struct_decl or init.kind == AstKind.union_decl) {
                    resolveDeclAggregateFieldTypes(env, mods[mi].id, decl_idx);
                }
            }
        }
    }
}

fn resolveFnSignatures(env: *TypeResolveEnv, mods: []mr_mod.ModuleEntry, resolved_types: *rtt_mod.ResolvedTypeTable) void {
    var mi: usize = 0;
    while (mi < mods.len) : (mi += 1) {
        var root = mods[mi].ast_root;
        if (root == @intCast(u32, 0)) continue;
        env.module_id = mods[mi].id;
        env.source_file_id = mods[mi].source_file_id;
        var rnode = ast_mod.astStoreNodeAt(env.store, root);
        var decls_n = ast_mod.astStoreNodeExtraChildCount(env.store, root);
        var di: usize = 0;
        while (di < @intCast(usize, decls_n)) : (di += 1) {
            var decl_idx = ast_mod.astStoreNodeExtraChildAt(env.store, root, @intCast(u32, di));
            var decl = ast_mod.astStoreNodeAt(env.store, decl_idx);
            if (decl.kind == AstKind.fn_decl) {
                var proto = env.store.fn_protos.items[@intCast(usize, ast_mod.astStoreNodePayload(env.store, decl_idx))];
                {
                    var sym_check = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, mods[mi].id, proto.name_id);
                    if (sym_check) |sc| {
                        if (sc.type_id != @intCast(u32, 0)) continue;
                    }
                }
                var rt_box: [1]u32 = [1]u32{type_mod.TYPE_VOID};
                if (proto.return_type_node != 0) {
                    var rtype = resolveTypeExprFull(env, proto.return_type_node, @intCast(u32, 0));
                    if (rtype != type_mod.TYPE_UNDEFINED) {
                        rt_box[0] = rtype;
                        rtt_mod.resolvedTypeTableSet(resolved_types, proto.return_type_node, rtype);
                    }
                }
                var is_ext: u8 = @intCast(u8, 0);
                if ((decl.flags & @intCast(u8, 4)) != @intCast(u8, 0)) { is_ext = @intCast(u8, 1); }
                var is_variadic: u8 = @intCast(u8, 0);
                if ((decl.flags & @intCast(u8, 1)) != @intCast(u8, 0)) { is_variadic = @intCast(u8, 1); }
                var ptypes_buf: [MAX_FN_PARAMS]u32 = undefined;
                var ptypes_n: usize = @intCast(usize, 0);
                // Loud guard: never silently truncate a function's parameter
                // list. `typeRegistryGetOrCreateFn` below still receives the
                // true `proto.params_count`, so a truncated buffer would build a
                // wrong function type.
                if (@intCast(usize, proto.params_count) > MAX_FN_PARAMS) {
                    @panic("async/type_resolver: function parameter count exceeds MAX_FN_PARAMS (64)");
                }
                if (proto.params_count > @intCast(u16, 0)) {
                    var p_payload: u64 = (@intCast(u64, proto.params_start) << @intCast(u64, 32)) | @intCast(u64, proto.params_count);
                    var pnodes_n = ast_mod.astStoreGetExtraChildCount(env.store, p_payload);
                    var pi: usize = 0;
                    while (pi < @intCast(usize, pnodes_n)) : (pi += 1) {
                        var pnode = ast_mod.astStoreNodeAt(env.store, ast_mod.astStoreGetExtraChildAt(env.store, p_payload, @intCast(u32, pi)));
                        if (pnode.child_0 != 0) {
                            var ptype = resolveTypeExprFull(env, pnode.child_0, @intCast(u32, 0));
                            // Belt-and-braces: unreachable given the pre-loop
                            // guard, but an overflow here would still yield a
                            // wrong function type, so fail loud.
                            if (ptypes_n >= MAX_FN_PARAMS) {
                                @panic("async/type_resolver: function parameter count exceeds MAX_FN_PARAMS (64)");
                            }
                            ptypes_buf[ptypes_n] = ptype;
                            ptypes_n += @intCast(usize, 1);
                            if (ptype != type_mod.TYPE_UNDEFINED) {
                                rtt_mod.resolvedTypeTableSet(resolved_types, pnode.child_0, ptype);
                            }
                        }
                    }
                }
                var fn_start: u32 = @intCast(u32, env.typereg.xt_len);
                var pf: usize = @intCast(usize, 0);
                while (pf < ptypes_n) : (pf += 1) {
                    type_mod.xtAppend(env.typereg, ptypes_buf[pf]);
                }
                var tid = type_mod.typeRegistryGetOrCreateFn(env.typereg, proto.name_id, mods[mi].id, is_ext, is_variadic, fn_start, proto.params_count, rt_box[0], proto.call_conv);
                rtt_mod.resolvedTypeTableSet(resolved_types, decl_idx, tid);
                var sym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, mods[mi].id, proto.name_id);
                if (sym) |sp| {
                    sp.type_id = tid;
                }
            } else if (decl.kind == AstKind.var_decl and decl.child_0 != 0) {
                var vtype = resolveTypeExprFull(env, decl.child_0, @intCast(u32, 0));
                if (vtype != type_mod.TYPE_UNDEFINED) {
                    rtt_mod.resolvedTypeTableSet(resolved_types, decl.child_0, vtype);
                    rtt_mod.resolvedTypeTableSet(resolved_types, decl_idx, vtype);
                    var sym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, mods[mi].id, ast_mod.astStoreNodePayload(env.store, decl_idx));
                    if (sym) |sp| {
                        sp.type_id = vtype;
                    }
                }
            }
        }
    }
}

pub fn typeResolverResolveNames(
    store: *AstStore,
    typereg: *TypeRegistry,
    symbol_reg: *SymbolRegistry,
    interner: *StringInterner,
    resolved_types: *rtt_mod.ResolvedTypeTable,
    module_reg: *mr_mod.ModuleRegistry,
    diag: *DiagnosticCollector,
    perm_alloc: *Sand
) void {
    var mods = mr_mod.moduleRegistryGetModules(module_reg);
    var env = TypeResolveEnv{ .store = store, .typereg = typereg, .symbol_reg = symbol_reg, .interner = interner, .module_id = MODULE_ID_NONE, .source_file_id = @intCast(u32, 0), .diag = diag, .local_consts = null, .local_types = null };
    _ = perm_alloc;
    resolveNamedTypeExpressions(&env, mods);
    resolveImportFieldAliases(&env, mods, module_reg);
    resolveAggregateFieldTypesAll(&env, mods);
    resolveFnSignatures(&env, mods, resolved_types);
}
