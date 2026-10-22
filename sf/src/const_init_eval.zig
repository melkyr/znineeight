// M2 T1C-F: one classification pass for file-scope `const` initializers.
//
// `constInitEvaluate` decides whether a file-scope `const`'s initializer is a
// C89 constant initializer and, when it is, builds a flat constant-init tree
// consumed by the C89 emitter (`static const T name = <init>;` rodata) and by
// the use-site scalar fold. `null` (or the `CIE_NONE` memo sentinel) means
// "not a C89 constant initializer" — the decl keeps today's `.bss` +
// `__module_init` path with today's correct values.
//
// Design: I-report `task-1c-i-report.md` §3.1 with the 1C-F operator rulings
// (fold-scope OPTION A, STOP-1 abstraction layer) and the execution deltas:
//   D1 tagged-union const with all-void payload -> `agg`; any non-void
//      payload -> `null` (the emitted payload union leads with `char _dummy`,
//      so a payload member is never the C89 first-member initializer target);
//   D2 `float_literal` -> `float_val`; float arith/negate-of-float -> `null`
//      (`comptimeEvalEvaluate` has no float-literal leaf and its binops are
//      int-only);
//   D7 wide integers (magnitude > 64 bits) -> `null` (no Z98 C type holds
//      them; symmetric with the use-site ">64-bit => no fold" rule).
//
// The tree is a flat node pool plus a child-index side array; `roots` maps a
// decl node index to its tree root (`CIE_NONE` = classified, not constant).
// Evaluation is depth-capped recursion (cap `kEvalDepthCap`); a cycle through
// `in_progress` or a depth overrun evaluates to `null`, which is always safe
// (the `.bss` fallback preserves correct values).

const AstStore = @import("ast.zig").AstStore;
const AstKind = @import("ast.zig").AstKind;
const ast_mod = @import("ast.zig");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const type_mod = @import("type_registry.zig");
const SymbolRegistry = @import("symbol_table.zig").SymbolRegistry;
const sym_mod = @import("symbol_table.zig");
const ResolvedTypeTable = @import("resolved_type_table.zig").ResolvedTypeTable;
const resolved_mod = @import("resolved_type_table.zig");
const ComptimeEval = @import("comptime_eval.zig").ComptimeEval;
const ce_mod = @import("comptime_eval.zig");
const ModuleRegistry = @import("module_registry.zig").ModuleRegistry;
const mr_mod = @import("module_registry.zig");
const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const hash_mod = @import("util/hash.zig");

pub const CIE_ZERO: u8 = 0;
pub const CIE_INT: u8 = 1;
pub const CIE_FLOAT: u8 = 2;
pub const CIE_BOOL: u8 = 3;
pub const CIE_CHAR: u8 = 4;
pub const CIE_STRING: u8 = 5;
pub const CIE_GLOBAL: u8 = 6;
pub const CIE_FN: u8 = 7;
pub const CIE_AGG: u8 = 8;

pub const CIE_NONE: u32 = 0xFFFFFFFF;
const kEvalDepthCap: u32 = 256;

// Flat constant-init tree node. `a` carries the primary value:
//   CIE_INT/CHAR  two's-complement u64 pattern in the DECL type's width
//                 (zero-extended for unsigned; `writeIntConstRvalue` masks)
//   CIE_FLOAT     f64 bit pattern
//   CIE_BOOL      0/1
//   CIE_STRING    interned string id (address of the C string literal)
//   CIE_GLOBAL    target global name_id
//   CIE_FN        function name_id
//   CIE_AGG       unused (children only)
// `b` = target module_id (GLOBAL/FN); `c` = target global type_id (GLOBAL).
pub const ConstInitNode = struct {
    kind: u8,
    _pad0: u8,
    _pad1: u8,
    _pad2: u8,
    a: u64,
    b: u32,
    c: u32,
    child_start: u32,
    child_count: u32,
};

pub const ConstInitTable = struct {
    nodes: [*]ConstInitNode,
    nodes_len: usize,
    nodes_cap: usize,
    kids: [*]u32,
    kids_len: usize,
    kids_cap: usize,
    roots: hash_mod.U32ToU32Map,
    in_progress: hash_mod.U32ToU32Map,
    alloc: *Sand,
};

pub const ConstInitEvalCtx = struct {
    tbl: *ConstInitTable,
    store: *AstStore,
    registry: *TypeRegistry,
    symbol_reg: *SymbolRegistry,
    resolved: *ResolvedTypeTable,
    ce: *ComptimeEval,
    enum_values: *hash_mod.U32ToU32Map,
    module_reg: *ModuleRegistry,
};

pub fn constInitTableInit(alloc: *Sand) ConstInitTable {
    return ConstInitTable{
        .nodes = undefined,
        .nodes_len = @intCast(usize, 0),
        .nodes_cap = @intCast(usize, 0),
        .kids = undefined,
        .kids_len = @intCast(usize, 0),
        .kids_cap = @intCast(usize, 0),
        .roots = hash_mod.u32ToU32MapInit(alloc),
        .in_progress = hash_mod.u32ToU32MapInit(alloc),
        .alloc = alloc,
    };
}

