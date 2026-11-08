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
const SymbolRegistry = @import("symbol_table.zig").SymbolRegistry;
const ce_mod = @import("comptime_eval.zig");
const import_resolver = @import("import_resolver.zig");
const itoa_mod = @import("util/itoa.zig");

pub const DeferEntry = struct {
    kind: u8,
    stmt_idx: u32,
    scope_depth: u32,
};

pub const PtrState = enum(u8) {
    uninit = 10,
    is_null = 11,
    safe = 12,
    maybe = 13,
};

pub const Provenance = enum(u8) {
    unknown = 0,
    local = 1,
    param = 2,
    param_addr = 3,
    global = 4,
    heap = 5,
    // T5 (§2.1 base): pointer-like parameter / caller-owned pointee. Values
    // and interiors are safe to return; the bare address of the binding still
    // dangles (classified param_addr).
    external = 6,
};

pub const AllocState = enum(u8) {
    untracked = 0,
    allocated = 1,
    freed = 2,
    returned_val = 3,
    transferred = 4,
    unknown = 5,
    // Same-block use after free already reported: the name stays freed for
    // double-free purposes but a later use does not emit a second ERR_2006.
    freed_reported = 6,
};

fn identNameId(store: *AstStore, node_idx: u32) u32 {
    return ast_mod.astStoreIdentifier(store, node_idx);
}

fn resolveOrigin(ctx: *AnalyzerContext, expr_idx: u32) ?u32 {
    if (expr_idx == @intCast(u32, 0)) return null;
    var node = ast_mod.astStoreNodeAt(ctx.store, expr_idx);
    var kind = node.kind;
    if (kind == AstKind.ident_expr) return identNameId(ctx.store, expr_idx);
    if (kind == AstKind.field_access) return resolveOrigin(ctx, node.child_0);
    if (kind == AstKind.index_access) return resolveOrigin(ctx, node.child_0);
    if (kind == AstKind.deref) return null;
    if (kind == AstKind.slice_expr) return resolveOrigin(ctx, node.child_0);
    return null;
}

// DF-1: alias relation for allocation state. Aliases are scoped to the
// StateMap that records them, so a branch fork and its sibling cannot see each
// other's aliases and a merge imports only the relation both arms agree on.
// Every name keeps its own allocation-state copy (taken when the alias is
// created), so reassigning one name detaches it without rebinding the others.
const ALIAS_CAP: usize = 8192;
const AliasEntry = struct {
    scope: *StateMap,
    name_id: u32,
    canon_id: u32,
};
var alias_entries: [ALIAS_CAP]AliasEntry = undefined;
var alias_len: usize = 0;

// Scratch for branch merges. Merges run after a branch walk completes and do
// not nest, so static scratch is safe and keeps the per-function sand budget
// untouched.
var alias_merge_names: [ALIAS_CAP]u32 = undefined;
var alias_merge_a: [ALIAS_CAP]u32 = undefined;
var alias_merge_b: [ALIAS_CAP]u32 = undefined;

fn aliasReset() void {
    alias_len = @intCast(usize, 0);
}

fn aliasLookupCanon(scope: *StateMap, name_id: u32) ?u32 {
    var s: ?*StateMap = scope;
    while (s) |sp| {
        var i = alias_len;
        while (i > 0) {
            i -= 1;
            if (alias_entries[i].scope == sp and alias_entries[i].name_id == name_id) {
                return alias_entries[i].canon_id;
            }
        }
        s = sp.parent;
    }
    return null;
}

fn aliasResolveName(scope: *StateMap, name_id: u32) u32 {
    if (name_id == @intCast(u32, 0)) return name_id;
    var cur = name_id;
    var guard: u32 = 0;
    while (guard < @intCast(u32, 64)) : (guard += 1) {
        var next = aliasLookupCanon(scope, cur) orelse return cur;
        if (next == cur) return cur;
        cur = next;
    }
    return cur;
}

fn aliasSet(scope: *StateMap, name_id: u32, canon_id: u32) void {
    if (name_id == @intCast(u32, 0)) return;
    var i = alias_len;
    while (i > 0) {
        i -= 1;
        if (alias_entries[i].scope == scope and alias_entries[i].name_id == name_id) {
            alias_entries[i].canon_id = canon_id;
            return;
        }
    }
    if (alias_len >= ALIAS_CAP) return;
    alias_entries[alias_len] = AliasEntry{ .scope = scope, .name_id = name_id, .canon_id = canon_id };
    alias_len += 1;
}

fn aliasRecord(scope: *StateMap, alias_id: u32, canonical_id: u32) void {
    if (alias_id == @intCast(u32, 0)) return;
    if (canonical_id == @intCast(u32, 0)) return;
    var canon = aliasResolveName(scope, canonical_id);
    aliasSet(scope, alias_id, canon);
}

fn aliasForget(scope: *StateMap, name_id: u32) void {
    if (name_id == @intCast(u32, 0)) return;
    aliasSet(scope, name_id, name_id);
}

fn aliasCopyState(state: *StateMap, alias_id: u32, canonical_id: u32) void {
    if (alias_id == @intCast(u32, 0) or canonical_id == @intCast(u32, 0)) return;
    var canon = aliasResolveName(state, canonical_id);
    if (smap_mod.stateMapGet(state, canon)) |st| {
        smap_mod.stateMapSet(state, alias_id, st);
    }
}

fn aliasHasInbound(state: *StateMap, root: u32) bool {
    var i: usize = 0;
    while (i < alias_len) : (i += 1) {
        var name_id = alias_entries[i].name_id;
        if (name_id == root) continue;
        if (aliasResolveName(state, name_id) == root) return true;
    }
    return false;
}

fn aliasDetachInbound(state: *StateMap, root: u32) void {
    var snap = alias_len;
    var i: usize = 0;
    while (i < snap) : (i += 1) {
        var name_id = alias_entries[i].name_id;
        if (name_id == root) continue;
        if (aliasResolveName(state, name_id) == root) aliasForget(state, name_id);
    }
}

const AliasClassSummary = struct {
    saw_any: bool,
    saw_allocated: bool,
    saw_freed: bool,
    saw_unowned: bool,
};

fn aliasClassSummary(state: *StateMap, root: u32) AliasClassSummary {
    var out = AliasClassSummary{
        .saw_any = false,
        .saw_allocated = false,
        .saw_freed = false,
        .saw_unowned = false,
    };
    var i: usize = 0;
    if (smap_mod.stateMapGet(state, root)) |st| {
        out.saw_any = true;
        if (st == @enumToInt(AllocState.allocated)) out.saw_allocated = true;
        if (st == @enumToInt(AllocState.freed) or st == @enumToInt(AllocState.freed_reported)) out.saw_freed = true;
        if (st == @enumToInt(AllocState.transferred) or st == @enumToInt(AllocState.returned_val) or
            st == @enumToInt(AllocState.unknown)) out.saw_unowned = true;
    }
    i = 0;
    while (i < alias_len) : (i += 1) {
        var name_id = alias_entries[i].name_id;
        if (name_id == root) continue;
        if (aliasResolveName(state, name_id) != root) continue;
        if (smap_mod.stateMapGet(state, name_id)) |st| {
            out.saw_any = true;
            if (st == @enumToInt(AllocState.allocated)) out.saw_allocated = true;
            if (st == @enumToInt(AllocState.freed) or st == @enumToInt(AllocState.freed_reported)) out.saw_freed = true;
            if (st == @enumToInt(AllocState.transferred) or st == @enumToInt(AllocState.returned_val) or
                st == @enumToInt(AllocState.unknown)) out.saw_unowned = true;
        }
    }
    return out;
}

fn aliasSetClassState(state: *StateMap, root: u32, new_state: u8) void {
    smap_mod.stateMapSet(state, root, new_state);
    var snap = alias_len;
    var i: usize = 0;
    while (i < snap) : (i += 1) {
        var name_id = alias_entries[i].name_id;
        if (name_id == root) continue;
        if (aliasResolveName(state, name_id) == root) {
            smap_mod.stateMapSet(state, name_id, new_state);
        }
    }
}

fn aliasNameInList(names: []const u32, count: usize, name_id: u32) bool {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (names[i] == name_id) return true;
    }
    return false;
}

// Merge the alias relation of one loop/switch body into its enclosing state.
// Only names touched in the body are considered; a body that disagrees with the
// pre-body relation tombstones the parent relation (conservative).
fn aliasMergeBranchInto(parent: *StateMap, body: *StateMap) void {
    var n: usize = 0;
    var i: usize = 0;
    while (i < alias_len) : (i += 1) {
        var e = alias_entries[i];
        if (e.scope != body) continue;
        if (aliasNameInList(alias_merge_names[0..], n, e.name_id)) continue;
        if (n >= ALIAS_CAP) break;
        alias_merge_names[n] = e.name_id;
        n += 1;
    }
    i = 0;
    while (i < n) : (i += 1) {
        alias_merge_a[i] = aliasResolveName(parent, alias_merge_names[i]);
        alias_merge_b[i] = aliasResolveName(body, alias_merge_names[i]);
    }
    i = 0;
    while (i < n) : (i += 1) {
        if (alias_merge_a[i] == alias_merge_b[i]) {
            aliasSet(parent, alias_merge_names[i], alias_merge_a[i]);
        } else {
            aliasForget(parent, alias_merge_names[i]);
        }
    }
}

// Merge a fork pair after `stateMapMergeStates`. A relation survives only when
// both arms resolve the name the same way.
fn aliasMergeBranches(parent: *StateMap, branch_a: *StateMap, branch_b: *StateMap) void {
    var n: usize = 0;
    var i: usize = 0;
    while (i < alias_len) : (i += 1) {
        var e = alias_entries[i];
        if (e.scope != branch_a and e.scope != branch_b) continue;
        if (aliasNameInList(alias_merge_names[0..], n, e.name_id)) continue;
        if (n >= ALIAS_CAP) break;
        alias_merge_names[n] = e.name_id;
        n += 1;
    }
    i = 0;
    while (i < n) : (i += 1) {
        alias_merge_a[i] = aliasResolveName(branch_a, alias_merge_names[i]);
        alias_merge_b[i] = aliasResolveName(branch_b, alias_merge_names[i]);
    }
    i = 0;
    while (i < n) : (i += 1) {
        if (alias_merge_a[i] == alias_merge_b[i]) {
            aliasSet(parent, alias_merge_names[i], alias_merge_a[i]);
        } else {
            aliasForget(parent, alias_merge_names[i]);
        }
    }
}


// DF-3: allocator handles seen as the first argument of a recognized
// alloc/free call. They are never ownership transfers.
const HANDLE_CAP: usize = 256;
var handle_names: [HANDLE_CAP]u32 = undefined;
var handle_len: usize = 0;

fn handleReset() void {
    handle_len = @intCast(usize, 0);
}

fn handleRecord(name_id: u32) void {
    if (name_id == @intCast(u32, 0)) return;
    var i: usize = 0;
    while (i < handle_len) : (i += 1) {
        if (handle_names[i] == name_id) return;
    }
    if (handle_len >= HANDLE_CAP) return;
    handle_names[handle_len] = name_id;
    handle_len += 1;
}

fn handleIs(name_id: u32) bool {
    var i: usize = 0;
    while (i < handle_len) : (i += 1) {
        if (handle_names[i] == name_id) return true;
    }
    return false;
}

