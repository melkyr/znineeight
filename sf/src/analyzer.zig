const AstStore = @import("ast.zig").AstStore;
const AstKind = @import("ast.zig").AstKind;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const StringInterner = @import("string_interner.zig").StringInterner;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const Sand = @import("allocator.zig").Sand;
const ast_mod = @import("ast.zig");
const alloc_mod = @import("allocator.zig");
const StateMap = @import("state_map.zig").StateMap;
const smap_mod = @import("state_map.zig");
const type_mod = @import("type_registry.zig");
const diag_mod = @import("diagnostics.zig");
const interner_mod = @import("string_interner.zig");
const SymbolTable = @import("symbol_table.zig").SymbolTable;
const SymbolKind = @import("symbol_table.zig").SymbolKind;
const sym_mod = @import("symbol_table.zig");

pub const DeferEntry = struct {
    kind: u8,
    stmt_idx: u32,
    scope_depth: u32,
};

pub const PtrState = enum(u8) {
    uninit,
    is_null,
    safe,
    maybe,
};

pub const Provenance = enum(u8) {
    unknown = 0,
    local = 1,
    param = 2,
    param_addr = 3,
    global = 4,
    heap = 5,
};

pub const AllocState = enum(u8) {
    untracked = 0,
    allocated = 1,
    freed = 2,
    returned_val = 3,
    transferred = 4,
    unknown = 5,
};

fn resolveOrigin(ctx: *AnalyzerContext, expr_idx: u32) ?u32 {
    if (expr_idx == @intCast(u32, 0)) return null;
    var node = ctx.store.nodes.items[@intCast(usize, expr_idx)];
    var kind = node.kind;
    if (kind == AstKind.ident_expr) return node.payload;
    if (kind == AstKind.field_access) return resolveOrigin(ctx, node.child_0);
    if (kind == AstKind.index_access) return resolveOrigin(ctx, node.child_0);
    if (kind == AstKind.deref) return null;
    if (kind == AstKind.slice_expr) return resolveOrigin(ctx, node.child_0);
    return null;
}

pub fn classifyProvenance(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32) u8 {
    if (expr_idx == @intCast(u32, 0)) return @intCast(u8, @enumToInt(Provenance.unknown));
    var node = ctx.store.nodes.items[@intCast(usize, expr_idx)];
    var kind = node.kind;
    if (kind == AstKind.address_of) {
        var found_name_id = resolveOrigin(ctx, node.child_0);
        if (found_name_id) |name_id| {
            var sym = sym_mod.symbolTableLookup(ctx.symbols, name_id);
            if (sym) |s| {
                if (s.kind == SymbolKind.local) return @intCast(u8, @enumToInt(Provenance.local));
                if (s.kind == SymbolKind.param) return @intCast(u8, @enumToInt(Provenance.param_addr));
                if (s.kind == SymbolKind.global) return @intCast(u8, @enumToInt(Provenance.global));
            }
        }
        return @intCast(u8, @enumToInt(Provenance.unknown));
    }
    if (kind == AstKind.fn_call) return @intCast(u8, @enumToInt(Provenance.heap));
    if (kind == AstKind.field_access) {
        var base_id = resolveOrigin(ctx, node.child_0);
        if (base_id) |bid| {
            var result = smap_mod.stateMapGet(state, bid);
            if (result) |v| return v;
        }
        return @intCast(u8, @enumToInt(Provenance.unknown));
    }
    if (kind == AstKind.slice_expr) {
        var base_id = resolveOrigin(ctx, node.child_0);
        if (base_id) |bid| {
            var result = smap_mod.stateMapGet(state, bid);
            if (result) |v| return v;
        }
        return @intCast(u8, @enumToInt(Provenance.unknown));
    }
    if (kind == AstKind.ident_expr) {
        var result = smap_mod.stateMapGet(state, node.payload);
        if (result) |v| return v;
        return @intCast(u8, @enumToInt(Provenance.unknown));
    }
    return @intCast(u8, @enumToInt(Provenance.unknown));
}