fn tableEnsureNodes(self: *ConstInitTable, need: usize) void {
    if (need <= self.nodes_cap) return;
    var new_cap: usize = self.nodes_cap;
    if (new_cap < @intCast(usize, 16)) new_cap = @intCast(usize, 16);
    while (new_cap < need) : (new_cap = new_cap * @intCast(usize, 2)) {}
    var raw = alloc_mod.sandAlloc(self.alloc, @sizeOf(ConstInitNode) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_nodes = @ptrCast([*]ConstInitNode, raw);
    var i: usize = @intCast(usize, 0);
    while (i < self.nodes_len) : (i += @intCast(usize, 1)) {
        new_nodes[i] = self.nodes[i];
    }
    self.nodes = new_nodes;
    self.nodes_cap = new_cap;
}

fn tableEnsureKids(self: *ConstInitTable, need: usize) void {
    if (need <= self.kids_cap) return;
    var new_cap: usize = self.kids_cap;
    if (new_cap < @intCast(usize, 32)) new_cap = @intCast(usize, 32);
    while (new_cap < need) : (new_cap = new_cap * @intCast(usize, 2)) {}
    var raw = alloc_mod.sandAlloc(self.alloc, @sizeOf(u32) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_kids = @ptrCast([*]u32, raw);
    var i: usize = @intCast(usize, 0);
    while (i < self.kids_len) : (i += @intCast(usize, 1)) {
        new_kids[i] = self.kids[i];
    }
    self.kids = new_kids;
    self.kids_cap = new_cap;
}

fn tableAddNode(self: *ConstInitTable, kind: u8, a: u64, b: u32, c: u32) u32 {
    tableEnsureNodes(self, self.nodes_len + @intCast(usize, 1));
    var idx: u32 = @intCast(u32, self.nodes_len);
    self.nodes[self.nodes_len] = ConstInitNode{
        .kind = kind,
        ._pad0 = @intCast(u8, 0),
        ._pad1 = @intCast(u8, 0),
        ._pad2 = @intCast(u8, 0),
        .a = a,
        .b = b,
        .c = c,
        .child_start = @intCast(u32, 0),
        .child_count = @intCast(u32, 0),
    };
    self.nodes_len += @intCast(usize, 1);
    return idx;
}

// Finish an agg node: copy `count` child roots from `scratch` into the kid
// pool and stamp the contiguous child range on `node_idx`.
fn tableFinishAgg(self: *ConstInitTable, node_idx: u32, scratch: [*]u32, count: u32) void {
    tableEnsureKids(self, self.kids_len + @intCast(usize, count));
    var start: u32 = @intCast(u32, self.kids_len);
    var i: u32 = @intCast(u32, 0);
    while (i < count) : (i += @intCast(u32, 1)) {
        self.kids[self.kids_len] = scratch[@intCast(usize, i)];
        self.kids_len += @intCast(usize, 1);
    }
    self.nodes[@intCast(usize, node_idx)].child_start = start;
    self.nodes[@intCast(usize, node_idx)].child_count = count;
}

pub fn constInitNodeAt(tbl: *ConstInitTable, idx: u32) ConstInitNode {
    return tbl.nodes[@intCast(usize, idx)];
}

pub fn constInitChildAt(tbl: *ConstInitTable, node_idx: u32, i: u32) u32 {
    var nd = tbl.nodes[@intCast(usize, node_idx)];
    return tbl.kids[@intCast(usize, nd.child_start + i)];
}

// The one classification predicate. Memoized on `decl_idx`; the result is the
// shared truth consulted by `main.zig` (storage classification), `lower.zig`
// (module-init skip + use-site scalar fold) and `c89_emit.zig` (rodata defs).
pub fn constInitEvaluate(ec: *ConstInitEvalCtx, module_id: u32, decl_idx: u32) ?u32 {
    return evalDecl(ec, module_id, decl_idx, @intCast(u32, 0));
}

fn evalDecl(ec: *ConstInitEvalCtx, module_id: u32, decl_idx: u32, depth: u32) ?u32 {
    if (decl_idx == @intCast(u32, 0)) return null;
    if (hash_mod.u32ToU32MapGet(&ec.tbl.roots, decl_idx)) |memo| {
        if (memo == CIE_NONE) return null;
        return memo;
    }
    if (depth >= kEvalDepthCap) return null;
    if (hash_mod.u32ToU32MapGet(&ec.tbl.in_progress, decl_idx) != null) return null;
    hash_mod.u32ToU32MapPut(&ec.tbl.in_progress, decl_idx, @intCast(u32, 1));
    var decl = ast_mod.astStoreNodeAt(ec.store, decl_idx);
    var root: ?u32 = null;
    if (decl.kind == AstKind.var_decl and decl.child_1 != @intCast(u32, 0)) {
        var dtype: u32 = @intCast(u32, type_mod.TYPE_UNDEFINED);
        if (resolved_mod.resolvedTypeTableGet(ec.resolved, decl_idx)) |dt| {
            dtype = dt;
        }
        root = classify(ec, module_id, decl.child_1, dtype, depth + @intCast(u32, 1));
    }
    if (root) |r| {
        hash_mod.u32ToU32MapPut(&ec.tbl.roots, decl_idx, r);
        return r;
    }
    hash_mod.u32ToU32MapPut(&ec.tbl.roots, decl_idx, CIE_NONE);
    return null;
}

fn typeKindOf(ec: *ConstInitEvalCtx, type_id: u32) u32 {
    if (type_id == @intCast(u32, 0) or @intCast(usize, type_id) >= ec.registry.types_len) {
        return @intCast(u32, @enumToInt(type_mod.TypeKind.none_sentinel));
    }
    return @intCast(u32, @enumToInt(ec.registry.types_items[@intCast(usize, type_id)].kind));
}

fn isU8ish(ec: *ConstInitEvalCtx, elem: u32) bool {
    if (elem == type_mod.TYPE_U8 or elem == type_mod.TYPE_C_CHAR) return true;
    if (typeKindOf(ec, elem) == @intCast(u32, @enumToInt(type_mod.TypeKind.u8_type))) return true;
    return false;
}

fn valNodeFromComptime(ec: *ConstInitEvalCtx, cv: ce_mod.ComptimeVal, type_id: u32) ?u32 {
    if (cv.kind == ce_mod.KIND_INT) {
        if (!ce_mod.comptimeIntFits64(cv.v)) return null;
        if (type_id != @intCast(u32, 0) and @intCast(usize, type_id) < ec.registry.types_len) {
            var tk = typeKindOf(ec, type_id);
            var is_int_ty: bool = (tk == @intCast(u32, @enumToInt(type_mod.TypeKind.i8_type)) or
                tk == @intCast(u32, @enumToInt(type_mod.TypeKind.i16_type)) or
                tk == @intCast(u32, @enumToInt(type_mod.TypeKind.i32_type)) or
                tk == @intCast(u32, @enumToInt(type_mod.TypeKind.i64_type)) or
                tk == @intCast(u32, @enumToInt(type_mod.TypeKind.u8_type)) or
                tk == @intCast(u32, @enumToInt(type_mod.TypeKind.u16_type)) or
                tk == @intCast(u32, @enumToInt(type_mod.TypeKind.u32_type)) or
                tk == @intCast(u32, @enumToInt(type_mod.TypeKind.u64_type)) or
                tk == @intCast(u32, @enumToInt(type_mod.TypeKind.isize_type)) or
                tk == @intCast(u32, @enumToInt(type_mod.TypeKind.usize_type)) or
                tk == @intCast(u32, @enumToInt(type_mod.TypeKind.c_char_type)) or
                tk == @intCast(u32, @enumToInt(type_mod.TypeKind.arb_uint_type)) or
                tk == @intCast(u32, @enumToInt(type_mod.TypeKind.arb_int_type)));
            if (is_int_ty) {
                if (!ce_mod.comptimeIntFitsType(ec.registry, cv.v, type_id)) return null;
            }
        }
        var pattern = ce_mod.ciToU64(cv.v);
        var nflag: u32 = @intCast(u32, 0);
        if (cv.v.neg) { nflag = @intCast(u32, 1); }
        return tableAddNode(ec.tbl, CIE_INT, pattern, nflag, @intCast(u32, 0));
    }
    if (cv.kind == ce_mod.KIND_BOOL) {
        var bv: u64 = @intCast(u64, 0);
        if (!ce_mod.ciIsZero(cv.v)) bv = @intCast(u64, 1);
        return tableAddNode(ec.tbl, CIE_BOOL, bv, @intCast(u32, 0), @intCast(u32, 0));
    }
    if (cv.kind == ce_mod.KIND_FLOAT) {
        return tableAddNode(ec.tbl, CIE_FLOAT, cv.float_bits, @intCast(u32, 0), @intCast(u32, 0));
    }
    return null;
}

fn symbolIsConstGlobalSym(s: *sym_mod.Symbol) bool {
    if (s.kind != sym_mod.SymbolKind.global) return false;
    return (@intCast(u16, s.flags) & @intCast(u16, 1)) == @intCast(u16, 0);
}

fn resolveModuleBaseNode(ec: *ConstInitEvalCtx, module_id: u32, base_idx: u32) u32 {
    if (base_idx == @intCast(u32, 0)) return @intCast(u32, 0);
    var bn = ast_mod.astStoreNodeAt(ec.store, base_idx);
    if (bn.kind == AstKind.ident_expr) {
        var nid = ast_mod.astStoreIdentifier(ec.store, base_idx);
        if (sym_mod.symbolRegistryQualifiedLookup(ec.symbol_reg, module_id, nid)) |s| {
            if (s.kind == sym_mod.SymbolKind.module) return s.module_id;
            if (s.type_id != @intCast(u32, 0) and @intCast(usize, s.type_id) < ec.registry.types_len) {
                var sty = ec.registry.types_items[@intCast(usize, s.type_id)];
                if (sty.kind == type_mod.TypeKind.module_type) return sty.module_id;
            }
        }
        return @intCast(u32, 0);
    }
    if (bn.kind == AstKind.import_expr) {
        var path_id = ast_mod.astStoreNodePayload(ec.store, base_idx);
        if (mr_mod.moduleRegistryPathToIdGet(ec.module_reg, path_id)) |mtid| return mtid;
        return @intCast(u32, 0);
    }
    return @intCast(u32, 0);
}

// Value-copy of a const global's tree (S18): classify the target's initializer
// through the same predicate (memoized) and reference its root.
fn valueCopyDecl(ec: *ConstInitEvalCtx, target_module: u32, decl_idx: u32, depth: u32) ?u32 {
    if (decl_idx == @intCast(u32, 0)) return null;
    var decl = ast_mod.astStoreNodeAt(ec.store, decl_idx);
    if (decl.kind != AstKind.var_decl) return null;
    if ((@intCast(u16, decl.flags) & @intCast(u16, 1)) != @intCast(u16, 0)) return null;
    return evalDecl(ec, target_module, decl_idx, depth);
}

fn classifyScalar(ec: *ConstInitEvalCtx, module_id: u32, node_idx: u32, type_id: u32, depth: u32) ?u32 {
    var node = ast_mod.astStoreNodeAt(ec.store, node_idx);
    if (node.kind == AstKind.float_literal) {
        var fb0 = ec.store.float_values.items[@intCast(usize, ast_mod.astStoreNodePayload(ec.store, node_idx))];
        // Z98 @bitCast is integer-only; transport the f64 bit pattern.
        var fbp0: *u64 = @ptrCast(*u64, &fb0);
        return tableAddNode(ec.tbl, CIE_FLOAT, fbp0.*, @intCast(u32, 0), @intCast(u32, 0));
    }
    if (node.kind == AstKind.int_literal) {
        var v = ce_mod.ciFromU64(ast_mod.astStoreIntValue(ec.store, node_idx));
        return valNodeFromComptime(ec, ce_mod.ciIntVal(v), type_id);
    }
    if (node.kind == AstKind.char_literal) {
        var v2 = ce_mod.ciFromU64(ast_mod.astStoreIntValue(ec.store, node_idx));
        var nid2 = valNodeFromComptime(ec, ce_mod.ciIntVal(v2), type_id);
        if (nid2) |n2| {
            ec.tbl.nodes[@intCast(usize, n2)].kind = CIE_CHAR;
            return n2;
        }
        return null;
    }
    if (node.kind == AstKind.bool_literal) {
        var bv: u64 = @intCast(u64, 0);
        if ((node.flags & @intCast(u8, 1)) != @intCast(u8, 0)) bv = @intCast(u64, 1);
        return tableAddNode(ec.tbl, CIE_BOOL, bv, @intCast(u32, 0), @intCast(u32, 0));
    }
    if (node.kind == AstKind.enum_literal) {
        if (hash_mod.u32ToU32MapGet(ec.enum_values, node_idx)) |ev| {
            var pv = ce_mod.ciFromU64(@intCast(u64, ev));
            return valNodeFromComptime(ec, ce_mod.ciIntVal(pv), type_id);
        }
        return null;
    }
    if (node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(ec.store, node_idx);
        if (sym_mod.symbolRegistryQualifiedLookup(ec.symbol_reg, module_id, name_id)) |s| {
            if (s.kind == sym_mod.SymbolKind.function) {
                return tableAddNode(ec.tbl, CIE_FN, @intCast(u64, s.name_id), s.module_id, @intCast(u32, 0));
            }
            if (symbolIsConstGlobalSym(s)) {
                return valueCopyDecl(ec, s.module_id, s.decl_node, depth);
            }
        }
        return null;
    }
    if (node.kind == AstKind.field_access) {
        var mid = resolveModuleBaseNode(ec, module_id, node.child_0);
        if (mid != @intCast(u32, 0)) {
            var fname = ast_mod.astStoreNodePayload(ec.store, node_idx);
            if (sym_mod.symbolRegistryQualifiedLookup(ec.symbol_reg, mid, fname)) |s2| {
                if (s2.kind == sym_mod.SymbolKind.function) {
                    return tableAddNode(ec.tbl, CIE_FN, @intCast(u64, s2.name_id), s2.module_id, @intCast(u32, 0));
                }
                if (symbolIsConstGlobalSym(s2)) {
                    return valueCopyDecl(ec, s2.module_id, s2.decl_node, depth);
                }
            }
        }
        return null;
    }
    if (node.kind == AstKind.paren_expr) {
        return classify(ec, module_id, node.child_0, type_id, depth);
    }
    // arith/neg/not/casts/builtins over constants (D2: float folds that
    // comptimeEvalEvaluate cannot reach simply come back null).
    if (comptimeShapeKind(node.kind)) {
        if (ce_mod.comptimeEvalEvaluate(ec.ce, node_idx)) |cv| {
            return valNodeFromComptime(ec, cv, type_id);
        }
        return null;
    }
    return null;
}

fn comptimeShapeKind(k: AstKind) bool {
    if (k == AstKind.negate or k == AstKind.bit_not or k == AstKind.bool_not) return true;
    if (k == AstKind.add or k == AstKind.sub or k == AstKind.mul or k == AstKind.div or k == AstKind.mod_op) return true;
    if (k == AstKind.bit_and or k == AstKind.bit_or or k == AstKind.bit_xor or k == AstKind.shl or k == AstKind.shr) return true;
    if (k == AstKind.bool_and or k == AstKind.bool_or) return true;
    if (k == AstKind.cmp_eq or k == AstKind.cmp_ne or k == AstKind.cmp_lt or k == AstKind.cmp_le or k == AstKind.cmp_gt or k == AstKind.cmp_ge) return true;
    if (k == AstKind.builtin_call) return true;
    return false;
}

fn classifyAddr(ec: *ConstInitEvalCtx, module_id: u32, target_idx: u32, depth: u32) ?u32 {
    _ = depth;
    var t = ast_mod.astStoreNodeAt(ec.store, target_idx);
    if (t.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(ec.store, target_idx);
        if (sym_mod.symbolRegistryQualifiedLookup(ec.symbol_reg, module_id, name_id)) |s| {
            if (s.kind == sym_mod.SymbolKind.function) {
                return tableAddNode(ec.tbl, CIE_FN, @intCast(u64, s.name_id), s.module_id, @intCast(u32, 0));
            }
            if (s.kind == sym_mod.SymbolKind.global) {
                var gtid: u32 = @intCast(u32, 0);
                if (resolved_mod.resolvedTypeTableGet(ec.resolved, s.decl_node)) |gt| {
                    gtid = gt;
                } else {
                    gtid = s.type_id;
                }
                return tableAddNode(ec.tbl, CIE_GLOBAL, @intCast(u64, s.name_id), s.module_id, gtid);
            }
        }
        return null;
    }
    if (t.kind == AstKind.field_access) {
        var mid = resolveModuleBaseNode(ec, module_id, t.child_0);
        if (mid != @intCast(u32, 0)) {
            var fname = ast_mod.astStoreNodePayload(ec.store, target_idx);
            if (sym_mod.symbolRegistryQualifiedLookup(ec.symbol_reg, mid, fname)) |s2| {
                if (s2.kind == sym_mod.SymbolKind.function) {
                    return tableAddNode(ec.tbl, CIE_FN, @intCast(u64, s2.name_id), s2.module_id, @intCast(u32, 0));
                }
                if (s2.kind == sym_mod.SymbolKind.global) {
                    var gtid2: u32 = s2.type_id;
                    if (resolved_mod.resolvedTypeTableGet(ec.resolved, s2.decl_node)) |gt2| {
                        gtid2 = gt2;
                    }
                    return tableAddNode(ec.tbl, CIE_GLOBAL, @intCast(u64, s2.name_id), s2.module_id, gtid2);
                }
            }
        }
        return null;
    }
    return null;
}

fn classifyAgg(ec: *ConstInitEvalCtx, module_id: u32, node_idx: u32, type_id: u32, depth: u32) ?u32 {
    if (depth >= kEvalDepthCap) return null;
    var node = ast_mod.astStoreNodeAt(ec.store, node_idx);
    var tk = typeKindOf(ec, type_id);

    // S8 (array-typed field of a const array): a const ref into an aggregate
    // destination value-copies the target's tree (C89 needs a value list).
    if (node.kind == AstKind.ident_expr) {
        var cv_name = ast_mod.astStoreIdentifier(ec.store, node_idx);
        if (sym_mod.symbolRegistryQualifiedLookup(ec.symbol_reg, module_id, cv_name)) |cvs| {
            if (symbolIsConstGlobalSym(cvs)) {
                return valueCopyDecl(ec, cvs.module_id, cvs.decl_node, depth);
            }
        }
        return null;
    }
    if (node.kind == AstKind.field_access) {
        var cv_mid = resolveModuleBaseNode(ec, module_id, node.child_0);
        if (cv_mid != @intCast(u32, 0)) {
            var cv_fn = ast_mod.astStoreNodePayload(ec.store, node_idx);
            if (sym_mod.symbolRegistryQualifiedLookup(ec.symbol_reg, cv_mid, cv_fn)) |cvs2| {
                if (symbolIsConstGlobalSym(cvs2)) {
                    return valueCopyDecl(ec, cvs2.module_id, cvs2.decl_node, depth);
                }
            }
        }
        return null;
    }

    // ---- array --------------------------------------------------------
    if (tk == @intCast(u32, @enumToInt(type_mod.TypeKind.array_type))) {
        var ap = ec.registry.array_items[@intCast(usize, ec.registry.types_items[@intCast(usize, type_id)].payload_idx)];
        var want: u32 = ap.length;
        if (node.kind == AstKind.array_init or node.kind == AstKind.tuple_literal) {
            var n = ast_mod.astStoreNodeExtraChildCount(ec.store, node_idx);
            if (@intCast(u32, n) > want) return null;
            var agg = tableAddNode(ec.tbl, CIE_AGG, @intCast(u64, 0), @intCast(u32, 0), @intCast(u32, 0));
            var scratch_raw = alloc_mod.sandAlloc(ec.tbl.alloc, @sizeOf(u32) * @intCast(usize, want + 1), @intCast(usize, 4)) catch unreachable;
            var scratch = @ptrCast([*]u32, scratch_raw);
            var i: u32 = @intCast(u32, 0);
            var ok: bool = true;
            while (i < want) : (i += @intCast(u32, 1)) {
                if (i < @intCast(u32, n)) {
                    var cei = ast_mod.astStoreNodeExtraChildAt(ec.store, node_idx, i);
                    if (classify(ec, module_id, cei, ap.elem, depth + @intCast(u32, 1))) |ch| {
                        scratch[@intCast(usize, i)] = ch;
                    } else {
                        ok = false;
                        break;
                    }
                } else {
                    scratch[@intCast(usize, i)] = tableAddNode(ec.tbl, CIE_ZERO, @intCast(u64, 0), @intCast(u32, 0), @intCast(u32, 0));
                }
            }
            if (!ok) return null;
            tableFinishAgg(ec.tbl, agg, scratch, want);
            return agg;
        }
        return null;
    }

    // ---- tuple --------------------------------------------------------
    if (tk == @intCast(u32, @enumToInt(type_mod.TypeKind.tuple_type))) {
        if (node.kind != AstKind.tuple_literal) return null;
        var tp = ec.registry.tup_items[@intCast(usize, ec.registry.types_items[@intCast(usize, type_id)].payload_idx)];
        var tcount: u32 = @intCast(u32, tp.elems_count);
        var n2 = ast_mod.astStoreNodeExtraChildCount(ec.store, node_idx);
        if (@intCast(u32, n2) != tcount) return null;
        var agg2 = tableAddNode(ec.tbl, CIE_AGG, @intCast(u64, 0), @intCast(u32, 0), @intCast(u32, 0));
        var scratch_raw2 = alloc_mod.sandAlloc(ec.tbl.alloc, @sizeOf(u32) * @intCast(usize, tcount + 1), @intCast(usize, 4)) catch unreachable;
        var scratch2 = @ptrCast([*]u32, scratch_raw2);
        var j: u32 = @intCast(u32, 0);
        var ok2: bool = true;
        while (j < tcount) : (j += @intCast(u32, 1)) {
            var et = ec.registry.xt_items[@intCast(usize, tp.elems_start) + @intCast(usize, j)];
            var cj = ast_mod.astStoreNodeExtraChildAt(ec.store, node_idx, j);
            if (classify(ec, module_id, cj, et, depth + @intCast(u32, 1))) |ch2| {
                scratch2[@intCast(usize, j)] = ch2;
            } else {
                ok2 = false;
                break;
            }
        }
        if (!ok2) return null;
        tableFinishAgg(ec.tbl, agg2, scratch2, tcount);
        return agg2;
    }

    // ---- struct -------------------------------------------------------
    if (tk == @intCast(u32, @enumToInt(type_mod.TypeKind.struct_type))) {
        var sp = ec.registry.st_items[@intCast(usize, ec.registry.types_items[@intCast(usize, type_id)].payload_idx)];
        var fs: usize = @intCast(usize, sp.fields_start);
        var fc: usize = @intCast(usize, sp.fields_count);
        // C-visible fields only (void fields are not emitted in the C struct).
        var vis_raw = alloc_mod.sandAlloc(ec.tbl.alloc, @sizeOf(u32) * (fc + @intCast(usize, 1)), @intCast(usize, 4)) catch unreachable;
        var vis = @ptrCast([*]u32, vis_raw);
        var vc: u32 = @intCast(u32, 0);
        var fi: usize = @intCast(usize, 0);
        while (fi < fc) : (fi += @intCast(usize, 1)) {
            if (ec.registry.fe_items[fs + fi].type_id != type_mod.TYPE_VOID) {
                vis[@intCast(usize, vc)] = @intCast(u32, fi);
                vc += @intCast(u32, 1);
            }
        }
        if (node.kind == AstKind.struct_init) {
            // Named fields, reordered to type declaration order (C89 positional).
            var n3 = ast_mod.astStoreNodeExtraChildCount(ec.store, node_idx);
            // every init field must map to a type field
            var ei3: u32 = @intCast(u32, 0);
            while (ei3 < @intCast(u32, n3)) : (ei3 += @intCast(u32, 1)) {
                var fi3 = ast_mod.astStoreNodeExtraChildAt(ec.store, node_idx, ei3);
                var fn3 = ast_mod.astStoreNodePayload(ec.store, fi3);
                var found3: bool = false;
                var fj3: usize = @intCast(usize, 0);
                while (fj3 < fc) : (fj3 += @intCast(usize, 1)) {
                    if (ec.registry.fe_items[fs + fj3].name_id == fn3) {
                        found3 = true;
                        break;
                    }
                }
                if (!found3) return null;
            }
            var agg3 = tableAddNode(ec.tbl, CIE_AGG, @intCast(u64, 0), @intCast(u32, 0), @intCast(u32, 0));
            var scratch_raw3 = alloc_mod.sandAlloc(ec.tbl.alloc, @sizeOf(u32) * @intCast(usize, vc + 1), @intCast(usize, 4)) catch unreachable;
            var scratch3 = @ptrCast([*]u32, scratch_raw3);
            var vi: u32 = @intCast(u32, 0);
            var ok3: bool = true;
            while (vi < vc) : (vi += @intCast(u32, 1)) {
                var fe3 = ec.registry.fe_items[fs + @intCast(usize, vis[@intCast(usize, vi)])];
                var val_node: u32 = @intCast(u32, 0);
                var have: bool = false;
                var fj4: u32 = @intCast(u32, 0);
                while (fj4 < @intCast(u32, n3)) : (fj4 += @intCast(u32, 1)) {
                    var fi4 = ast_mod.astStoreNodeExtraChildAt(ec.store, node_idx, fj4);
                    if (ast_mod.astStoreNodePayload(ec.store, fi4) == fe3.name_id) {
                        if (classify(ec, module_id, ast_mod.astStoreNodeAt(ec.store, fi4).child_0, fe3.type_id, depth + @intCast(u32, 1))) |ch3| {
                            val_node = ch3;
                            have = true;
                        } else {
                            ok3 = false;
                        }
                        break;
                    }
                }
                if (!ok3) break;
                if (!have) {
                    val_node = tableAddNode(ec.tbl, CIE_ZERO, @intCast(u64, 0), @intCast(u32, 0), @intCast(u32, 0));
                }
                scratch3[@intCast(usize, vi)] = val_node;
            }
            if (!ok3) return null;
            tableFinishAgg(ec.tbl, agg3, scratch3, vc);
            return agg3;
        }
        if (node.kind == AstKind.tuple_literal) {
            // positional `.{ a, b }` against a named struct: C-visible order.
            var n4 = ast_mod.astStoreNodeExtraChildCount(ec.store, node_idx);
            if (@intCast(u32, n4) != vc) return null;
            var agg4 = tableAddNode(ec.tbl, CIE_AGG, @intCast(u64, 0), @intCast(u32, 0), @intCast(u32, 0));
            var scratch_raw4 = alloc_mod.sandAlloc(ec.tbl.alloc, @sizeOf(u32) * @intCast(usize, vc + 1), @intCast(usize, 4)) catch unreachable;
            var scratch4 = @ptrCast([*]u32, scratch_raw4);
            var vi4: u32 = @intCast(u32, 0);
            var ok4: bool = true;
            while (vi4 < vc) : (vi4 += @intCast(u32, 1)) {
                var fe4 = ec.registry.fe_items[fs + @intCast(usize, vis[@intCast(usize, vi4)])];
                var cj4 = ast_mod.astStoreNodeExtraChildAt(ec.store, node_idx, vi4);
                if (classify(ec, module_id, cj4, fe4.type_id, depth + @intCast(u32, 1))) |ch4| {
                    scratch4[@intCast(usize, vi4)] = ch4;
                } else {
                    ok4 = false;
                    break;
                }
            }
            if (!ok4) return null;
            tableFinishAgg(ec.tbl, agg4, scratch4, vc);
            return agg4;
        }
        return null;
    }

    // ---- untagged union (STOP-1: first non-void member only) ----------
    if (tk == @intCast(u32, @enumToInt(type_mod.TypeKind.union_type))) {
        if (node.kind != AstKind.struct_init) return null;
        var up = ec.registry.un_items[@intCast(usize, ec.registry.types_items[@intCast(usize, type_id)].payload_idx)];
        var ufs: usize = @intCast(usize, up.fields_start);
        var ufc: usize = @intCast(usize, up.fields_count);
        var n5 = ast_mod.astStoreNodeExtraChildCount(ec.store, node_idx);
        if (@intCast(u32, n5) != @intCast(u32, 1)) return null;
        var fi5 = ast_mod.astStoreNodeExtraChildAt(ec.store, node_idx, @intCast(u32, 0));
        var fn5 = ast_mod.astStoreNodePayload(ec.store, fi5);
        var ai5: i64 = @intCast(i64, -1);
        var uj: usize = @intCast(usize, 0);
        while (uj < ufc) : (uj += @intCast(usize, 1)) {
            if (ec.registry.fe_items[ufs + uj].name_id == fn5) {
                ai5 = @intCast(i64, uj);
                break;
            }
        }
        if (ai5 < @intCast(i64, 0)) return null;
        // first non-void member is the only C89-constant-initializable one
        var first_vis: i64 = @intCast(i64, -1);
        var uj2: usize = @intCast(usize, 0);
        while (uj2 < ufc) : (uj2 += @intCast(usize, 1)) {
            if (ec.registry.fe_items[ufs + uj2].type_id != type_mod.TYPE_VOID) {
                first_vis = @intCast(i64, uj2);
                break;
            }
        }
        if (ai5 != first_vis) return null;
        var afe = ec.registry.fe_items[ufs + @intCast(usize, ai5)];
        if (classify(ec, module_id, ast_mod.astStoreNodeAt(ec.store, fi5).child_0, afe.type_id, depth + @intCast(u32, 1))) |ch5| {
            var agg5 = tableAddNode(ec.tbl, CIE_AGG, @intCast(u64, 0), @intCast(u32, 0), @intCast(u32, 0));
            var scratch_raw5 = alloc_mod.sandAlloc(ec.tbl.alloc, @sizeOf(u32) * 2, @intCast(usize, 4)) catch unreachable;
            var scratch5 = @ptrCast([*]u32, scratch_raw5);
            scratch5[0] = ch5;
            tableFinishAgg(ec.tbl, agg5, scratch5, @intCast(u32, 1));
            return agg5;
        }
        return null;
    }

    // ---- tagged union (D1: empty payload only) ------------------------
    if (tk == @intCast(u32, @enumToInt(type_mod.TypeKind.tagged_union_type))) {
        if (node.kind != AstKind.struct_init) return null;
        var tpu = ec.registry.tu_items[@intCast(usize, ec.registry.types_items[@intCast(usize, type_id)].payload_idx)];
        var tfs: usize = @intCast(usize, tpu.fields_start);
        var tfc: usize = @intCast(usize, tpu.fields_count);
        var n6 = ast_mod.astStoreNodeExtraChildCount(ec.store, node_idx);
        if (@intCast(u32, n6) != @intCast(u32, 1)) return null;
        var fi6 = ast_mod.astStoreNodeExtraChildAt(ec.store, node_idx, @intCast(u32, 0));
        var fn6 = ast_mod.astStoreNodePayload(ec.store, fi6);
        var ai6: i64 = @intCast(i64, -1);
        var tj: usize = @intCast(usize, 0);
        while (tj < tfc) : (tj += @intCast(usize, 1)) {
            if (ec.registry.fe_items[tfs + tj].name_id == fn6) {
                ai6 = @intCast(i64, tj);
                break;
            }
        }
        if (ai6 < @intCast(i64, 0)) return null;
        var tfe = ec.registry.fe_items[tfs + @intCast(usize, ai6)];
        // D1: any non-void payload -> .bss fallback (the emitted payload
        // union leads with `char _dummy`, so a payload member cannot be the
        // C89 first-member static initializer).
        if (tfe.type_id != type_mod.TYPE_VOID) return null;
        // tag value: enum member value when the tag is an enum type, else
        // the field ordinal (emitTaggedUnionType macro rule).
        var tag_val: u64 = @intCast(u64, ai6);
        var ttag = ec.registry.types_items[@intCast(usize, tpu.tag_type)];
        if (ttag.kind == type_mod.TypeKind.enum_type) {
            var ep = ec.registry.en_items[@intCast(usize, ttag.payload_idx)];
            var found_t: bool = false;
            var em: u16 = @intCast(u16, 0);
            while (em < ep.members_count) : (em += @intCast(u16, 1)) {
                var mem = ec.registry.em_items[@intCast(usize, ep.members_start) + @intCast(usize, em)];
                if (mem.name_id == fn6) {
                    tag_val = @intCast(u64, @intCast(i64, mem.value));
                    found_t = true;
                    break;
                }
            }
            if (!found_t) return null;
        }
        var agg6 = tableAddNode(ec.tbl, CIE_AGG, @intCast(u64, 0), @intCast(u32, 0), @intCast(u32, 0));
        var scratch_raw6 = alloc_mod.sandAlloc(ec.tbl.alloc, @sizeOf(u32) * 3, @intCast(usize, 4)) catch unreachable;
        var scratch6 = @ptrCast([*]u32, scratch_raw6);
        scratch6[0] = tableAddNode(ec.tbl, CIE_INT, tag_val, @intCast(u32, 0), @intCast(u32, 0));
        scratch6[1] = tableAddNode(ec.tbl, CIE_ZERO, @intCast(u64, 0), @intCast(u32, 0), @intCast(u32, 0));
        tableFinishAgg(ec.tbl, agg6, scratch6, @intCast(u32, 2));
        return agg6;
    }

    // ---- optional (S17 via typedef shape) -----------------------------
    if (tk == @intCast(u32, @enumToInt(type_mod.TypeKind.optional_type))) {
        if (node.kind == AstKind.null_literal) {
            return tableAddNode(ec.tbl, CIE_ZERO, @intCast(u64, 0), @intCast(u32, 0), @intCast(u32, 0));
        }
        var op = ec.registry.opt_items[@intCast(usize, ec.registry.types_items[@intCast(usize, type_id)].payload_idx)];
        if (classify(ec, module_id, node_idx, op.payload, depth + @intCast(u32, 1))) |pay| {
            var agg7 = tableAddNode(ec.tbl, CIE_AGG, @intCast(u64, 0), @intCast(u32, 0), @intCast(u32, 0));
            var scratch_raw7 = alloc_mod.sandAlloc(ec.tbl.alloc, @sizeOf(u32) * 3, @intCast(usize, 4)) catch unreachable;
            var scratch7 = @ptrCast([*]u32, scratch_raw7);
            scratch7[0] = pay;
            scratch7[1] = tableAddNode(ec.tbl, CIE_INT, @intCast(u64, 1), @intCast(u32, 0), @intCast(u32, 0));
            tableFinishAgg(ec.tbl, agg7, scratch7, @intCast(u32, 2));
            return agg7;
        }
        return null;
    }

    // ---- error union (S17 via typedef shape) --------------------------
    if (tk == @intCast(u32, @enumToInt(type_mod.TypeKind.error_union_type))) {
        var ep2 = ec.registry.eu_items[@intCast(usize, ec.registry.types_items[@intCast(usize, type_id)].payload_idx)];
        var pay_ty = ep2.payload;
        var is_void_pay: bool = (pay_ty == type_mod.TYPE_VOID) or (typeKindOf(ec, pay_ty) == @intCast(u32, @enumToInt(type_mod.TypeKind.void_type)));
        if (node.kind == AstKind.error_literal) {
            // error init of a non-void-payload EU lands in the `data` union's
            // NON-first member (D1); void-payload EU is `struct { int err;
            // int is_error; }` and is representable.
            if (!is_void_pay) return null;
            if (hash_mod.u32ToU32MapGet(ec.enum_values, node_idx)) |ev2| {
                var agg8 = tableAddNode(ec.tbl, CIE_AGG, @intCast(u64, 0), @intCast(u32, 0), @intCast(u32, 0));
                var scratch_raw8 = alloc_mod.sandAlloc(ec.tbl.alloc, @sizeOf(u32) * 3, @intCast(usize, 4)) catch unreachable;
                var scratch8 = @ptrCast([*]u32, scratch_raw8);
                scratch8[0] = tableAddNode(ec.tbl, CIE_INT, @intCast(u64, ev2), @intCast(u32, 0), @intCast(u32, 0));
                scratch8[1] = tableAddNode(ec.tbl, CIE_INT, @intCast(u64, 1), @intCast(u32, 0), @intCast(u32, 0));
                tableFinishAgg(ec.tbl, agg8, scratch8, @intCast(u32, 2));
                return agg8;
            }
            return null;
        }
        if (is_void_pay) return null;
        if (classify(ec, module_id, node_idx, pay_ty, depth + @intCast(u32, 1))) |pay2| {
            // typedef { union { T payload; int err; } data; int is_error; }
            // (the renderer wraps the payload child in the `data` braces)
            var agg9 = tableAddNode(ec.tbl, CIE_AGG, @intCast(u64, 0), @intCast(u32, 0), @intCast(u32, 0));
            var scratch_raw9 = alloc_mod.sandAlloc(ec.tbl.alloc, @sizeOf(u32) * 3, @intCast(usize, 4)) catch unreachable;
            var scratch9 = @ptrCast([*]u32, scratch_raw9);
            scratch9[0] = pay2;
            scratch9[1] = tableAddNode(ec.tbl, CIE_INT, @intCast(u64, 0), @intCast(u32, 0), @intCast(u32, 0));
            tableFinishAgg(ec.tbl, agg9, scratch9, @intCast(u32, 2));
            return agg9;
        }
        return null;
    }

    return null;
}

fn classify(ec: *ConstInitEvalCtx, module_id: u32, node_idx: u32, type_id: u32, depth: u32) ?u32 {
    if (node_idx == @intCast(u32, 0)) return null;
    if (depth >= kEvalDepthCap) return null;
    var node = ast_mod.astStoreNodeAt(ec.store, node_idx);
    var tk = typeKindOf(ec, type_id);

    if (node.kind == AstKind.undefined_literal) return null;

    // Type-directed non-scalar shapes first (a literal in a non-scalar slot
    // belongs to the shape, e.g. `?u32 = 5` -> optional aggregate).
    if (tk == @intCast(u32, @enumToInt(type_mod.TypeKind.optional_type)) or
        tk == @intCast(u32, @enumToInt(type_mod.TypeKind.error_union_type)) or
        tk == @intCast(u32, @enumToInt(type_mod.TypeKind.array_type)) or
        tk == @intCast(u32, @enumToInt(type_mod.TypeKind.tuple_type)) or
        tk == @intCast(u32, @enumToInt(type_mod.TypeKind.struct_type)) or
        tk == @intCast(u32, @enumToInt(type_mod.TypeKind.union_type)) or
        tk == @intCast(u32, @enumToInt(type_mod.TypeKind.tagged_union_type)))
    {
        // string literal into a u8 array (S12) or into a struct? arrays only
        if (node.kind == AstKind.string_literal and tk == @intCast(u32, @enumToInt(type_mod.TypeKind.array_type))) {
            var ap = ec.registry.array_items[@intCast(usize, ec.registry.types_items[@intCast(usize, type_id)].payload_idx)];
            if (isU8ish(ec, ap.elem)) {
                var sid = ec.store.string_values.items[@intCast(usize, ast_mod.astStoreNodePayload(ec.store, node_idx))];
                return tableAddNode(ec.tbl, CIE_STRING, @intCast(u64, sid), @intCast(u32, 0), @intCast(u32, 0));
            }
            return null;
        }
        return classifyAgg(ec, module_id, node_idx, type_id, depth);
    }

    // pointer-ish targets
    if (tk == @intCast(u32, @enumToInt(type_mod.TypeKind.ptr_type)) or
        tk == @intCast(u32, @enumToInt(type_mod.TypeKind.many_ptr_type)))
    {
        if (node.kind == AstKind.null_literal) {
            return tableAddNode(ec.tbl, CIE_ZERO, @intCast(u64, 0), @intCast(u32, 0), @intCast(u32, 0));
        }
        if (node.kind == AstKind.string_literal) {
            var sid2 = ec.store.string_values.items[@intCast(usize, ast_mod.astStoreNodePayload(ec.store, node_idx))];
            return tableAddNode(ec.tbl, CIE_STRING, @intCast(u64, sid2), @intCast(u32, 0), @intCast(u32, 0));
        }
        if (node.kind == AstKind.address_of) {
            return classifyAddr(ec, module_id, node.child_0, depth);
        }
        if (node.kind == AstKind.ident_expr) {
            // decay of an ARRAY global (S9) is an address constant; a const
            // ref to a non-array target value-copies its tree (S18).
            var name_id2 = ast_mod.astStoreIdentifier(ec.store, node_idx);
            if (sym_mod.symbolRegistryQualifiedLookup(ec.symbol_reg, module_id, name_id2)) |s3| {
                if (s3.kind == sym_mod.SymbolKind.function) {
                    return tableAddNode(ec.tbl, CIE_FN, @intCast(u64, s3.name_id), s3.module_id, @intCast(u32, 0));
                }
                if (s3.kind == sym_mod.SymbolKind.global) {
                    var gtid3: u32 = s3.type_id;
                    if (resolved_mod.resolvedTypeTableGet(ec.resolved, s3.decl_node)) |gt3| {
                        gtid3 = gt3;
                    }
                    if (typeKindOf(ec, gtid3) == @intCast(u32, @enumToInt(type_mod.TypeKind.array_type))) {
                        return tableAddNode(ec.tbl, CIE_GLOBAL, @intCast(u64, s3.name_id), s3.module_id, gtid3);
                    }
                    return valueCopyDecl(ec, s3.module_id, s3.decl_node, depth);
                }
            }
            return null;
        }
        return null;
    }

    // slice targets
    if (tk == @intCast(u32, @enumToInt(type_mod.TypeKind.slice_type))) {
        if (node.kind == AstKind.string_literal) {
            var sid3 = ec.store.string_values.items[@intCast(usize, ast_mod.astStoreNodePayload(ec.store, node_idx))];
            return tableAddNode(ec.tbl, CIE_STRING, @intCast(u64, sid3), @intCast(u32, 0), @intCast(u32, 0));
        }
        if (node.kind == AstKind.ident_expr) {
            // slice-of-const-array decay (S9): `gc: []const i32 = garr`
            var name_id3 = ast_mod.astStoreIdentifier(ec.store, node_idx);
            if (sym_mod.symbolRegistryQualifiedLookup(ec.symbol_reg, module_id, name_id3)) |s4| {
                if (s4.kind == sym_mod.SymbolKind.global) {
                    var gtid4: u32 = s4.type_id;
                    if (resolved_mod.resolvedTypeTableGet(ec.resolved, s4.decl_node)) |gt4| {
                        gtid4 = gt4;
                    }
                    if (typeKindOf(ec, gtid4) == @intCast(u32, @enumToInt(type_mod.TypeKind.array_type))) {
                        return tableAddNode(ec.tbl, CIE_GLOBAL, @intCast(u64, s4.name_id), s4.module_id, gtid4);
                    }
                    return valueCopyDecl(ec, s4.module_id, s4.decl_node, depth);
                }
            }
            return null;
        }
        if (node.kind == AstKind.address_of) {
            return classifyAddr(ec, module_id, node.child_0, depth);
        }
        return null;
    }

    // float targets (D2: direct literals only)
    if (tk == @intCast(u32, @enumToInt(type_mod.TypeKind.f32_type)) or
        tk == @intCast(u32, @enumToInt(type_mod.TypeKind.f64_type)))
    {
        if (node.kind == AstKind.float_literal) {
            var fb = ec.store.float_values.items[@intCast(usize, ast_mod.astStoreNodePayload(ec.store, node_idx))];
            // Z98 @bitCast is integer-only; transport the f64 bit pattern.
            var fbp: *u64 = @ptrCast(*u64, &fb);
            return tableAddNode(ec.tbl, CIE_FLOAT, fbp.*, @intCast(u32, 0), @intCast(u32, 0));
        }
        return null;
    }

    // enum targets: literal + scalar folds (tag ints)
    if (tk == @intCast(u32, @enumToInt(type_mod.TypeKind.enum_type))) {
        return classifyScalar(ec, module_id, node_idx, type_id, depth);
    }

    // scalar-ish / untyped: int, bool, char, integer_literal_type, etc.
    return classifyScalar(ec, module_id, node_idx, type_id, depth);
}