fn indexKeyNameId(ctx: *AnalyzerContext, expr_idx: u32) ?u32 {
    if (expr_idx == @intCast(u32, 0)) return null;
    var node = ast_mod.astStoreNodeAt(ctx.store, expr_idx);
    if (node.kind == AstKind.ident_expr) return identNameId(ctx.store, expr_idx);
    if (node.kind != AstKind.int_literal) return null;
    var buf: [24]u8 = undefined;
    var len = itoa_mod.itoa64(ast_mod.astStoreIntValue(ctx.store, expr_idx), buf[0..]);
    var last = @intCast(usize, buf.len) - @intCast(usize, 1);
    var start = last - @intCast(usize, len);
    return interner_mod.stringInternerIntern(ctx.interner, buf[start..last]);
}

// DF-2: the identity of an assignable/freeable expression. Field and index
// chains compose onto the base identity (`st.p`, `arr.0`) so allocation,
// aliasing, and free all key the same state.
fn resolveLValueIdentity(ctx: *AnalyzerContext, node_idx: u32) ?u32 {
    if (node_idx == @intCast(u32, 0)) return null;
    var node = ast_mod.astStoreNodeAt(ctx.store, node_idx);
    var kind = node.kind;
    if (kind == AstKind.ident_expr) return identNameId(ctx.store, node_idx);
    if (kind == AstKind.paren_expr) return resolveLValueIdentity(ctx, node.child_0);
    if (kind == AstKind.field_access) {
        var base = resolveLValueIdentity(ctx, node.child_0) orelse return null;
        var field_id = ast_mod.astStoreNodePayload(ctx.store, node_idx);
        if (field_id == @intCast(u32, 0)) return null;
        return compositeNameId(ctx.interner, base, field_id);
    }
    if (kind == AstKind.index_access) {
        var base = resolveLValueIdentity(ctx, node.child_0) orelse return null;
        var key = indexKeyNameId(ctx, node.child_1) orelse return null;
        return compositeNameId(ctx.interner, base, key);
    }
    return null;
}

pub fn classifyProvenance(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32) u8 {
    if (expr_idx == @intCast(u32, 0)) return @intCast(u8, @enumToInt(Provenance.unknown));
    var node = ast_mod.astStoreNodeAt(ctx.store, expr_idx);
    var kind = node.kind;
    if (kind == AstKind.address_of) {
        // T5 (§2.1 base): classify the STORAGE an address names. A bare
        // `&name` is the binding's own call-frame slot (dangles for params); an
        // interior `&name.field`/`&name[i]` follows the pointee's provenance
        // (pointer-like params are caller-owned — `external`).
        var t5_is_interior: u8 = @intCast(u8, 0);
        if (node.child_0 != @intCast(u32, 0)) {
            var t5_onode = ast_mod.astStoreNodeAt(ctx.store, node.child_0);
            if (t5_onode.kind != AstKind.ident_expr) t5_is_interior = @intCast(u8, 1);
        }
        var found_name_id = resolveOrigin(ctx, node.child_0);
        if (found_name_id) |name_id| {
            var t5_base: u8 = @intCast(u8, 255);
            var sym = sym_mod.symbolTableLookup(ctx.symbols, name_id);
            if (sym) |s| {
                if (s.kind == SymbolKind.local) {
                    t5_base = @intCast(u8, @enumToInt(Provenance.local));
                } else if (s.kind == SymbolKind.param) {
                    t5_base = @intCast(u8, @enumToInt(Provenance.param));
                } else if (s.kind == SymbolKind.global) {
                    t5_base = @intCast(u8, @enumToInt(Provenance.global));
                } else {
                    return @intCast(u8, @enumToInt(Provenance.unknown));
                }
            } else {
                // The real pipeline's symbol tables hold module-level names
                // only (symbol_registrator.zig) — fn locals/params/captures
                // are absent. Params arrive seeded (`param`/`external`),
                // vars/captures carry their tracked value provenance, and an
                // untracked binding is a conservative local.
                var pv = smap_mod.stateMapGet(state, name_id);
                if (pv) |v| {
                    t5_base = v;
                } else {
                    t5_base = @intCast(u8, @enumToInt(Provenance.local));
                }
            }
            if (t5_is_interior == @intCast(u8, 0)) {
                if (t5_base == @intCast(u8, @enumToInt(Provenance.global))) return @intCast(u8, @enumToInt(Provenance.global));
                if (t5_base == @intCast(u8, @enumToInt(Provenance.param)) or
                    t5_base == @intCast(u8, @enumToInt(Provenance.external)) or
                    t5_base == @intCast(u8, @enumToInt(Provenance.param_addr))) {
                    return @intCast(u8, @enumToInt(Provenance.param_addr));
                }
                return @intCast(u8, @enumToInt(Provenance.local));
            }
            if (t5_base == @intCast(u8, @enumToInt(Provenance.external))) return @intCast(u8, @enumToInt(Provenance.external));
            if (t5_base == @intCast(u8, @enumToInt(Provenance.global))) return @intCast(u8, @enumToInt(Provenance.global));
            if (t5_base == @intCast(u8, @enumToInt(Provenance.heap))) return @intCast(u8, @enumToInt(Provenance.heap));
            if (t5_base == @intCast(u8, @enumToInt(Provenance.param))) return @intCast(u8, @enumToInt(Provenance.param_addr));
            return @intCast(u8, @enumToInt(Provenance.local));
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
        var result = smap_mod.stateMapGet(state, identNameId(ctx.store, expr_idx));
        if (result) |v| return v;
        return @intCast(u8, @enumToInt(Provenance.unknown));
    }
    return @intCast(u8, @enumToInt(Provenance.unknown));
}

pub fn checkReturnProvenance(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32, ret_node_idx: u32) void {
    var prov = classifyProvenance(ctx, state, expr_idx);
    var rnode = ast_mod.astStoreNodeAt(ctx.store, ret_node_idx);
    var start = rnode.span_start;
    var end: u32 = rnode.span_start + @intCast(u32, rnode.span_len);
    var expr_node = ast_mod.astStoreNodeAt(ctx.store, expr_idx);
    var pl = @intCast(u8, @enumToInt(Provenance.local));
    var ppa = @intCast(u8, @enumToInt(Provenance.param_addr));
    if (prov == pl) {
        if (expr_node.kind == AstKind.address_of) {
            var name_opt = resolveOrigin(ctx, expr_node.child_0);
            if (name_opt) |nid| {
                var nm = interner_mod.stringInternerGet(ctx.interner, nid);
                var rp1: []const u8 = "returning address of local variable '";
                var rp2: []const u8 = "'";
                var rparts: [3][]const u8 = [3][]const u8{rp1, nm, rp2};
                var msg = diag_mod.diagnosticBuilderMakeMsg(ctx.diag.interner, &rparts[0], @intCast(u32, 3));
                diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2020_RETURNING_ADDRESS_OF_LOCAL)), ctx.source_file_id, start, end, msg);
                return;
            }
            var dmsg: []const u8 = "returning address of local variable";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2020_RETURNING_ADDRESS_OF_LOCAL)), ctx.source_file_id, start, end, dmsg);
            return;
        }
        if (expr_node.kind == AstKind.slice_expr) {
            var name_opt = resolveOrigin(ctx, expr_node.child_0);
            if (name_opt) |nid| {
                var nm = interner_mod.stringInternerGet(ctx.interner, nid);
                var rp1: []const u8 = "returning slice of local array '";
                var rp2: []const u8 = "'";
                var rparts: [3][]const u8 = [3][]const u8{rp1, nm, rp2};
                var msg = diag_mod.diagnosticBuilderMakeMsg(ctx.diag.interner, &rparts[0], @intCast(u32, 3));
                diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6011_RETURNING_SLICE_OF_LOCAL)), ctx.source_file_id, start, end, msg);
                return;
            }
            var dmsg: []const u8 = "returning slice of local array";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6011_RETURNING_SLICE_OF_LOCAL)), ctx.source_file_id, start, end, dmsg);
            return;
        }
        var name_opt = resolveOrigin(ctx, expr_idx);
        if (name_opt) |nid| {
            var nm = interner_mod.stringInternerGet(ctx.interner, nid);
            var rp1: []const u8 = "returning pointer to local via variable '";
            var rp2: []const u8 = "'";
            var rparts: [3][]const u8 = [3][]const u8{rp1, nm, rp2};
            var msg = diag_mod.diagnosticBuilderMakeMsg(ctx.diag.interner, &rparts[0], @intCast(u32, 3));
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6010_RETURNING_POINTER_VIA_VARIABLE)), ctx.source_file_id, start, end, msg);
            return;
        }
        var dmsg: []const u8 = "returning pointer to local via variable";
        diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6010_RETURNING_POINTER_VIA_VARIABLE)), ctx.source_file_id, start, end, dmsg);
        return;
    }
    if (prov == ppa) {
        var name_opt = resolveOrigin(ctx, expr_node.child_0);
        if (name_opt) |nid| {
            var nm = interner_mod.stringInternerGet(ctx.interner, nid);
            var rp1: []const u8 = "returning address of parameter '";
            var rp2: []const u8 = "'";
            var rparts: [3][]const u8 = [3][]const u8{rp1, nm, rp2};
            var msg = diag_mod.diagnosticBuilderMakeMsg(ctx.diag.interner, &rparts[0], @intCast(u32, 3));
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2021_RETURNING_ADDRESS_OF_PARAM)), ctx.source_file_id, start, end, msg);
            return;
        }
        var dmsg: []const u8 = "returning address of function parameter";
        diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2021_RETURNING_ADDRESS_OF_PARAM)), ctx.source_file_id, start, end, dmsg);
        return;
    }
}

// Final callee identifier for both call shapes: a bare `ident_expr`
// (`gpaAlloc(g, n, a)`) and a module-qualified member call (`gpa.gpaAlloc(...)`)
// whose callee is a `field_access` carrying the final name id in its payload.
fn calleeFinalNameId(ctx: *AnalyzerContext, callee_idx: u32) ?u32 {
    if (callee_idx == @intCast(u32, 0)) return null;
    var callee = ast_mod.astStoreNodeAt(ctx.store, callee_idx);
    if (callee.kind == AstKind.ident_expr) return identNameId(ctx.store, callee_idx);
    if (callee.kind == AstKind.field_access) {
        var final_id = ast_mod.astStoreNodePayload(ctx.store, callee_idx);
        if (final_id == @intCast(u32, 0)) return null;
        return final_id;
    }
    return null;
}

pub fn isAllocCall(ctx: *AnalyzerContext, expr_idx: u32) bool {
    if (expr_idx == @intCast(u32, 0)) return false;
    var node = ast_mod.astStoreNodeAt(ctx.store, expr_idx);
    if (node.kind == AstKind.try_expr) return isAllocCall(ctx, node.child_0);
    if (node.kind != AstKind.fn_call) return false;
    var name_id = calleeFinalNameId(ctx, node.child_0) orelse return false;
    var s_sandAlloc: []const u8 = "sandAlloc";
    var sand_nid = interner_mod.stringInternerIntern(ctx.interner, s_sandAlloc);
    if (name_id == sand_nid) return true;
    var s_sand_alloc: []const u8 = "sand_alloc";
    var sand2_nid = interner_mod.stringInternerIntern(ctx.interner, s_sand_alloc);
    if (name_id == sand2_nid) return true;
    var s_arena_alloc: []const u8 = "arena_alloc";
    var arena_nid = interner_mod.stringInternerIntern(ctx.interner, s_arena_alloc);
    if (name_id == arena_nid) return true;
    var s_gpa_alloc: []const u8 = "gpaAlloc";
    var gpa_alloc_nid = interner_mod.stringInternerIntern(ctx.interner, s_gpa_alloc);
    if (name_id == gpa_alloc_nid) return true;
    var s_gpa_alloc_zeroed: []const u8 = "gpaAllocZeroed";
    var gpa_alloc_zeroed_nid = interner_mod.stringInternerIntern(ctx.interner, s_gpa_alloc_zeroed);
    if (name_id == gpa_alloc_zeroed_nid) return true;
    return false;
}