pub fn checkReturnProvenance(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32, ret_node_idx: u32) void {
    var prov = classifyProvenance(ctx, state, expr_idx);
    var rnode = ctx.store.nodes.items[@intCast(usize, ret_node_idx)];
    var start = rnode.span_start;
    var end = rnode.span_start + @intCast(u32, rnode.span_len);
    var expr_node = ctx.store.nodes.items[@intCast(usize, expr_idx)];
    var pl = @intCast(u8, @enumToInt(Provenance.local));
    var ppa = @intCast(u8, @enumToInt(Provenance.param_addr));
    if (prov == pl) {
        if (expr_node.kind == AstKind.address_of) {
            var msg: []const u8 = "returning address of local variable";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2020_RETURNING_ADDRESS_OF_LOCAL)), @intCast(u32, 0), start, end, msg);
            return;
        }
        if (expr_node.kind == AstKind.slice_expr) {
            var msg: []const u8 = "returning slice of local array";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6011_RETURNING_SLICE_OF_LOCAL)), @intCast(u32, 0), start, end, msg);
            return;
        }
        var msg: []const u8 = "returning pointer to local via variable";
        diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6010_RETURNING_POINTER_VIA_VARIABLE)), @intCast(u32, 0), start, end, msg);
        return;
    }
    if (prov == ppa) {
        var msg: []const u8 = "returning address of function parameter";
        diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2021_RETURNING_ADDRESS_OF_PARAM)), @intCast(u32, 0), start, end, msg);
        return;
    }
}

pub fn isAllocCall(ctx: *AnalyzerContext, expr_idx: u32) bool {
    if (expr_idx == @intCast(u32, 0)) return false;
    var node = ctx.store.nodes.items[@intCast(usize, expr_idx)];
    if (node.kind == AstKind.try_expr) return isAllocCall(ctx, node.child_0);
    if (node.kind != AstKind.fn_call) return false;
    var callee = ctx.store.nodes.items[@intCast(usize, node.child_0)];
    if (callee.kind != AstKind.ident_expr) return false;
    var name_id = callee.payload;
    var sand_nid = interner_mod.stringInternerIntern(ctx.interner, "sandAlloc");
    if (name_id == sand_nid) return true;
    var sand2_nid = interner_mod.stringInternerIntern(ctx.interner, "sand_alloc");
    if (name_id == sand2_nid) return true;
    var arena_nid = interner_mod.stringInternerIntern(ctx.interner, "arena_alloc");
    if (name_id == arena_nid) return true;
    return false;
}

pub fn isFreeCall(ctx: *AnalyzerContext, expr_idx: u32) ?u32 {
    if (expr_idx == @intCast(u32, 0)) return null;
    var node = ctx.store.nodes.items[@intCast(usize, expr_idx)];
    if (node.kind != AstKind.fn_call) return null;
    var callee = ctx.store.nodes.items[@intCast(usize, node.child_0)];
    if (callee.kind != AstKind.ident_expr) return null;
    var name_id = callee.payload;
    var arena_free_nid = interner_mod.stringInternerIntern(ctx.interner, "arena_free");
    var sand_free_nid = interner_mod.stringInternerIntern(ctx.interner, "sandFree");
    if (name_id != arena_free_nid and name_id != sand_free_nid) return null;
    var args = ast_mod.astStoreGetExtraChildren(ctx.store, node.payload);
    if (args.len < @intCast(usize, 2)) return null;
    var ptr_arg = ctx.store.nodes.items[@intCast(usize, args[1])];
    if (ptr_arg.kind == AstKind.ident_expr) return ptr_arg.payload;
    return null;
}

pub fn compositeNameId(interner: *StringInterner, base_id: u32, field_id: u32) u32 {
    var base_str = interner_mod.stringInternerGet(interner, base_id);
    var field_str = interner_mod.stringInternerGet(interner, field_id);
    var buf: [128]u8 = undefined;
    var pos: usize = 0;
    var i: usize = 0;
    while (i < base_str.len and pos < @intCast(usize, 127)) {
        buf[pos] = base_str[i];
        pos += 1;
        i += 1;
    }
    if (pos < @intCast(usize, 127)) {
        buf[pos] = @intCast(u8, '.');
        pos += 1;
    }
    i = 0;
    while (i < field_str.len and pos < @intCast(usize, 127)) {
        buf[pos] = field_str[i];
        pos += 1;
        i += 1;
    }
    return interner_mod.stringInternerIntern(interner, buf[0..pos]);
}

