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

pub const DeferEntry = struct {
    kind: u8,
    stmt_idx: u32,
    scope_depth: u32,
};

pub const AnalyzerContext = struct {
    store: *AstStore,
    registry: *TypeRegistry,
    interner: *StringInterner,
    diag: *DiagnosticCollector,
    alloc: *Sand,
    current_fn_name: u32,
    defer_queue_items: [*]DeferEntry,
    defer_queue_len: usize,
    defer_queue_cap: usize,
    defer_queue_alloc: *Sand,
    current_depth: u32,
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
            if (ty.kind == type_mod.TypeKind.void_type and is_return == @intCast(u32, 0)) {
                var vmsg: []const u8 = "void not allowed as parameter type";
            }
            if (is_return != @intCast(u32, 0)) {
                if (ty.size > @intCast(u32, 64)) {
                    var wmsg: []const u8 = "return type exceeds 64 bytes; may cause issues on MSVC 6.0";
                }
            }
        }
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
    ctx.current_depth = saved_depth;
}

pub fn visitStatement(ctx: *AnalyzerContext, state: *StateMap, node_idx: u32, on_stmt: fn(*AnalyzerContext, *StateMap, u32) void) void {
    if (node_idx == @intCast(u32, 0)) return;
    var node = ctx.store.nodes.items[@intCast(usize, node_idx)];
    var kind = node.kind;
    if (kind == AstKind.if_stmt) {
        var then_state = smap_mod.stateMapFork(state, ctx.alloc);
        var else_state = smap_mod.stateMapFork(state, ctx.alloc);
        walkBlock(ctx, then_state, node.child_1, on_stmt);
        if (node.child_2 != @intCast(u32, 0)) walkBlock(ctx, else_state, node.child_2, on_stmt);
        smap_mod.stateMapMergeStates(state, then_state, else_state, @intCast(u8, 99));
    } else if (kind == AstKind.while_stmt) {
        var body_state = smap_mod.stateMapFork(state, ctx.alloc);
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
    } else if (kind == AstKind.defer_stmt or kind == AstKind.errdefer_stmt) {
        var dk: u8 = @intCast(u8, 0);
        if (kind == AstKind.errdefer_stmt) dk = @intCast(u8, 1);
        deferQueueEnsureCapacity(ctx, ctx.defer_queue_len + @intCast(usize, 1));
        ctx.defer_queue_items[ctx.defer_queue_len] = DeferEntry{ .kind = dk, .stmt_idx = node_idx, .scope_depth = ctx.current_depth };
        ctx.defer_queue_len += 1;
    } else {
        on_stmt(ctx, state, node_idx);
    }
}