pub fn isFreeCall(ctx: *AnalyzerContext, expr_idx: u32) ?u32 {
    if (expr_idx == @intCast(u32, 0)) return null;
    var node = ast_mod.astStoreNodeAt(ctx.store, expr_idx);
    if (node.kind != AstKind.fn_call) return null;
    var name_id = calleeFinalNameId(ctx, node.child_0) orelse return null;
    var s_arena_free: []const u8 = "arena_free";
    var arena_free_nid = interner_mod.stringInternerIntern(ctx.interner, s_arena_free);
    var s_sand_free: []const u8 = "sandFree";
    var sand_free_nid = interner_mod.stringInternerIntern(ctx.interner, s_sand_free);
    var s_gpa_free: []const u8 = "gpaFree";
    var gpa_free_nid = interner_mod.stringInternerIntern(ctx.interner, s_gpa_free);
    if (name_id != arena_free_nid and name_id != sand_free_nid and name_id != gpa_free_nid) return null;
    // `gpaFree(g, ptr)` keeps the arg-1 pointer convention.
    var args_n = ast_mod.astStoreNodeExtraChildCount(ctx.store, expr_idx);
    if (args_n < @intCast(u32, 2)) return null;
    var args1 = ast_mod.astStoreNodeExtraChildAt(ctx.store, expr_idx, @intCast(u32, 1));
    // DF-2: the freed pointer may be a field/index/member chain, not only a
    // bare identifier. Resolve it to the same identity used by allocation.
    return resolveLValueIdentity(ctx, args1);
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

// Report the first same-block dereference/index/field use of a freed name and
// latch it as `freed_reported` so later uses do not duplicate the diagnostic.
fn reportUseAfterFree(ctx: *AnalyzerContext, state: *StateMap, name_id: u32, node_idx: u32) void {
    if (name_id == @intCast(u32, 0)) return;
    // DF-1 documented limitation: a same-block use-after-free through an alias
    // copy is still not claimed. Only the canonical name reports.
    if (aliasResolveName(state, name_id) != name_id) return;
    var current = smap_mod.stateMapGet(state, name_id);
    if (current) |c| {
        if (c == @enumToInt(AllocState.freed)) {
            var pn = interner_mod.stringInternerGet(ctx.interner, name_id);
            var up1: []const u8 = "use after free of pointer '";
            var up2: []const u8 = "'";
            var uparts: [3][]const u8 = [3][]const u8{up1, pn, up2};
            var umsg = diag_mod.diagnosticBuilderMakeMsg(ctx.diag.interner, &uparts[0], @intCast(u32, 3));
            var node = ast_mod.astStoreNodeAt(ctx.store, node_idx);
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2006_USE_AFTER_FREE)), ctx.source_file_id, node.span_start, node.span_start + @intCast(u32, node.span_len), umsg);
            smap_mod.stateMapSet(state, name_id, @enumToInt(AllocState.freed_reported));
        }
    }
}

// Same-block only: walk a statement expression for dereference/index/field
// uses and report the identifier they bottom out at. A bare pointer copy
// (`q = p` / `var q = p`) and a bare identifier statement are not uses.
fn checkUseAfterFreeExpr(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32) void {
    if (expr_idx == @intCast(u32, 0)) return;
    var node = ast_mod.astStoreNodeAt(ctx.store, expr_idx);
    var kind = node.kind;
    if (kind == AstKind.deref) {
        if (resolveOrigin(ctx, node.child_0)) |nid| reportUseAfterFree(ctx, state, nid, expr_idx);
        checkUseAfterFreeExpr(ctx, state, node.child_0);
        return;
    }
    if (kind == AstKind.index_access) {
        if (resolveOrigin(ctx, node.child_0)) |nid| reportUseAfterFree(ctx, state, nid, expr_idx);
        checkUseAfterFreeExpr(ctx, state, node.child_0);
        checkUseAfterFreeExpr(ctx, state, node.child_1);
        return;
    }
    if (kind == AstKind.field_access) {
        if (resolveOrigin(ctx, node.child_0)) |nid| reportUseAfterFree(ctx, state, nid, expr_idx);
        checkUseAfterFreeExpr(ctx, state, node.child_0);
        return;
    }
    if (kind == AstKind.fn_call or kind == AstKind.builtin_call) {
        var args_n = ast_mod.astStoreNodeExtraChildCount(ctx.store, expr_idx);
        var ai: usize = 0;
        while (ai < @intCast(usize, args_n)) : (ai += 1) {
            checkUseAfterFreeExpr(ctx, state, ast_mod.astStoreNodeExtraChildAt(ctx.store, expr_idx, @intCast(u32, ai)));
        }
        return;
    }
    if (kind == AstKind.var_decl) {
        checkUseAfterFreeExpr(ctx, state, node.child_1);
        return;
    }
    if (kind == AstKind.plain_assign) {
        checkUseAfterFreeExpr(ctx, state, node.child_0);
        checkUseAfterFreeExpr(ctx, state, node.child_1);
        return;
    }
    if (kind == AstKind.return_stmt or kind == AstKind.expr_stmt or
        kind == AstKind.try_expr or kind == AstKind.paren_expr or
        kind == AstKind.address_of or kind == AstKind.orelse_expr or
        kind == AstKind.catch_expr or kind == AstKind.slice_expr) {
        checkUseAfterFreeExpr(ctx, state, node.child_0);
        return;
    }
    if (kind == AstKind.block) {
        var stmts_n = ast_mod.astStoreNodeExtraChildCount(ctx.store, expr_idx);
        var si: usize = 0;
        while (si < @intCast(usize, stmts_n)) : (si += 1) {
            checkUseAfterFreeExpr(ctx, state, ast_mod.astStoreNodeExtraChildAt(ctx.store, expr_idx, @intCast(u32, si)));
        }
        return;
    }
    // Arithmetic/comparison/boolean/unary/compound-assign and other wrapper
    // nodes: reach any deref/index/field use in their child slots. Bare
    // identifier operands remain non-uses (the ident branch is empty).
    if (node.child_0 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(kind, @intCast(u8, 0))) checkUseAfterFreeExpr(ctx, state, node.child_0);
    if (node.child_1 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(kind, @intCast(u8, 1))) checkUseAfterFreeExpr(ctx, state, node.child_1);
    if (node.child_2 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(kind, @intCast(u8, 2))) checkUseAfterFreeExpr(ctx, state, node.child_2);
}

pub fn handleAllocCall(ctx: *AnalyzerContext, state: *StateMap, name_id: u32, init_idx: u32) void {
    if (!isAllocCall(ctx, init_idx)) return;
    smap_mod.stateMapSet(state, name_id, @enumToInt(AllocState.allocated));
    recordAllocatorHandle(ctx, init_idx);
}

fn emitFreeingUntracked(ctx: *AnalyzerContext, name_id: u32, node_idx: u32) void {
    var pn = interner_mod.stringInternerGet(ctx.interner, name_id);
    var up1: []const u8 = "freeing untracked pointer '";
    var up2: []const u8 = "'";
    var uparts: [3][]const u8 = [3][]const u8{up1, pn, up2};
    var umsg = diag_mod.diagnosticBuilderMakeMsg(ctx.diag.interner, &uparts[0], @intCast(u32, 3));
    var node = ast_mod.astStoreNodeAt(ctx.store, node_idx);
    diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6006_FREEING_UNTRACKED)), ctx.source_file_id, node.span_start, node.span_start + @intCast(u32, node.span_len), umsg);
}

pub fn handleFreeCall(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32) void {
    var target_id = isFreeCall(ctx, expr_idx) orelse return;
    if (target_id == @intCast(u32, 0)) return;
    var root = aliasResolveName(state, target_id);
    var summary = aliasClassSummary(state, root);
    var node = ast_mod.astStoreNodeAt(ctx.store, expr_idx);
    if (summary.saw_freed) {
        var pn = interner_mod.stringInternerGet(ctx.interner, target_id);
        var dp1: []const u8 = "double free of pointer '";
        var dp2: []const u8 = "'";
        var dparts: [3][]const u8 = [3][]const u8{dp1, pn, dp2};
        var dmsg = diag_mod.diagnosticBuilderMakeMsg(ctx.diag.interner, &dparts[0], @intCast(u32, 3));
        diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2005_DOUBLE_FREE)), ctx.source_file_id, node.span_start, node.span_start + @intCast(u32, node.span_len), dmsg);
        return;
    }
    if (summary.saw_allocated) {
        aliasSetClassState(state, root, @enumToInt(AllocState.freed));
        return;
    }
    // DF-4: `transferred`, `returned_val`, and `unknown` are not owned here;
    // keep the state (no silent -> freed) and emit the documented untracked-free
    // diagnostic instead of a false double free.
    if (summary.saw_unowned) {
        emitFreeingUntracked(ctx, target_id, expr_idx);
        return;
    }
    if (summary.saw_any) {
        aliasSetClassState(state, root, @enumToInt(AllocState.freed));
    } else {
        emitFreeingUntracked(ctx, target_id, expr_idx);
    }
}

pub fn checkLeaksOnScopeExit(ctx: *AnalyzerContext, state: *StateMap) void {
    var entries = smap_mod.stateMapGetEntries(state);
    var ei: usize = 0;
    while (ei < entries.len) : (ei += 1) {
        if (entries[ei].state == @enumToInt(AllocState.allocated)) {
            // One allocation, one leak diagnostic: aliases mirror the canonical
            // name's state, so report only the class root.
            if (aliasResolveName(state, entries[ei].name_id) != entries[ei].name_id) continue;
            var pn = interner_mod.stringInternerGet(ctx.interner, entries[ei].name_id);
            var lp1: []const u8 = "memory leak: pointer '";
            var lp2: []const u8 = "' not freed";
            var lparts: [3][]const u8 = [3][]const u8{lp1, pn, lp2};
            var lmsg = diag_mod.diagnosticBuilderMakeMsg(ctx.diag.interner, &lparts[0], @intCast(u32, 3));
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6005_MEMORY_LEAK)), ctx.source_file_id, ctx.current_fn_span_start, ctx.current_fn_span_end, lmsg);
        }
    }
}