pub fn handleAllocCall(ctx: *AnalyzerContext, state: *StateMap, name_id: u32, init_idx: u32) void {
    if (!isAllocCall(ctx, init_idx)) return;
    smap_mod.stateMapSet(state, name_id, @enumToInt(AllocState.allocated));
}

pub fn handleFreeCall(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32) void {
    var name_id = isFreeCall(ctx, expr_idx) orelse return;
    if (name_id == @intCast(u32, 0)) return;
    var current = smap_mod.stateMapGet(state, name_id);
    var node = ctx.store.nodes.items[@intCast(usize, expr_idx)];
    if (current) |c| {
        if (c == @enumToInt(AllocState.allocated)) {
            smap_mod.stateMapSet(state, name_id, @enumToInt(AllocState.freed));
            return;
        }
        if (c == @enumToInt(AllocState.freed)) {
            var dmsg: []const u8 = "double free of pointer";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2005_DOUBLE_FREE)), @intCast(u32, 0), node.span_start, node.span_start + @intCast(u32, node.span_len), dmsg);
            return;
        }
        smap_mod.stateMapSet(state, name_id, @enumToInt(AllocState.freed));
    } else {
        var umsg: []const u8 = "freeing untracked pointer";
        diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6006_FREEING_UNTRACKED)), @intCast(u32, 0), node.span_start, node.span_start + @intCast(u32, node.span_len), umsg);
    }
}

pub fn checkLeaksOnScopeExit(ctx: *AnalyzerContext, state: *StateMap) void {
    var entries = smap_mod.stateMapGetEntries(state);
    var ei: usize = 0;
    while (ei < entries.len) : (ei += 1) {
        if (entries[ei].state == @enumToInt(AllocState.allocated)) {
            var lmsg: []const u8 = "memory leak: pointer not freed";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6005_MEMORY_LEAK)), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), lmsg);
        }
    }
}

pub fn handleAllocAssign(ctx: *AnalyzerContext, state: *StateMap, node_idx: u32) void {
    var node = ctx.store.nodes.items[@intCast(usize, node_idx)];
    var lhs_idx = node.child_0;
    var rhs_idx = node.child_1;
    var lhs_node = ctx.store.nodes.items[@intCast(usize, lhs_idx)];
    if (lhs_node.kind != AstKind.ident_expr) return;
    var current = smap_mod.stateMapGet(state, lhs_node.payload);
    if (current) |c| {
        if (c == @enumToInt(AllocState.allocated)) {
            var lmsg: []const u8 = "memory leak: pointer overwritten before free";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6005_MEMORY_LEAK)), @intCast(u32, 0), node.span_start, node.span_start + @intCast(u32, node.span_len), lmsg);
        }
    }
    if (isAllocCall(ctx, rhs_idx)) {
        smap_mod.stateMapSet(state, lhs_node.payload, @enumToInt(AllocState.allocated));
        return;
    }
    if (rhs_idx != @intCast(u32, 0)) {
        var rhs_node = ctx.store.nodes.items[@intCast(usize, rhs_idx)];
        if (rhs_node.kind == AstKind.null_literal) {
            smap_mod.stateMapSet(state, lhs_node.payload, @enumToInt(AllocState.untracked));
            return;
        }
    }
    smap_mod.stateMapSet(state, lhs_node.payload, @enumToInt(AllocState.unknown));
}

pub fn handleOwnershipReturn(ctx: *AnalyzerContext, state: *StateMap, ret_expr_idx: u32) void {
    if (ret_expr_idx == @intCast(u32, 0)) return;
    var node = ctx.store.nodes.items[@intCast(usize, ret_expr_idx)];
    if (node.kind != AstKind.ident_expr) return;
    var current = smap_mod.stateMapGet(state, node.payload);
    if (current) |c| {
        if (c == @enumToInt(AllocState.allocated)) {
            smap_mod.stateMapSet(state, node.payload, @enumToInt(AllocState.returned_val));
        }
    }
}

pub fn handleOwnershipPass(ctx: *AnalyzerContext, state: *StateMap, fn_call_idx: u32) void {
    if (fn_call_idx == @intCast(u32, 0)) return;
    var node = ctx.store.nodes.items[@intCast(usize, fn_call_idx)];
    if (node.kind != AstKind.fn_call) return;
    var args = ast_mod.astStoreGetExtraChildren(ctx.store, node.payload);
    var ai: usize = 0;
    while (ai < args.len) : (ai += 1) {
        var arg_node = ctx.store.nodes.items[@intCast(usize, args[ai])];
        if (arg_node.kind != AstKind.ident_expr) continue;
        var current = smap_mod.stateMapGet(state, arg_node.payload);
        if (current) |c| {
            if (c == @enumToInt(AllocState.allocated)) {
                smap_mod.stateMapSet(state, arg_node.payload, @enumToInt(AllocState.transferred));
                var tmsg: []const u8 = "ownership transferred to function";
                diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 2), @intCast(u16, @enumToInt(diag_mod.ErrorCode.INFO_7001_OWNERSHIP_TRANSFERRED)), @intCast(u32, 0), node.span_start, node.span_start + @intCast(u32, node.span_len), tmsg);
            }
        }
    }
}

pub const NullGuard = struct {
    name_id: u32,
    is_not_null: u8,
};

pub const AnalyzerContext = struct {
    store: *AstStore,
    registry: *TypeRegistry,
    interner: *StringInterner,
    diag: *DiagnosticCollector,
    symbols: *SymbolTable,
    alloc: *Sand,
    current_fn_name: u32,
    defer_queue_items: [*]DeferEntry,
    defer_queue_len: usize,
    defer_queue_cap: usize,
    defer_queue_alloc: *Sand,
    current_depth: u32,
    null_analysis_mode: u8,
};

pub fn deferQueueEnsureCapacity(ctx: *AnalyzerContext, new_cap: usize) void {
    if (new_cap <= ctx.defer_queue_cap) return;
    var nc = new_cap;
    if (nc < ctx.defer_queue_cap * 2) nc = ctx.defer_queue_cap * 2;
    if (nc < 8) nc = 8;
    var raw = alloc_mod.sandAlloc(ctx.defer_queue_alloc, @intCast(usize, 12) * nc, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]DeferEntry, raw);
    var i: usize = 0;
    while (i < ctx.defer_queue_len) : (i += 1) { new_items[i] = ctx.defer_queue_items[i]; }
    ctx.defer_queue_items = new_items;
    ctx.defer_queue_cap = nc;
}

pub fn analyzeSignature(ctx: *AnalyzerContext, fn_node_idx: u32) void {
    var node = ctx.store.nodes.items[@intCast(usize, fn_node_idx)];
    if (node.kind != AstKind.fn_decl) return;
    var proto_idx = node.payload;
    var proto = ctx.store.fn_protos.items[@intCast(usize, proto_idx)];
    var param_payload: u32 = (@intCast(u32, proto.params_start) << @intCast(u32, 16)) | @intCast(u32, proto.params_count);
    var params = ast_mod.astStoreGetExtraChildren(ctx.store, param_payload);
    var pi: usize = 0;
    while (pi < params.len) : (pi += 1) {
        var pnode = ctx.store.nodes.items[@intCast(usize, params[pi])];
        var type_expr = pnode.child_0;
        if (type_expr != @intCast(u32, 0)) validateSignatureType(ctx, type_expr, @intCast(u32, 0));
    }
    var ret_node = proto.return_type_node;
    if (ret_node != @intCast(u32, 0)) validateSignatureType(ctx, ret_node, @intCast(u32, 1));
}