pub fn handleAllocAssign(ctx: *AnalyzerContext, state: *StateMap, node_idx: u32) void {
    var node = ast_mod.astStoreNodeAt(ctx.store, node_idx);
    var lhs_idx = node.child_0;
    var rhs_idx = node.child_1;
    var lhs_name_id = resolveLValueIdentity(ctx, lhs_idx) orelse return;
    var lhs_root = aliasResolveName(state, lhs_name_id);
    var current = smap_mod.stateMapGet(state, lhs_root);
    if (current) |c| {
        if (c == @enumToInt(AllocState.allocated)) {
            // Reassigning an alias never loses the allocation (the class root
            // still owns it); reassigning the root is only a leak when no
            // alias still references the old allocation.
            var report_leak = lhs_name_id == lhs_root and !aliasHasInbound(state, lhs_root);
            if (report_leak) {
                var pn = interner_mod.stringInternerGet(ctx.interner, lhs_name_id);
                var op1: []const u8 = "memory leak: pointer '";
                var op2: []const u8 = "' overwritten before free";
                var oparts: [3][]const u8 = [3][]const u8{op1, pn, op2};
                var lmsg = diag_mod.diagnosticBuilderMakeMsg(ctx.diag.interner, &oparts[0], @intCast(u32, 3));
                diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6005_MEMORY_LEAK)), ctx.source_file_id, node.span_start, node.span_start + @intCast(u32, node.span_len), lmsg);
            }
        }
    }
    if (lhs_name_id == lhs_root) {
        aliasDetachInbound(state, lhs_root);
    } else {
        aliasForget(state, lhs_name_id);
    }
    if (isAllocCall(ctx, rhs_idx)) {
        aliasForget(state, lhs_name_id);
        smap_mod.stateMapSet(state, lhs_name_id, @enumToInt(AllocState.allocated));
        recordAllocatorHandle(ctx, rhs_idx);
        return;
    }
    if (rhs_idx != @intCast(u32, 0)) {
        var rhs_node = ast_mod.astStoreNodeAt(ctx.store, rhs_idx);
        if (rhs_node.kind == AstKind.null_literal) {
            aliasForget(state, lhs_name_id);
            smap_mod.stateMapSet(state, lhs_name_id, @enumToInt(AllocState.untracked));
            return;
        }
        var rhs_name_id = resolveLValueIdentity(ctx, rhs_idx) orelse 0;
        if (rhs_name_id != @intCast(u32, 0)) {
            var rhs_root = aliasResolveName(state, rhs_name_id);
            if (smap_mod.stateMapGet(state, rhs_root) != null) {
                aliasRecord(state, lhs_name_id, rhs_root);
                aliasCopyState(state, lhs_name_id, rhs_root);
                return;
            }
        }
    }
    aliasForget(state, lhs_name_id);
    smap_mod.stateMapSet(state, lhs_name_id, @enumToInt(AllocState.unknown));
}

// DF-1: a `var` initializer propagates the allocation state of an identifier
// (or field/index) RHS by making the new binding an alias of that allocation.
pub fn handleAllocVarDecl(ctx: *AnalyzerContext, state: *StateMap, node_idx: u32) void {
    var node = ast_mod.astStoreNodeAt(ctx.store, node_idx);
    var name_id = ast_mod.astStoreNodePayload(ctx.store, node_idx);
    if (name_id == @intCast(u32, 0)) return;
    var rhs_idx = node.child_1;
    if (rhs_idx == @intCast(u32, 0)) return;
    aliasForget(state, name_id);
    if (isAllocCall(ctx, rhs_idx)) {
        smap_mod.stateMapSet(state, name_id, @enumToInt(AllocState.allocated));
        recordAllocatorHandle(ctx, rhs_idx);
        return;
    }
    var rhs_node = ast_mod.astStoreNodeAt(ctx.store, rhs_idx);
    if (rhs_node.kind == AstKind.null_literal) {
        smap_mod.stateMapSet(state, name_id, @enumToInt(AllocState.untracked));
        return;
    }
    var rhs_name_id = resolveLValueIdentity(ctx, rhs_idx) orelse return;
    var rhs_root = aliasResolveName(state, rhs_name_id);
    if (smap_mod.stateMapGet(state, rhs_root) != null) {
        aliasRecord(state, name_id, rhs_root);
        aliasCopyState(state, name_id, rhs_root);
    }
}

pub fn handleOwnershipReturn(ctx: *AnalyzerContext, state: *StateMap, ret_expr_idx: u32) void {
    if (ret_expr_idx == @intCast(u32, 0)) return;
    var ret_id = resolveLValueIdentity(ctx, ret_expr_idx) orelse return;
    var root = aliasResolveName(state, ret_id);
    var current = smap_mod.stateMapGet(state, root);
    if (current) |c| {
        if (c == @enumToInt(AllocState.allocated)) {
            aliasSetClassState(state, root, @enumToInt(AllocState.returned_val));
        }
    }
}

// DF-3: only a real ownership-taking call transfers. The callee name must name
// an ownership-taking operation; unknown calls (reads, logging, plain helpers)
// never transfer. Allocator/free calls are excluded and a name known to be an
// allocator handle is skipped.
fn isOwnershipTakingNameId(ctx: *AnalyzerContext, name_id: u32) bool {
    var s_take: []const u8 = "take";
    if (name_id == interner_mod.stringInternerIntern(ctx.interner, s_take)) return true;
    var s_take_own: []const u8 = "takeOwnership";
    if (name_id == interner_mod.stringInternerIntern(ctx.interner, s_take_own)) return true;
    var s_take_own2: []const u8 = "take_ownership";
    if (name_id == interner_mod.stringInternerIntern(ctx.interner, s_take_own2)) return true;
    var s_transfer: []const u8 = "transfer_ownership";
    if (name_id == interner_mod.stringInternerIntern(ctx.interner, s_transfer)) return true;
    var s_consume: []const u8 = "consume";
    if (name_id == interner_mod.stringInternerIntern(ctx.interner, s_consume)) return true;
    var s_destroy: []const u8 = "destroy";
    if (name_id == interner_mod.stringInternerIntern(ctx.interner, s_destroy)) return true;
    var s_deinit: []const u8 = "deinit";
    if (name_id == interner_mod.stringInternerIntern(ctx.interner, s_deinit)) return true;
    var s_release: []const u8 = "release";
    if (name_id == interner_mod.stringInternerIntern(ctx.interner, s_release)) return true;
    var s_drop: []const u8 = "drop";
    if (name_id == interner_mod.stringInternerIntern(ctx.interner, s_drop)) return true;
    return false;
}

fn isOwnershipTakingCall(ctx: *AnalyzerContext, fn_call_idx: u32) bool {
    if (fn_call_idx == @intCast(u32, 0)) return false;
    var node = ast_mod.astStoreNodeAt(ctx.store, fn_call_idx);
    if (node.kind != AstKind.fn_call) return false;
    var name_id = calleeFinalNameId(ctx, node.child_0) orelse return false;
    return isOwnershipTakingNameId(ctx, name_id);
}

pub fn handleOwnershipPass(ctx: *AnalyzerContext, state: *StateMap, fn_call_idx: u32) void {
    if (fn_call_idx == @intCast(u32, 0)) return;
    var node = ast_mod.astStoreNodeAt(ctx.store, fn_call_idx);
    if (node.kind != AstKind.fn_call) return;
    if (isAllocCall(ctx, fn_call_idx)) return;
    if (isFreeCall(ctx, fn_call_idx) != null) return;
    if (!isOwnershipTakingCall(ctx, fn_call_idx)) return;
    var args_n = ast_mod.astStoreNodeExtraChildCount(ctx.store, fn_call_idx);
    var ai: usize = 0;
    while (ai < @intCast(usize, args_n)) : (ai += 1) {
        var args_i = ast_mod.astStoreNodeExtraChildAt(ctx.store, fn_call_idx, @intCast(u32, ai));
        var arg_node = ast_mod.astStoreNodeAt(ctx.store, args_i);
        if (arg_node.kind != AstKind.ident_expr) continue;
        var arg_name_id = identNameId(ctx.store, args_i);
        var root = aliasResolveName(state, arg_name_id);
        if (handleIs(arg_name_id) or handleIs(root)) continue;
        var current = smap_mod.stateMapGet(state, root);
        if (current) |c| {
            if (c == @enumToInt(AllocState.allocated)) {
                aliasSetClassState(state, root, @enumToInt(AllocState.transferred));
                var pn = interner_mod.stringInternerGet(ctx.interner, arg_name_id);
                var tp1: []const u8 = "ownership of '";
                var tp2: []const u8 = "' transferred to function";
                var tparts: [3][]const u8 = [3][]const u8{tp1, pn, tp2};
                var tmsg = diag_mod.diagnosticBuilderMakeMsg(ctx.diag.interner, &tparts[0], @intCast(u32, 3));
                var warn_lvl: u8 = @intCast(u8, 2);
                if (ctx.warn_all != @intCast(u8, 0)) warn_lvl = @intCast(u8, 1);
                diag_mod.diagnosticCollectorAdd(ctx.diag, warn_lvl, @intCast(u16, @enumToInt(diag_mod.ErrorCode.INFO_7001_OWNERSHIP_TRANSFERRED)), @intCast(u32, 0), node.span_start, node.span_start + @intCast(u32, node.span_len), tmsg);
            }
        }
    }
}

// DF-3: remember the allocator handle (first argument of a recognized
// alloc/free call) so a later call cannot mistake it for owned memory.
pub fn recordAllocatorHandle(ctx: *AnalyzerContext, call_idx: u32) void {
    if (call_idx == @intCast(u32, 0)) return;
    var idx = call_idx;
    var node = ast_mod.astStoreNodeAt(ctx.store, idx);
    // `var p = try sandAlloc(...)`: the allocator call is under `try`.
    if (node.kind == AstKind.try_expr) {
        idx = node.child_0;
        if (idx == @intCast(u32, 0)) return;
        node = ast_mod.astStoreNodeAt(ctx.store, idx);
    }
    if (node.kind != AstKind.fn_call) return;
    var args_n = ast_mod.astStoreNodeExtraChildCount(ctx.store, idx);
    if (args_n < @intCast(u32, 1)) return;
    var args0 = ast_mod.astStoreNodeExtraChildAt(ctx.store, idx, @intCast(u32, 0));
    var id = resolveLValueIdentity(ctx, args0) orelse return;
    handleRecord(id);
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
    skip_null_check: u8,
    skip_lifetime_check: u8,
    skip_doublefree_check: u8,
    warn_all: u8,
    on_stmt_cb: fn(*AnalyzerContext, *StateMap, u32) void,
    in_defer_exec: u8,
    lifetime_analysis_mode: u8,
    doublefree_analysis_mode: u8,
    source_file_id: u32,
    // T9a (D4a): shared comptime fold table written by
    // `phase_ComptimeEvaluation` (and sema's local-const stamping). Analyzer
    // consumers consult THIS table — never a parallel copy — for dead-arm
    // parity with sema/lowering.
    comptime_folds: ?*ce_mod.ComptimeFoldTable,
    // T9a: the module symbol registry + target flag let the DED-2 selector
    // fallback construct the same evaluator sema/lowering use when the shared
    // fold table has no entry for a switch selector.
    symbol_reg: ?*SymbolRegistry,
    target_is_windows: bool,
    // T9a (DX-1): the enclosing function declaration span used to attribute
    // scope-exit leak diagnostics (which have no statement node of their own).
    current_fn_span_start: u32,
    current_fn_span_end: u32,
};

pub fn deferQueueEnsureCapacity(ctx: *AnalyzerContext, new_cap: usize) void {
    if (new_cap <= ctx.defer_queue_cap) return;
    var nc = new_cap;
    if (nc < ctx.defer_queue_cap * 2) nc = ctx.defer_queue_cap * 2;
    if (nc < 8) nc = 8;
    var raw = alloc_mod.sandAlloc(ctx.defer_queue_alloc, @intCast(usize, @sizeOf(DeferEntry)) * nc, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]DeferEntry, raw);
    var i: usize = 0;
    while (i < ctx.defer_queue_len) : (i += 1) { new_items[i] = ctx.defer_queue_items[i]; }
    ctx.defer_queue_items = new_items;
    ctx.defer_queue_cap = nc;
}

pub fn resetDeferQueue(ctx: *AnalyzerContext) void {
    ctx.defer_queue_items = undefined;
    ctx.defer_queue_len = @intCast(usize, 0);
    ctx.defer_queue_cap = @intCast(usize, 0);
}

pub fn analyzeSignature(ctx: *AnalyzerContext, fn_node_idx: u32) void {
    var node = ast_mod.astStoreNodeAt(ctx.store, fn_node_idx);
    if (node.kind != AstKind.fn_decl) return;
    var proto_idx = ast_mod.astStoreNodePayload(ctx.store, fn_node_idx);
    var proto = ctx.store.fn_protos.items[@intCast(usize, proto_idx)];
    var param_payload: u64 = (@intCast(u64, proto.params_start) << @intCast(u64, 32)) | @intCast(u64, proto.params_count);
    var params_n = ast_mod.astStoreGetExtraChildCount(ctx.store, param_payload);
    var pi: usize = 0;
    while (pi < @intCast(usize, params_n)) : (pi += 1) {
        var pnode = ast_mod.astStoreNodeAt(ctx.store, ast_mod.astStoreGetExtraChildAt(ctx.store, param_payload, @intCast(u32, pi)));
        var type_expr = pnode.child_0;
        if (type_expr != @intCast(u32, 0)) validateSignatureType(ctx, type_expr, @intCast(u32, 0));
        rejectAnytypeType(ctx, type_expr);
    }
    var ret_node = proto.return_type_node;
    if (ret_node != @intCast(u32, 0)) validateSignatureType(ctx, ret_node, @intCast(u32, 1));
    rejectAnytypeType(ctx, ret_node);
}

// A1-F (Q3(i)): recursively reject the `anytype` marker in any signature/type
// position -- a direct parameter/return, or nested inside a `?`/`*`/`[*]`/`[]`/
// `[N]` wrapper, an `E!T` error union or a `fn(...)` pointer type. Level-0
// `error[16]` (`ERR_2012_ANYTYPE_NOT_SUPPORTED`), one per anytype node
// (`diagnosticCollectorMarkNodeOnce`), carrying the offending node's span and
// the module's real source file id so the renderer prints `file:line:col` + a
// caret. The top-level ident also reaches `validateSignatureType`; the shared
// dedup keeps the census at exactly one diagnostic per node.
fn rejectAnytypeType(ctx: *AnalyzerContext, type_node_idx: u32) void {
    if (type_node_idx == @intCast(u32, 0)) return;
    var tnode = ast_mod.astStoreNodeAt(ctx.store, type_node_idx);
    var kind = tnode.kind;
    if (kind == AstKind.ident_expr) {
        var name_id = identNameId(ctx.store, type_node_idx);
        var s_anytype: []const u8 = "anytype";
        var anytype_nid = interner_mod.stringInternerIntern(ctx.interner, s_anytype);
        if (name_id == anytype_nid) {
            if (!diag_mod.diagnosticCollectorMarkNodeOnce(ctx.diag, type_node_idx)) return;
            var amsg: []const u8 = "anytype not supported in Z98";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2012_ANYTYPE_NOT_SUPPORTED)), ctx.source_file_id, tnode.span_start, tnode.span_start + @intCast(u32, tnode.span_len), amsg);
        }
        return;
    }
    if (kind == AstKind.ptr_type or kind == AstKind.many_ptr_type or
        kind == AstKind.slice_type or kind == AstKind.optional_type or
        kind == AstKind.array_type) {
        rejectAnytypeType(ctx, tnode.child_0);
        return;
    }
    if (kind == AstKind.error_union_type) {
        rejectAnytypeType(ctx, tnode.child_0);
        rejectAnytypeType(ctx, tnode.child_1);
        return;
    }
    if (kind == AstKind.fn_type) {
        rejectAnytypeType(ctx, tnode.child_0);
        if (ast_mod.astStoreNodePayload(ctx.store, type_node_idx) != @intCast(u32, 0)) {
            var ft_n = ast_mod.astStoreNodeExtraChildCount(ctx.store, type_node_idx);
            var ft_i: usize = 0;
            while (ft_i < @intCast(usize, ft_n)) : (ft_i += 1) {
                rejectAnytypeType(ctx, ast_mod.astStoreNodeExtraChildAt(ctx.store, type_node_idx, @intCast(u32, ft_i)));
            }
        }
        return;
    }
}

// T5: `is_return` is a position code — 0 = direct parameter (void →
// ERR_2010), 1 = direct or fn-ptr return (size → WARN_7010), 2 = nested
// inside a wrapper (`?T`, `E!T`, `*T`, `[]T`, `[N]T`, fn-ptr params).
fn validateSignatureNamed(ctx: *AnalyzerContext, name_id: u32, tnode_idx: u32, is_return: u32) void {
    var tnode = ast_mod.astStoreNodeAt(ctx.store, tnode_idx);
    var key = @intCast(u64, name_id);
    var tid = type_mod.nameCacheGet(ctx.registry, key);
    if (tid) |ttid| {
        var ty = ctx.registry.types_items[@intCast(usize, ttid)];
        if (ty.kind == type_mod.TypeKind.unresolved_name or
            ((ty.kind == type_mod.TypeKind.struct_type or
              ty.kind == type_mod.TypeKind.union_type or
              ty.kind == type_mod.TypeKind.tagged_union_type or
              ty.kind == type_mod.TypeKind.packed_union_type or
              ty.kind == type_mod.TypeKind.enum_type) and ty.state != @intCast(u8, 2))) {
            var tname = interner_mod.stringInternerGet(ctx.interner, name_id);
            var ip1: []const u8 = "incomplete type '";
            var ip2: []const u8 = "' in function signature";
            var iparts: [3][]const u8 = [3][]const u8{ip1, tname, ip2};
            var imsg = diag_mod.diagnosticBuilderMakeMsg(ctx.diag.interner, &iparts[0], @intCast(u32, 3));
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2011_INCOMPLETE_TYPE)), @intCast(u32, 0), tnode.span_start, tnode.span_start + @intCast(u32, tnode.span_len), imsg);
        }
        if (ty.kind == type_mod.TypeKind.void_type and is_return == @intCast(u32, 0)) {
            var vmsg: []const u8 = "void not allowed as parameter type";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2010_VOID_PARAMETER)), @intCast(u32, 0), tnode.span_start, tnode.span_start + @intCast(u32, tnode.span_len), vmsg);
        }
        if (is_return == @intCast(u32, 1)) {
            if (ty.size > @intCast(u32, 64)) {
                var wmsg: []const u8 = "return type exceeds 64 bytes; may cause issues on MSVC 6.0";
                diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_7010_LARGE_RETURN)), @intCast(u32, 0), tnode.span_start, tnode.span_start + @intCast(u32, tnode.span_len), wmsg);
            }
        }
    } else {
        // T5: arbitrary-width ints (`i1`..`i63` / `u1`..`u64` — the
        // parseArbIntWidth family) may not be cached yet under this name; they
        // lower to a stable C89 carrier and are accepted. Any other uncached
        // name is left to type resolution (no analyzer rule).
        var t5_text = interner_mod.stringInternerGet(ctx.interner, name_id);
        var t5_au: bool = false;
        var t5_aw = type_mod.parseArbIntWidth(t5_text, &t5_au);
        if (t5_aw != @intCast(u32, 0)) return;
    }
    var s_anytype: []const u8 = "anytype";
    var anytype_nid = interner_mod.stringInternerIntern(ctx.interner, s_anytype);
    if (name_id == anytype_nid) {
        if (!diag_mod.diagnosticCollectorMarkNodeOnce(ctx.diag, tnode_idx)) return;
        var amsg: []const u8 = "anytype not supported in Z98";
        diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2012_ANYTYPE_NOT_SUPPORTED)), ctx.source_file_id, tnode.span_start, tnode.span_start + @intCast(u32, tnode.span_len), amsg);
    }
}

pub fn validateSignatureType(ctx: *AnalyzerContext, type_node_idx: u32, is_return: u32) void {
    if (type_node_idx == @intCast(u32, 0)) return;
    var tnode = ast_mod.astStoreNodeAt(ctx.store, type_node_idx);
    var kind = tnode.kind;
    if (kind == AstKind.ident_expr) {
        validateSignatureNamed(ctx, identNameId(ctx.store, type_node_idx), type_node_idx, is_return);
        return;
    }
    // T5: the rules reach through the composite wrappers, so a fn-ptr return
    // of `?Aggregate`/`E!Aggregate` (the D1-fixed shapes) is validated like a
    // bare name and accepted when complete; incomplete bases are still
    // rejected.
    if (kind == AstKind.optional_type) {
        validateSignatureType(ctx, tnode.child_0, @intCast(u32, 2));
        return;
    }
    if (kind == AstKind.error_union_type) {
        if (tnode.child_0 != @intCast(u32, 0)) validateSignatureType(ctx, tnode.child_0, @intCast(u32, 2));
        validateSignatureType(ctx, tnode.child_1, @intCast(u32, 2));
        return;
    }
    if (kind == AstKind.ptr_type or kind == AstKind.many_ptr_type or
        kind == AstKind.slice_type or kind == AstKind.array_type) {
        validateSignatureType(ctx, tnode.child_0, @intCast(u32, 2));
        return;
    }
    if (kind == AstKind.fn_type) {
        validateSignatureType(ctx, tnode.child_0, @intCast(u32, 1));
        if (ast_mod.astStoreNodePayload(ctx.store, type_node_idx) != @intCast(u32, 0)) {
            var ft_n = ast_mod.astStoreNodeExtraChildCount(ctx.store, type_node_idx);
            var ft_i: usize = 0;
            while (ft_i < @intCast(usize, ft_n)) : (ft_i += 1) {
                var ft_p = ast_mod.astStoreNodeExtraChildAt(ctx.store, type_node_idx, @intCast(u32, ft_i));
                validateSignatureType(ctx, ft_p, @intCast(u32, 2));
                rejectAnytypeType(ctx, ft_p);
            }
        }
        return;
    }
    if (kind == AstKind.field_access) {
        // Member type expressions (`mod.Key`, `T.tag`-family member types):
        // validate the member's named type through the name cache.
        var t5_mname = ast_mod.astStoreNodePayload(ctx.store, type_node_idx);
        if (t5_mname != @intCast(u32, 0)) {
            validateSignatureNamed(ctx, t5_mname, type_node_idx, is_return);
        }
        return;
    }
}