pub fn validateSignatureType(ctx: *AnalyzerContext, type_node_idx: u32, is_return: u32) void {
    var tnode = ctx.store.nodes.items[@intCast(usize, type_node_idx)];
    if (tnode.kind == AstKind.ident_expr) {
        var name_id = tnode.payload;
        var key = @intCast(u64, name_id);
        var tid = type_mod.nameCacheGet(ctx.registry, key);
        if (tid) |ttid| {
            var ty = ctx.registry.types_items[@intCast(usize, ttid)];
            if (ty.kind == type_mod.TypeKind.unresolved_name or
                ((ty.kind == type_mod.TypeKind.struct_type or
                  ty.kind == type_mod.TypeKind.union_type or
                  ty.kind == type_mod.TypeKind.tagged_union_type or
                  ty.kind == type_mod.TypeKind.enum_type) and ty.state != @intCast(u8, 2))) {
                var imsg: []const u8 = "incomplete type in function signature";
                diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2011_INCOMPLETE_TYPE)), @intCast(u32, 0), tnode.span_start, tnode.span_start + @intCast(u32, tnode.span_len), imsg);
            }
            if (ty.kind == type_mod.TypeKind.void_type and is_return == @intCast(u32, 0)) {
                var vmsg: []const u8 = "void not allowed as parameter type";
                diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2010_VOID_PARAMETER)), @intCast(u32, 0), tnode.span_start, tnode.span_start + @intCast(u32, tnode.span_len), vmsg);
            }
            if (is_return != @intCast(u32, 0)) {
                if (ty.size > @intCast(u32, 64)) {
                    var wmsg: []const u8 = "return type exceeds 64 bytes; may cause issues on MSVC 6.0";
                    diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_7010_LARGE_RETURN)), @intCast(u32, 0), tnode.span_start, tnode.span_start + @intCast(u32, tnode.span_len), wmsg);
                }
            }
        }
        var anytype_nid = interner_mod.stringInternerIntern(ctx.interner, "anytype");
        if (name_id == anytype_nid) {
            var amsg: []const u8 = "anytype not supported in Z98";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2012_ANYTYPE_NOT_SUPPORTED)), @intCast(u32, 0), tnode.span_start, tnode.span_start + @intCast(u32, tnode.span_len), amsg);
        }
    }
}

pub fn analyzeExpr(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32) void {
    if (expr_idx == @intCast(u32, 0)) return;
    var node = ctx.store.nodes.items[@intCast(usize, expr_idx)];
    var kind = node.kind;
    if (kind == AstKind.deref) {
        var st = classifyExpr(ctx, state, node.child_0);
        var start = node.span_start;
        var end = node.span_start + @intCast(u32, node.span_len);
        if (st == @enumToInt(PtrState.is_null)) {
            var msg: []const u8 = "definite null pointer dereference";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2004_DEFINITE_NULL_DEREF)), @intCast(u32, 0), start, end, msg);
        } else if (st == @enumToInt(PtrState.uninit)) {
            var msg: []const u8 = "dereference of uninitialized pointer";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6001_UNINIT_DEREF)), @intCast(u32, 0), start, end, msg);
        } else if (st == @enumToInt(PtrState.maybe)) {
            var msg: []const u8 = "potential null pointer dereference";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6002_POTENTIAL_NULL_DEREF)), @intCast(u32, 0), start, end, msg);
        }
        return;
    }
    if (kind == AstKind.index_access) {
        analyzeExpr(ctx, state, node.child_0);
        return;
    }
    if (kind == AstKind.field_access) {
        analyzeExpr(ctx, state, node.child_0);
        return;
    }
    if (kind == AstKind.fn_call) {
        var args = ast_mod.astStoreGetExtraChildren(ctx.store, node.payload);
        var ai: usize = 0;
        while (ai < args.len) : (ai += 1) {
            analyzeExpr(ctx, state, args[ai]);
        }
        return;
    }
    if (kind == AstKind.assign) {
        analyzeExpr(ctx, state, node.child_1);
        var lhs_node = ctx.store.nodes.items[@intCast(usize, node.child_0)];
        if (lhs_node.kind == AstKind.ident_expr) {
            var new_st = classifyExpr(ctx, state, node.child_1);
            smap_mod.stateMapSet(state, lhs_node.payload, new_st);
        }
        return;
    }
    if (node.child_0 != @intCast(u32, 0)) analyzeExpr(ctx, state, node.child_0);
    if (node.child_1 != @intCast(u32, 0)) analyzeExpr(ctx, state, node.child_1);
    if (node.child_2 != @intCast(u32, 0)) analyzeExpr(ctx, state, node.child_2);
}

pub fn classifyExpr(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32) u8 {
    if (expr_idx == @intCast(u32, 0)) return @enumToInt(PtrState.uninit);
    var node = ctx.store.nodes.items[@intCast(usize, expr_idx)];
    var kind = node.kind;
    if (kind == AstKind.null_literal) return @enumToInt(PtrState.is_null);
    if (kind == AstKind.address_of) return @enumToInt(PtrState.safe);
    if (kind == AstKind.try_expr) return @enumToInt(PtrState.safe);
    if (kind == AstKind.fn_call) return @enumToInt(PtrState.maybe);
    if (kind == AstKind.orelse_expr) return @enumToInt(PtrState.safe);
    if (kind == AstKind.catch_expr) return @enumToInt(PtrState.safe);
    if (kind == AstKind.int_literal) {
        var val = ctx.store.int_values.items[@intCast(usize, node.payload)];
        if (val == @intCast(u64, 0)) return @enumToInt(PtrState.is_null);
        return @enumToInt(PtrState.safe);
    }
    if (kind == AstKind.ident_expr) {
        var result = smap_mod.stateMapGet(state, node.payload);
        if (result) |v| return v;
    }
    return @enumToInt(PtrState.maybe);
}

fn isNullExpr(store: *AstStore, idx: u32) u8 {
    if (idx == @intCast(u32, 0)) return @intCast(u8, 0);
    var node = store.nodes.items[@intCast(usize, idx)];
    if (node.kind == AstKind.null_literal) return @intCast(u8, 1);
    if (node.kind == AstKind.int_literal) {
        var val = store.int_values.items[@intCast(usize, node.payload)];
        if (val == @intCast(u64, 0)) return @intCast(u8, 1);
    }
    return @intCast(u8, 0);
}

fn isIdentExpr(store: *AstStore, idx: u32) ?u32 {
    if (idx == @intCast(u32, 0)) return null;
    var node = store.nodes.items[@intCast(usize, idx)];
    if (node.kind == AstKind.ident_expr) return node.payload;
    return null;
}

pub fn detectNullGuard(store: *AstStore, cond_idx: u32) ?NullGuard {
    if (cond_idx == @intCast(u32, 0)) return null;
    var cond = store.nodes.items[@intCast(usize, cond_idx)];
    var ck = cond.kind;
    if (ck == AstKind.cmp_ne) {
        var n0 = isNullExpr(store, cond.child_0);
        if (n0 != 0) { var id1 = isIdentExpr(store, cond.child_1); if (id1) |nid| return NullGuard{ .name_id = nid, .is_not_null = @intCast(u8, 1) }; }
        var n1 = isNullExpr(store, cond.child_1);
        if (n1 != 0) { var id0 = isIdentExpr(store, cond.child_0); if (id0) |nid| return NullGuard{ .name_id = nid, .is_not_null = @intCast(u8, 1) }; }
        return null;
    }
    if (ck == AstKind.cmp_eq) {
        var n0 = isNullExpr(store, cond.child_0);
        if (n0 != 0) { var id1 = isIdentExpr(store, cond.child_1); if (id1) |nid| return NullGuard{ .name_id = nid, .is_not_null = @intCast(u8, 0) }; }
        var n1 = isNullExpr(store, cond.child_1);
        if (n1 != 0) { var id0 = isIdentExpr(store, cond.child_0); if (id0) |nid| return NullGuard{ .name_id = nid, .is_not_null = @intCast(u8, 0) }; }
        return null;
    }
    if (ck == AstKind.ident_expr) {
        return NullGuard{ .name_id = cond.payload, .is_not_null = @intCast(u8, 1) };
    }
    if (ck == AstKind.bool_not) {
        var inner = detectNullGuard(store, cond.child_0);
        if (inner) |g| return NullGuard{ .name_id = g.name_id, .is_not_null = @intCast(u8, 1 - g.is_not_null) };
        return null;
    }
    return null;
}