pub fn analyzeExpr(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32) void {
    // T9a (D4a / audit L2): null tracking and null diagnostics belong to the
    // null pass only. The lifetime/double-free passes keep their own on_stmt
    // state; they must not re-emit null diagnostics from condition walks.
    if (ctx.null_analysis_mode == @intCast(u8, 0)) return;
    if (expr_idx == @intCast(u32, 0)) return;
    var node = ast_mod.astStoreNodeAt(ctx.store, expr_idx);
    var kind = node.kind;
    if (kind == AstKind.deref) {
        var st = classifyExpr(ctx, state, node.child_0);
        var start = node.span_start;
        var end = node.span_start + @intCast(u32, node.span_len);
        if (st == @enumToInt(PtrState.is_null)) {
            var msg: []const u8 = "definite null pointer dereference";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_2004_DEFINITE_NULL_DEREF)), ctx.source_file_id, start, end, msg);
        } else if (st == @enumToInt(PtrState.uninit)) {
            var msg: []const u8 = "dereference of uninitialized pointer";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6001_UNINIT_DEREF)), ctx.source_file_id, start, end, msg);
        } else if (st == @enumToInt(PtrState.maybe)) {
            var msg: []const u8 = "potential null pointer dereference";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_6002_POTENTIAL_NULL_DEREF)), ctx.source_file_id, start, end, msg);
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
        var args_n = ast_mod.astStoreNodeExtraChildCount(ctx.store, expr_idx);
        var ai: usize = 0;
        while (ai < @intCast(usize, args_n)) : (ai += 1) {
            analyzeExpr(ctx, state, ast_mod.astStoreNodeExtraChildAt(ctx.store, expr_idx, @intCast(u32, ai)));
        }
        return;
    }
    if (kind == AstKind.builtin_call) {
        var bargs_n = ast_mod.astStoreNodeExtraChildCount(ctx.store, expr_idx);
        var bi: usize = 0;
        while (bi < @intCast(usize, bargs_n)) : (bi += 1) {
            analyzeExpr(ctx, state, ast_mod.astStoreNodeExtraChildAt(ctx.store, expr_idx, @intCast(u32, bi)));
        }
        return;
    }
    if (kind == AstKind.if_expr) {
        // T5 (T3 rule): capture-free comptime-known condition — only the live
        // arm exists for analysis. A capture binds into a forked state and the
        // then arm sees it.
        var t5_ief = analyzerFoldComptimeBool(ctx, node.child_0, 0);
        if (t5_ief) |iev| {
            if (ast_mod.astStoreNodePayload(ctx.store, expr_idx) == @intCast(u32, 0)) {
                if (iev) {
                    analyzeExpr(ctx, state, node.child_1);
                } else if (node.child_2 != @intCast(u32, 0)) {
                    analyzeExpr(ctx, state, node.child_2);
                }
                return;
            }
        }
        analyzeExpr(ctx, state, node.child_0);
        var t5_iecap = captureNameIdOf(ctx.store, expr_idx);
        if (t5_iecap != @intCast(u32, 0)) {
            var t5_ies = smap_mod.stateMapFork(state, ctx.alloc);
            bindCaptureState(ctx, t5_ies, t5_iecap, node.child_0);
            analyzeExpr(ctx, t5_ies, node.child_1);
        } else {
            analyzeExpr(ctx, state, node.child_1);
        }
        if (node.child_2 != @intCast(u32, 0)) analyzeExpr(ctx, state, node.child_2);
        return;
    }
    if (kind == AstKind.catch_expr) {
        // T5: `e catch |err| ...` payload capture — the error binding is
        // guaranteed present (null-safe) inside the rhs.
        analyzeExpr(ctx, state, node.child_0);
        var t5_ecap: u32 = @intCast(u32, 0);
        if (node.child_2 != @intCast(u32, 0)) {
            var capn = ast_mod.astStoreNodeAt(ctx.store, node.child_2);
            if (capn.kind == AstKind.payload_capture) {
                t5_ecap = ast_mod.astStoreNodePayload(ctx.store, node.child_2);
            }
        }
        if (t5_ecap != @intCast(u32, 0)) {
            var t5_ecs = smap_mod.stateMapFork(state, ctx.alloc);
            bindCaptureState(ctx, t5_ecs, t5_ecap, node.child_0);
            analyzeExpr(ctx, t5_ecs, node.child_1);
        } else {
            analyzeExpr(ctx, state, node.child_1);
        }
        return;
    }
    if (kind == AstKind.plain_assign) {
        analyzeExpr(ctx, state, node.child_1);
        var lhs_node = ast_mod.astStoreNodeAt(ctx.store, node.child_0);
        if (lhs_node.kind == AstKind.ident_expr) {
            var new_st = classifyExpr(ctx, state, node.child_1);
            smap_mod.stateMapSet(state, identNameId(ctx.store, node.child_0), new_st);
        }
        return;
    }
    if (node.child_0 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(kind, @intCast(u8, 0))) analyzeExpr(ctx, state, node.child_0);
    if (node.child_1 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(kind, @intCast(u8, 1))) analyzeExpr(ctx, state, node.child_1);
    if (node.child_2 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(kind, @intCast(u8, 2))) analyzeExpr(ctx, state, node.child_2);
}

pub fn classifyExpr(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32) u8 {
    if (expr_idx == @intCast(u32, 0)) return @enumToInt(PtrState.uninit);
    var node = ast_mod.astStoreNodeAt(ctx.store, expr_idx);
    var kind = node.kind;
    if (kind == AstKind.null_literal) return @enumToInt(PtrState.is_null);
    if (kind == AstKind.address_of) return @enumToInt(PtrState.safe);
    if (kind == AstKind.try_expr) return @enumToInt(PtrState.safe);
    if (kind == AstKind.fn_call) return @enumToInt(PtrState.maybe);
    if (kind == AstKind.orelse_expr) return @enumToInt(PtrState.safe);
    if (kind == AstKind.catch_expr) return @enumToInt(PtrState.safe);
    if (kind == AstKind.int_literal) {
        var val = ast_mod.astStoreIntValue(ctx.store, expr_idx);
        if (val == @intCast(u64, 0)) return @enumToInt(PtrState.is_null);
        return @enumToInt(PtrState.safe);
    }
    if (kind == AstKind.ident_expr) {
        var result = smap_mod.stateMapGet(state, identNameId(ctx.store, expr_idx));
        if (result) |v| return v;
    }
    return @enumToInt(PtrState.maybe);
}

fn isNullExpr(store: *AstStore, idx: u32) u8 {
    if (idx == @intCast(u32, 0)) return @intCast(u8, 0);
    var node = ast_mod.astStoreNodeAt(store, idx);
    if (node.kind == AstKind.null_literal) return @intCast(u8, 1);
    if (node.kind == AstKind.int_literal) {
        var val = ast_mod.astStoreIntValue(store, idx);
        if (val == @intCast(u64, 0)) return @intCast(u8, 1);
    }
    return @intCast(u8, 0);
}

fn isIdentExpr(store: *AstStore, idx: u32) ?u32 {
    if (idx == @intCast(u32, 0)) return null;
    var node = ast_mod.astStoreNodeAt(store, idx);
    if (node.kind == AstKind.ident_expr) return identNameId(store, idx);
    return null;
}

pub fn detectNullGuard(store: *AstStore, cond_idx: u32) ?NullGuard {
    if (cond_idx == @intCast(u32, 0)) return null;
    var cond = ast_mod.astStoreNodeAt(store, cond_idx);
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
        return NullGuard{ .name_id = identNameId(store, cond_idx), .is_not_null = @intCast(u8, 1) };
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
    var node = ast_mod.astStoreNodeAt(ctx.store, node_idx);
    var name_id: u32 = ast_mod.astStoreNodePayload(ctx.store, node_idx);
    var init_idx = node.child_1;
    if (init_idx != @intCast(u32, 0)) {
        // NP-3: `var` initializers are in scope for null derefs.
        analyzeExpr(ctx, state, init_idx);
        var st = classifyExpr(ctx, state, init_idx);
        smap_mod.stateMapSet(state, name_id, st);
    } else {
        smap_mod.stateMapSet(state, name_id, @enumToInt(PtrState.uninit));
    }
}

pub fn handleNullAssign(ctx: *AnalyzerContext, state: *StateMap, node_idx: u32) void {
    var node = ast_mod.astStoreNodeAt(ctx.store, node_idx);
    var rhs = node.child_1;
    // NP-3: assignment RHS expressions are in scope for null derefs.
    analyzeExpr(ctx, state, rhs);
    var rhs_state = classifyExpr(ctx, state, rhs);
    var lhs_idx = node.child_0;
    var lhs_node = ast_mod.astStoreNodeAt(ctx.store, lhs_idx);
    if (lhs_node.kind == AstKind.ident_expr) {
        smap_mod.stateMapSet(state, identNameId(ctx.store, lhs_idx), rhs_state);
    }
}

pub fn executeDeferQueue(ctx: *AnalyzerContext, state: *StateMap, target_depth: u32, is_error: u8, visit_fn: fn(*AnalyzerContext, *StateMap, u32) void) void {
    ctx.in_defer_exec = @intCast(u8, 1);
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
    ctx.in_defer_exec = @intCast(u8, 0);
}

pub fn walkBlock(ctx: *AnalyzerContext, state: *StateMap, block_idx: u32, visit_fn: fn(*AnalyzerContext, *StateMap, u32) void) void {
    if (block_idx == @intCast(u32, 0)) return;
    var node = ast_mod.astStoreNodeAt(ctx.store, block_idx);
    if (node.kind != AstKind.block) {
        visit_fn(ctx, state, block_idx);
        return;
    }
    var saved_depth = ctx.current_depth;
    ctx.current_depth += 1;
    var children_n = ast_mod.astStoreNodeExtraChildCount(ctx.store, block_idx);
    var i: usize = 0;
    while (i < @intCast(usize, children_n)) : (i += 1) {
        visit_fn(ctx, state, ast_mod.astStoreNodeExtraChildAt(ctx.store, block_idx, @intCast(u32, i)));
    }
    executeDeferQueue(ctx, state, saved_depth, @intCast(u8, 0), visit_fn);
    if (ctx.doublefree_analysis_mode != @intCast(u8, 0)) {
        checkLeaksOnScopeExit(ctx, state);
    }
    ctx.current_depth = saved_depth;
}

// T5: resolve a statement's capture binding to the capture NAME id.
// if_stmt/while_stmt/if_expr carry the if_capture/while_capture NODE index in
// the payload (that node's payload is the name id — cf. lower.zig
// `bindOptionalCapture`); if_capture/while_capture/for_stmt carry the name id
// directly; swt_prong keeps it in child_1.
fn captureNameIdOf(store: *AstStore, node_idx: u32) u32 {
    if (node_idx == @intCast(u32, 0)) return @intCast(u32, 0);
    var node = ast_mod.astStoreNodeAt(store, node_idx);
    var kind = node.kind;
    if (kind == AstKind.if_stmt or kind == AstKind.while_stmt or kind == AstKind.if_expr) {
        var cap_idx = ast_mod.astStoreNodePayload(store, node_idx);
        if (cap_idx == @intCast(u32, 0)) return @intCast(u32, 0);
        var capn = ast_mod.astStoreNodeAt(store, cap_idx);
        if (capn.kind == AstKind.if_capture or capn.kind == AstKind.while_capture) {
            return ast_mod.astStoreNodePayload(store, cap_idx);
        }
        return @intCast(u32, 0);
    }
    if (kind == AstKind.if_capture or kind == AstKind.while_capture or kind == AstKind.for_stmt) {
        return ast_mod.astStoreNodePayload(store, node_idx);
    }
    if (kind == AstKind.swt_prong) {
        return node.child_1;
    }
    return @intCast(u32, 0);
}