pub fn applyNullGuardRefinement(store: *AstStore, cond_idx: u32, then_state: *StateMap, else_state: *StateMap) void {
    var guard = detectNullGuard(store, cond_idx);
    if (guard) |g| {
        if (g.is_not_null != 0) {
            smap_mod.stateMapSet(then_state, g.name_id, @enumToInt(PtrState.safe));
            smap_mod.stateMapSet(else_state, g.name_id, @enumToInt(PtrState.is_null));
        } else {
            smap_mod.stateMapSet(then_state, g.name_id, @enumToInt(PtrState.is_null));
            smap_mod.stateMapSet(else_state, g.name_id, @enumToInt(PtrState.safe));
        }
    }
}

pub fn handleNullVarDecl(ctx: *AnalyzerContext, state: *StateMap, node_idx: u32) void {
    var node = ctx.store.nodes.items[@intCast(usize, node_idx)];
    var name_id = node.payload;
    var init_idx = node.child_1;
    if (init_idx != @intCast(u32, 0)) {
        var st = classifyExpr(ctx, state, init_idx);
        smap_mod.stateMapSet(state, name_id, st);
    } else {
        smap_mod.stateMapSet(state, name_id, @enumToInt(PtrState.uninit));
    }
}

pub fn handleNullAssign(ctx: *AnalyzerContext, state: *StateMap, node_idx: u32) void {
    var node = ctx.store.nodes.items[@intCast(usize, node_idx)];
    var rhs = node.child_1;
    var rhs_state = classifyExpr(ctx, state, rhs);
    var lhs_idx = node.child_0;
    var lhs_node = ctx.store.nodes.items[@intCast(usize, lhs_idx)];
    if (lhs_node.kind == AstKind.ident_expr) {
        smap_mod.stateMapSet(state, lhs_node.payload, rhs_state);
    }
}

pub fn executeDeferQueue(ctx: *AnalyzerContext, state: *StateMap, target_depth: u32, is_error: u8, visit_fn: fn(*AnalyzerContext, *StateMap, u32) void) void {
    while (ctx.defer_queue_len > @intCast(usize, 0)) {
        var idx = ctx.defer_queue_len - @intCast(usize, 1);
        var entry = ctx.defer_queue_items[idx];
        if (entry.scope_depth < target_depth) break;
        ctx.defer_queue_len = idx;
        if (entry.kind == @intCast(u8, 0)) {
            visit_fn(ctx, state, entry.stmt_idx);
        } else if (entry.kind == @intCast(u8, 1) and is_error != @intCast(u8, 0)) {
            visit_fn(ctx, state, entry.stmt_idx);
        }
    }
}

pub fn walkBlock(ctx: *AnalyzerContext, state: *StateMap, block_idx: u32, visit_fn: fn(*AnalyzerContext, *StateMap, u32) void) void {
    if (block_idx == @intCast(u32, 0)) return;
    var node = ctx.store.nodes.items[@intCast(usize, block_idx)];
    if (node.kind != AstKind.block) {
        visit_fn(ctx, state, block_idx);
        return;
    }
    var saved_depth = ctx.current_depth;
    ctx.current_depth += 1;
    var children = ast_mod.astStoreGetExtraChildren(ctx.store, node.payload);
    var i: usize = 0;
    while (i < children.len) : (i += 1) {
        visit_fn(ctx, state, children[i]);
    }
    executeDeferQueue(ctx, state, saved_depth, @intCast(u8, 0), visit_fn);
    checkLeaksOnScopeExit(ctx, state);
    ctx.current_depth = saved_depth;
}

pub fn visitStatement(ctx: *AnalyzerContext, state: *StateMap, node_idx: u32, on_stmt: fn(*AnalyzerContext, *StateMap, u32) void) void {
    if (node_idx == @intCast(u32, 0)) return;
    var node = ctx.store.nodes.items[@intCast(usize, node_idx)];
    var kind = node.kind;
    if (kind == AstKind.if_stmt or kind == AstKind.if_capture) {
        analyzeExpr(ctx, state, node.child_0);
        var then_state = smap_mod.stateMapFork(state, ctx.alloc);
        var else_state = smap_mod.stateMapFork(state, ctx.alloc);
        if (ctx.null_analysis_mode != @intCast(u8, 0)) {
            applyNullGuardRefinement(ctx.store, node.child_0, then_state, else_state);
            if (kind == AstKind.if_capture) {
                smap_mod.stateMapSet(then_state, node.payload, @enumToInt(PtrState.safe));
            }
        }
        walkBlock(ctx, then_state, node.child_1, on_stmt);
        if (node.child_2 != @intCast(u32, 0)) walkBlock(ctx, else_state, node.child_2, on_stmt);
        smap_mod.stateMapMergeStates(state, then_state, else_state, @intCast(u8, 99));
    } else if (kind == AstKind.while_stmt or kind == AstKind.while_capture) {
        analyzeExpr(ctx, state, node.child_0);
        var body_state = smap_mod.stateMapFork(state, ctx.alloc);
        if (ctx.null_analysis_mode != @intCast(u8, 0) and kind == AstKind.while_capture) {
            smap_mod.stateMapSet(body_state, node.payload, @enumToInt(PtrState.safe));
        }
        walkBlock(ctx, body_state, node.child_1, on_stmt);
        smap_mod.stateMapMergeStates(state, state, body_state, @intCast(u8, 99));
    } else if (kind == AstKind.switch_expr) {
        var prongs = ast_mod.astStoreGetExtraChildren(ctx.store, node.payload);
        var si: usize = 0;
        while (si < prongs.len) : (si += 1) {
            var prong = ctx.store.nodes.items[@intCast(usize, prongs[si])];
            var ps = smap_mod.stateMapFork(state, ctx.alloc);
            walkBlock(ctx, ps, prong.child_0, on_stmt);
            smap_mod.stateMapMergeStates(state, state, ps, @intCast(u8, 99));
        }
    } else if (kind == AstKind.for_stmt) {
        var body_state = smap_mod.stateMapFork(state, ctx.alloc);
        walkBlock(ctx, body_state, node.child_0, on_stmt);
        smap_mod.stateMapMergeStates(state, state, body_state, @intCast(u8, 99));
    } else if (kind == AstKind.return_stmt) {
        if (node.child_0 != @intCast(u32, 0)) {
            checkReturnProvenance(ctx, state, node.child_0, node_idx);
            handleOwnershipReturn(ctx, state, node.child_0);
        }
        on_stmt(ctx, state, node_idx);
    } else if (kind == AstKind.defer_stmt or kind == AstKind.errdefer_stmt) {
        var dk: u8 = @intCast(u8, 0);
        if (kind == AstKind.errdefer_stmt) dk = @intCast(u8, 1);
        deferQueueEnsureCapacity(ctx, ctx.defer_queue_len + @intCast(usize, 1));
        ctx.defer_queue_items[ctx.defer_queue_len] = DeferEntry{ .kind = dk, .stmt_idx = node_idx, .scope_depth = ctx.current_depth };
        ctx.defer_queue_len += 1;
    } else if (ctx.null_analysis_mode != @intCast(u8, 0) and kind == AstKind.var_decl) {
        handleNullVarDecl(ctx, state, node_idx);
        on_stmt(ctx, state, node_idx);
    } else if (ctx.null_analysis_mode != @intCast(u8, 0) and kind == AstKind.assign) {
        handleNullAssign(ctx, state, node_idx);
        on_stmt(ctx, state, node_idx);
    } else if (kind == AstKind.expr_stmt) {
        analyzeExpr(ctx, state, node.child_0);
    } else {
        on_stmt(ctx, state, node_idx);
    }
}