// T5 (tech-debt §2.1 — capture propagation): bind a payload capture into the
// active state map. Null mode guarantees the unwrapped payload `safe`; lifetime
// mode inherits the provenance of the captured expression (so
// `if (opt_ptr) |ptr| { return ptr; }` flags when opt_ptr points at a local);
// double-free mode makes the payload an alias of the captured allocation so
// freeing either name frees the one allocation (DF-1).
fn bindCaptureState(ctx: *AnalyzerContext, state: *StateMap, name_id: u32, src_expr: u32) void {
    if (name_id == @intCast(u32, 0)) return;
    if (ctx.null_analysis_mode != @intCast(u8, 0)) {
        smap_mod.stateMapSet(state, name_id, @enumToInt(PtrState.safe));
    }
    if (ctx.lifetime_analysis_mode != @intCast(u8, 0)) {
        var prov = classifyProvenance(ctx, state, src_expr);
        smap_mod.stateMapSet(state, name_id, prov);
    }
    if (ctx.doublefree_analysis_mode != @intCast(u8, 0)) {
        var orig = resolveLValueIdentity(ctx, src_expr);
        if (orig == null) orig = resolveOrigin(ctx, src_expr);
        if (orig) |oid| {
            var ocanon = aliasResolveName(state, oid);
            if (smap_mod.stateMapGet(state, ocanon) != null) {
                aliasRecord(state, name_id, ocanon);
                aliasCopyState(state, name_id, ocanon);
            }
        }
    }
}

// T9a (D4a): the single fold accessor for the analyzers. The shared
// `ComptimeFoldTable` is authoritative (it is the same object sema and
// lowering consume); when a node has no table entry, fall back to the same
// comptime evaluator they use. No parallel fold table exists.
fn analyzerFoldComptimeVal(ctx: *AnalyzerContext, node_idx: u32) ?ce_mod.ComptimeVal {
    if (node_idx == @intCast(u32, 0)) return null;
    if (ctx.comptime_folds) |ft| {
        if (ce_mod.comptimeFoldTableGet(ft, node_idx)) |cv| return cv;
    }
    var sr = ctx.symbol_reg orelse return null;
    var ce = ce_mod.comptimeEvalInit(ctx.registry, ctx.store, ctx.interner, sr);
    ce.host_is_windows = ctx.target_is_windows;
    return ce_mod.comptimeEvalEvaluate(&ce, node_idx);
}

// T9a (DED-2): select the live switch prong with the SAME shared selector
// sema's conditional-import path uses. A table miss falls back to the
// evaluator (e.g. `switch (1 == 1)` has no fold-table entry). Non-decisive
// (unknown selector or an unevaluable case label) keeps every prong live.
fn analyzerSwitchSelection(ctx: *AnalyzerContext, sw_idx: u32) import_resolver.ImportSwitchSelection {
    var out = import_resolver.ImportSwitchSelection{ .decisive = false, .prong = @intCast(u32, 0) };
    var sn = ast_mod.astStoreNodeAt(ctx.store, sw_idx);
    var sv = analyzerFoldComptimeVal(ctx, sn.child_0) orelse return out;
    var sr = ctx.symbol_reg orelse return out;
    var ce = ce_mod.comptimeEvalInit(ctx.registry, ctx.store, ctx.interner, sr);
    ce.host_is_windows = ctx.target_is_windows;
    return import_resolver.importSwitchSelectProng(ctx.store, &ce, sw_idx, sv);
}

// T5 (T3 interaction — comptime-dead arms): per Zig semantics a
// comptime-untaken arm does not exist for analysis. The shared fold table is
// consulted first (T9a/D4a); the conservative bool-literal family
// (`parserFoldComptimeBool`: literals, parens, `!`/`&&`/`||`) remains as the
// fallback.
fn analyzerFoldComptimeBool(ctx: *AnalyzerContext, node_idx: u32, depth: u32) ?bool {
    if (node_idx == @intCast(u32, 0)) return null;
    if (depth >= @intCast(u32, 8)) return null;
    if (analyzerFoldComptimeVal(ctx, node_idx)) |cv| {
        if (cv.kind == ce_mod.KIND_BOOL) return !ce_mod.ciIsZero(cv.v);
    }
    var n = ast_mod.astStoreNodeAt(ctx.store, node_idx);
    if (n.kind == AstKind.bool_literal) {
        return (n.flags & @intCast(u8, 1)) != @intCast(u8, 0);
    }
    if (n.kind == AstKind.paren_expr) {
        return analyzerFoldComptimeBool(ctx, n.child_0, depth + @intCast(u32, 1));
    }
    if (n.kind == AstKind.bool_not) {
        if (analyzerFoldComptimeBool(ctx, n.child_0, depth + @intCast(u32, 1))) |v| {
            return !v;
        }
        return null;
    }
    if (n.kind == AstKind.bool_and) {
        if (analyzerFoldComptimeBool(ctx, n.child_0, depth + @intCast(u32, 1))) |l| {
            if (!l) return false;
            return analyzerFoldComptimeBool(ctx, n.child_1, depth + @intCast(u32, 1));
        }
        return null;
    }
    if (n.kind == AstKind.bool_or) {
        if (analyzerFoldComptimeBool(ctx, n.child_0, depth + @intCast(u32, 1))) |l| {
            if (l) return true;
            return analyzerFoldComptimeBool(ctx, n.child_1, depth + @intCast(u32, 1));
        }
        return null;
    }
    return null;
}

// T5: pointer-like parameter types (`*T`, `[*]T`, `[]T`, fn-ptr) own
// caller-side storage; the bare binding is still call-frame (dangling by
// address) but interiors follow the pointee.
fn paramTypeIsPointerLike(ctx: *AnalyzerContext, type_expr_idx: u32) bool {
    if (type_expr_idx == @intCast(u32, 0)) return false;
    var tnode = ast_mod.astStoreNodeAt(ctx.store, type_expr_idx);
    return tnode.kind == AstKind.ptr_type or tnode.kind == AstKind.many_ptr_type or
        tnode.kind == AstKind.slice_type or tnode.kind == AstKind.fn_type;
}

pub fn visitStatement(ctx: *AnalyzerContext, state: *StateMap, node_idx: u32, on_stmt: fn(*AnalyzerContext, *StateMap, u32) void, visit_fn: fn(*AnalyzerContext, *StateMap, u32) void) void {
    if (node_idx == @intCast(u32, 0)) return;
    var node = ast_mod.astStoreNodeAt(ctx.store, node_idx);
    var kind = node.kind;
    if (kind == AstKind.if_stmt or kind == AstKind.if_capture) {
        if (ctx.doublefree_analysis_mode != @intCast(u8, 0)) {
            checkUseAfterFreeExpr(ctx, state, node.child_0);
        }
        // T5 (T3 rule): a capture-free comptime-known condition takes the live
        // arm only — the untaken arm does not exist for analysis.
        var t5_fold = analyzerFoldComptimeBool(ctx, node.child_0, 0);
        if (t5_fold) |tfv| {
            if (ast_mod.astStoreNodePayload(ctx.store, node_idx) == @intCast(u32, 0)) {
                if (tfv) {
                    walkBlock(ctx, state, node.child_1, visit_fn);
                } else if (node.child_2 != @intCast(u32, 0)) {
                    walkBlock(ctx, state, node.child_2, visit_fn);
                }
                return;
            }
        }
        analyzeExpr(ctx, state, node.child_0);
        var then_state = smap_mod.stateMapFork(state, ctx.alloc);
        var else_state = smap_mod.stateMapFork(state, ctx.alloc);
        if (ctx.null_analysis_mode != @intCast(u8, 0)) {
            applyNullGuardRefinement(ctx.store, node.child_0, then_state, else_state);
        }
        var t5_cap = captureNameIdOf(ctx.store, node_idx);
        bindCaptureState(ctx, then_state, t5_cap, node.child_0);
        walkBlock(ctx, then_state, node.child_1, visit_fn);
        if (node.child_2 != @intCast(u32, 0)) walkBlock(ctx, else_state, node.child_2, visit_fn);
        smap_mod.stateMapMergeStates(state, then_state, else_state, @intCast(u8, 99));
        if (ctx.doublefree_analysis_mode != @intCast(u8, 0)) {
            aliasMergeBranches(state, then_state, else_state);
        }
    } else if (kind == AstKind.while_stmt or kind == AstKind.while_capture) {
        if (ctx.doublefree_analysis_mode != @intCast(u8, 0)) {
            checkUseAfterFreeExpr(ctx, state, node.child_0);
        }
        analyzeExpr(ctx, state, node.child_0);
        var body_state = smap_mod.stateMapFork(state, ctx.alloc);
        var t5_wcap = captureNameIdOf(ctx.store, node_idx);
        bindCaptureState(ctx, body_state, t5_wcap, node.child_0);
        walkBlock(ctx, body_state, node.child_1, visit_fn);
        smap_mod.stateMapMergeStates(state, state, body_state, @intCast(u8, 99));
        if (ctx.doublefree_analysis_mode != @intCast(u8, 0)) {
            aliasMergeBranchInto(state, body_state);
        }
    } else if (kind == AstKind.swt_ex) {
        if (ctx.doublefree_analysis_mode != @intCast(u8, 0)) {
            checkUseAfterFreeExpr(ctx, state, node.child_0);
        }
        analyzeExpr(ctx, state, node.child_0);
        // T9a (DED-2): a comptime-known selector makes exactly one prong (or
        // the `else` prong) live; a dead prong does not exist for analysis and
        // must not emit analyzer diagnostics. An undecidable selector/label
        // keeps every prong live (conservative).
        var sel = analyzerSwitchSelection(ctx, node_idx);
        var prongs_n = ast_mod.astStoreNodeExtraChildCount(ctx.store, node_idx);
        var si: usize = 0;
        while (si < @intCast(usize, prongs_n)) : (si += 1) {
            var prong_idx = ast_mod.astStoreNodeExtraChildAt(ctx.store, node_idx, @intCast(u32, si));
            if (sel.decisive and prong_idx != sel.prong) continue;
            var prong = ast_mod.astStoreNodeAt(ctx.store, prong_idx);
            var ps = smap_mod.stateMapFork(state, ctx.alloc);
            var t5_pcap = captureNameIdOf(ctx.store, prong_idx);
            bindCaptureState(ctx, ps, t5_pcap, node.child_0);
            walkBlock(ctx, ps, prong.child_0, visit_fn);
            smap_mod.stateMapMergeStates(state, state, ps, @intCast(u8, 99));
            if (ctx.doublefree_analysis_mode != @intCast(u8, 0)) {
                smap_mod.stateMapMergeInsertMissing(state, ps, @intCast(u8, @enumToInt(AllocState.unknown)));
                aliasMergeBranchInto(state, ps);
            }
        }
    } else if (kind == AstKind.for_stmt) {
        var body_state = smap_mod.stateMapFork(state, ctx.alloc);
        var t5_fcap = captureNameIdOf(ctx.store, node_idx);
        bindCaptureState(ctx, body_state, t5_fcap, node.child_0);
        walkBlock(ctx, body_state, node.child_1, visit_fn);
        smap_mod.stateMapMergeStates(state, state, body_state, @intCast(u8, 99));
        if (ctx.doublefree_analysis_mode != @intCast(u8, 0)) {
            aliasMergeBranchInto(state, body_state);
        }
    } else if (kind == AstKind.return_stmt) {
        if (node.child_0 != @intCast(u32, 0)) {
            // NP-2: return expressions are in scope for null derefs. The walk
            // is mode-gated inside `analyzeExpr`.
            analyzeExpr(ctx, state, node.child_0);
            if (ctx.lifetime_analysis_mode != @intCast(u8, 0)) {
                checkReturnProvenance(ctx, state, node.child_0, node_idx);
            }
            if (ctx.doublefree_analysis_mode != @intCast(u8, 0)) {
                handleOwnershipReturn(ctx, state, node.child_0);
            }
        }
        on_stmt(ctx, state, node_idx);
    } else if ((kind == AstKind.defer_stmt or kind == AstKind.errdefer_stmt) and ctx.in_defer_exec == @intCast(u8, 0)) {
        var dk: u8 = @intCast(u8, 0);
        if (kind == AstKind.errdefer_stmt) dk = @intCast(u8, 1);
        deferQueueEnsureCapacity(ctx, ctx.defer_queue_len + @intCast(usize, 1));
        ctx.defer_queue_items[ctx.defer_queue_len] = DeferEntry{ .kind = dk, .stmt_idx = node_idx, .scope_depth = ctx.current_depth };
        ctx.defer_queue_len += 1;
    } else if (ctx.null_analysis_mode != @intCast(u8, 0) and kind == AstKind.var_decl) {
        handleNullVarDecl(ctx, state, node_idx);
        on_stmt(ctx, state, node_idx);
    } else if (ctx.null_analysis_mode != @intCast(u8, 0) and kind == AstKind.plain_assign) {
        handleNullAssign(ctx, state, node_idx);
        on_stmt(ctx, state, node_idx);
    } else if (kind == AstKind.expr_stmt) {
        if (node.child_0 != @intCast(u32, 0)) {
            var inner = ast_mod.astStoreNodeAt(ctx.store, node.child_0);
            if (inner.kind == AstKind.swt_ex) {
                visitStatement(ctx, state, node.child_0, on_stmt, visit_fn);
            } else {
                analyzeExpr(ctx, state, node.child_0);
            }
        }
    } else if (kind == AstKind.block) {
        walkBlock(ctx, state, node_idx, visit_fn);
    } else if (kind == AstKind.labeled_stmt) {
        visitStatement(ctx, state, node.child_0, on_stmt, visit_fn);
    } else {
        on_stmt(ctx, state, node_idx);
    }
}

pub fn onNullStmt(ctx: *AnalyzerContext, state: *StateMap, node_idx: u32) void {
    _ = ctx; _ = state; _ = node_idx;
}

fn onLifetimeStmt(ctx: *AnalyzerContext, state: *StateMap, node_idx: u32) void {
    var node = ast_mod.astStoreNodeAt(ctx.store, node_idx);
    if (node.kind == AstKind.var_decl) {
        if (node.child_1 != @intCast(u32, 0)) {
            var prov = classifyProvenance(ctx, state, node.child_1);
            smap_mod.stateMapSet(state, ast_mod.astStoreNodePayload(ctx.store, node_idx), prov);
        } else {
            smap_mod.stateMapSet(state, ast_mod.astStoreNodePayload(ctx.store, node_idx), @intCast(u8, @enumToInt(Provenance.unknown)));
        }
     }
     if (node.kind == AstKind.plain_assign) {
         var lhs_node = ast_mod.astStoreNodeAt(ctx.store, node.child_0);
        if (lhs_node.kind == AstKind.ident_expr) {
            var prov = classifyProvenance(ctx, state, node.child_1);
            smap_mod.stateMapSet(state, ast_mod.astStoreNodePayload(ctx.store, node.child_0), prov);
        }
    }
}

fn onDoubleFreeStmt(ctx: *AnalyzerContext, state: *StateMap, node_idx: u32) void {
    var node = ast_mod.astStoreNodeAt(ctx.store, node_idx);
    checkUseAfterFreeExpr(ctx, state, node_idx);
    if (node.kind == AstKind.var_decl) {
        handleAllocVarDecl(ctx, state, node_idx);
     }
     if (node.kind == AstKind.plain_assign) {
         handleAllocAssign(ctx, state, node_idx);
    }
    if (node.kind == AstKind.fn_call) {
        var df_is_free = isFreeCall(ctx, node_idx) != null;
        var df_is_alloc = isAllocCall(ctx, node_idx);
        if (df_is_free or df_is_alloc) recordAllocatorHandle(ctx, node_idx);
        if (df_is_free) {
            handleFreeCall(ctx, state, node_idx);
        } else if (!df_is_alloc) {
            handleOwnershipPass(ctx, state, node_idx);
        }
    }
}

pub fn runSignatureAnalyzer(ctx: *AnalyzerContext, fn_decl_idx: u32) void {
    analyzeSignature(ctx, fn_decl_idx);
}

fn detectorVisit(ctx: *AnalyzerContext, state: *StateMap, node_idx: u32) void {
    visitStatement(ctx, state, node_idx, ctx.on_stmt_cb, detectorVisit);
}

pub fn runNullAnalyzer(ctx: *AnalyzerContext, fn_decl_idx: u32, fn_body_idx: u32) void {
    var state = smap_mod.stateMapInit(ctx.alloc);
    // NP-1: a non-optional pointer-like parameter (`*T`, `[*]T`, `[]T`,
    // fn-ptr) is caller-provided and non-null, so seed it `safe`. Optional
    // parameters are deliberately left unseeded (`maybe`, conservative) until
    // a guard or capture refines them.
    // NB: a function's proto index may legitimately be 0 (the first proto in
    // the store), so do not use payload==0 as an absence sentinel here.
    var proto = ctx.store.fn_protos.items[@intCast(usize, ast_mod.astStoreNodePayload(ctx.store, fn_decl_idx))];
    var pp: u64 = (@intCast(u64, proto.params_start) << @intCast(u64, 32)) | @intCast(u64, proto.params_count);
    var params_n = ast_mod.astStoreGetExtraChildCount(ctx.store, pp);
    var pi: usize = 0;
    while (pi < @intCast(usize, params_n)) : (pi += 1) {
        var pnode = ast_mod.astStoreNodeAt(ctx.store, ast_mod.astStoreGetExtraChildAt(ctx.store, pp, @intCast(u32, pi)));
        if (pnode.kind == AstKind.param_decl and paramTypeIsPointerLike(ctx, pnode.child_0)) {
            smap_mod.stateMapSet(&state, ast_mod.astStoreNodePayload(ctx.store, ast_mod.astStoreGetExtraChildAt(ctx.store, pp, @intCast(u32, pi))), @enumToInt(PtrState.safe));
        }
    }
    ctx.null_analysis_mode = @intCast(u8, 1);
    ctx.on_stmt_cb = onNullStmt;
    walkBlock(ctx, &state, fn_body_idx, detectorVisit);
    ctx.null_analysis_mode = @intCast(u8, 0);
}

pub fn runLifetimeAnalyzer(ctx: *AnalyzerContext, fn_decl_idx: u32, fn_body_idx: u32) void {
    var state = smap_mod.stateMapInit(ctx.alloc);
    var decl = ast_mod.astStoreNodeAt(ctx.store, fn_decl_idx);
    if (ast_mod.astStoreNodePayload(ctx.store, fn_decl_idx) != @intCast(u32, 0)) {
        var proto = ctx.store.fn_protos.items[@intCast(usize, ast_mod.astStoreNodePayload(ctx.store, fn_decl_idx))];
        var pp: u64 = (@intCast(u64, proto.params_start) << @intCast(u64, 32)) | @intCast(u64, proto.params_count);
        var params_n = ast_mod.astStoreGetExtraChildCount(ctx.store, pp);
        var pi: usize = 0;
        while (pi < @intCast(usize, params_n)) : (pi += 1) {
            var pnode = ast_mod.astStoreNodeAt(ctx.store, ast_mod.astStoreGetExtraChildAt(ctx.store, pp, @intCast(u32, pi)));
            if (pnode.kind == AstKind.param_decl) {
                // T5 (§2.1 base): pointer-like params (`*T`, `[*]T`, `[]T`,
                // fn-ptr) seed `external` — their pointee is caller-owned, so
                // interiors (`&p.field`) are safe to return; the bare address
                // of the binding (`&p`) still dangles (param_addr). By-value
                // params seed `param` — interiors are call-frame storage.
                var t5_pseed: u8 = @intCast(u8, @enumToInt(Provenance.param));
                if (paramTypeIsPointerLike(ctx, pnode.child_0)) {
                    t5_pseed = @intCast(u8, @enumToInt(Provenance.external));
                }
                smap_mod.stateMapSet(&state, ast_mod.astStoreNodePayload(ctx.store, ast_mod.astStoreGetExtraChildAt(ctx.store, pp, @intCast(u32, pi))), t5_pseed);
            }
        }
    }
    ctx.lifetime_analysis_mode = @intCast(u8, 1);
    ctx.on_stmt_cb = onLifetimeStmt;
    walkBlock(ctx, &state, fn_body_idx, detectorVisit);
    ctx.lifetime_analysis_mode = @intCast(u8, 0);
}

pub fn runDoubleFreeAnalyzer(ctx: *AnalyzerContext, fn_body_idx: u32) void {
    var state = smap_mod.stateMapInit(ctx.alloc);
    aliasReset();
    handleReset();
    ctx.doublefree_analysis_mode = @intCast(u8, 1);
    ctx.on_stmt_cb = onDoubleFreeStmt;
    walkBlock(ctx, &state, fn_body_idx, detectorVisit);
    ctx.doublefree_analysis_mode = @intCast(u8, 0);
}

pub const PER_FUNC_BUDGET: usize = 512 * 1024;

pub fn runAllAnalyzers(ctx: *AnalyzerContext, module_root_idx: u32) void {
    var root = ast_mod.astStoreNodeAt(ctx.store, module_root_idx);
    if (root.kind != AstKind.module_root) return;
    var decls_n = ast_mod.astStoreNodeExtraChildCount(ctx.store, module_root_idx);
    var di: usize = 0;
    while (di < @intCast(usize, decls_n)) : (di += 1) {
        var decl_idx = ast_mod.astStoreNodeExtraChildAt(ctx.store, module_root_idx, @intCast(u32, di));
        var decl = ast_mod.astStoreNodeAt(ctx.store, decl_idx);
        if (decl.kind != AstKind.fn_decl) continue;
        if (decl.child_0 == @intCast(u32, 0)) continue;
        alloc_mod.sandResetPeak(ctx.alloc);
        ctx.current_fn_name = ctx.store.fn_protos.items[@intCast(usize, ast_mod.astStoreNodePayload(ctx.store, decl_idx))].name_id;
        ctx.current_fn_span_start = decl.span_start;
        ctx.current_fn_span_end = decl.span_start + @intCast(u32, decl.span_len);
        if (ctx.current_fn_span_end <= ctx.current_fn_span_start) ctx.current_fn_span_end = ctx.current_fn_span_start + @intCast(u32, 1);
        runSignatureAnalyzer(ctx, decl_idx);
        alloc_mod.sandReset(ctx.alloc);
        resetDeferQueue(ctx);
        if (ctx.skip_null_check == @intCast(u8, 0)) {
            runNullAnalyzer(ctx, decl_idx, decl.child_0);
            alloc_mod.sandReset(ctx.alloc);
            resetDeferQueue(ctx);
        }
        if (ctx.skip_lifetime_check == @intCast(u8, 0)) {
            runLifetimeAnalyzer(ctx, decl_idx, decl.child_0);
            alloc_mod.sandReset(ctx.alloc);
            resetDeferQueue(ctx);
        }
        if (ctx.skip_doublefree_check == @intCast(u8, 0)) {
            runDoubleFreeAnalyzer(ctx, decl.child_0);
            alloc_mod.sandReset(ctx.alloc);
            resetDeferQueue(ctx);
        }
        if (ctx.alloc.peak > PER_FUNC_BUDGET) {

            var bmsg: []const u8 = "per-function analyzer budget exceeded";
            diag_mod.diagnosticCollectorAdd(ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_7002_ANALYZER_BUDGET_EXCEEDED)), @intCast(u32, 0), decl.span_start, decl.span_start + @intCast(u32, decl.span_len), bmsg);
        }
    }
}
