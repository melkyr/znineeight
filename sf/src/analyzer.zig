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
    // Internal marker for an array-typed local binding. Arrays are stack
    // storage, but returning the array BY VALUE copies it, so this must not
    // be treated as `local` by `checkReturnProvenance` (WARN_6010). It is
    // consumed only by the `slice_expr` arm, which maps it back to `local`
    // for WARN_6011 (a slice escapes the stack). Address-of and interior
    // paths already fall through to `local`.
    local_array = 7,
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

// Scratch for canonical reassignment. Collecting names before rewriting keeps
// resolution stable while the relation is being re-rooted.
var alias_reroot_names: [ALIAS_CAP]u32 = undefined;

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

// DF-1: on canonical reassignment, keep every inbound alias related as ONE
// class for the old allocation instead of forgetting each one separately (that
// fragmented the old allocation into independent roots and produced both false
// leaks and missed double frees). The first surviving alias becomes the new
// canonical name and every other survivor re-points at it. Returns the new
// root, or 0 when no inbound aliases survive.
fn aliasRerootInbound(state: *StateMap, root: u32) u32 {
    var n: usize = 0;
    var snap = alias_len;
    var i: usize = 0;
    while (i < snap) : (i += 1) {
        var name_id = alias_entries[i].name_id;
        if (name_id == root) continue;
        if (aliasNameInList(alias_reroot_names[0..], n, name_id)) continue;
        if (aliasResolveName(state, name_id) != root) continue;
        if (n >= ALIAS_CAP) break;
        alias_reroot_names[n] = name_id;
        n += 1;
    }
    if (n == 0) return @intCast(u32, 0);
    var survivor = alias_reroot_names[0];
    aliasForget(state, survivor);
    i = 0;
    while (i < n) : (i += 1) {
        if (alias_reroot_names[i] == survivor) continue;
        aliasSet(state, alias_reroot_names[i], survivor);
    }
    return survivor;
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

// T9h (D4h): declared-type substrate for null-base classification. The null
// pass has no resolved-type table in `AnalyzerContext` (adding one would touch
// main.zig/test constructors outside this task's file scope), so it resolves
// the type shapes it needs from the AST: module-root type declarations, local
// `var`/param annotations, and the already-resolved field entries in
// `TypeRegistry`. A declared non-optional pointer cannot be null, so a deref
// through it is safe; an optional pointer or an unknown call result stays
// `maybe`.
const NP_TYPE_CAP: usize = 8192;
const NP_FIELD_CACHE_CAP: usize = 1024;

const NpTypeDecl = struct { name_id: u32, decl_idx: u32 };
var np_type_decls: [NP_TYPE_CAP]NpTypeDecl = undefined;
var np_type_decl_len: usize = 0;

const NpDeclType = struct { name_id: u32, type_idx: u32 };
var np_decl_types: [NP_TYPE_CAP]NpDeclType = undefined;
var np_decl_type_len: usize = 0;

const NpFieldCacheEntry = struct { name_id: u32, cls: u8 };
var np_field_cache: [NP_FIELD_CACHE_CAP]NpFieldCacheEntry = undefined;
var np_field_cache_len: usize = 0;

fn npResetTypeDecls() void {
    np_type_decl_len = @intCast(usize, 0);
}

fn npTypeDeclAdd(name_id: u32, decl_idx: u32) void {
    if (name_id == @intCast(u32, 0) or decl_idx == @intCast(u32, 0)) return;
    if (np_type_decl_len >= NP_TYPE_CAP) return;
    np_type_decls[np_type_decl_len] = NpTypeDecl{ .name_id = name_id, .decl_idx = decl_idx };
    np_type_decl_len += 1;
}

fn npTypeDeclLookup(name_id: u32) ?u32 {
    if (name_id == @intCast(u32, 0)) return null;
    var i: usize = 0;
    while (i < np_type_decl_len) : (i += 1) {
        if (np_type_decls[i].name_id == name_id) return np_type_decls[i].decl_idx;
    }
    return null;
}

fn npCollectModuleTypeDecls(ctx: *AnalyzerContext, module_root_idx: u32) void {
    npResetTypeDecls();
    var n = ast_mod.astStoreNodeExtraChildCount(ctx.store, module_root_idx);
    var i: usize = 0;
    while (i < @intCast(usize, n)) : (i += 1) {
        var decl_idx = ast_mod.astStoreNodeExtraChildAt(ctx.store, module_root_idx, @intCast(u32, i));
        var d = ast_mod.astStoreNodeAt(ctx.store, decl_idx);
        if (d.kind != AstKind.var_decl) continue;
        var init_idx = d.child_1;
        if (init_idx == @intCast(u32, 0)) continue;
        var init = ast_mod.astStoreNodeAt(ctx.store, init_idx);
        if (init.kind != AstKind.struct_decl and init.kind != AstKind.union_decl) continue;
        npTypeDeclAdd(ast_mod.astStoreNodePayload(ctx.store, decl_idx), init_idx);
    }
}

fn npResetDeclTypes() void {
    np_decl_type_len = @intCast(usize, 0);
}

fn npDeclTypeSet(name_id: u32, type_idx: u32) void {
    if (name_id == @intCast(u32, 0) or type_idx == @intCast(u32, 0)) return;
    var i: usize = 0;
    while (i < np_decl_type_len) : (i += 1) {
        if (np_decl_types[i].name_id == name_id) {
            np_decl_types[i].type_idx = type_idx;
            return;
        }
    }
    if (np_decl_type_len >= NP_TYPE_CAP) return;
    np_decl_types[np_decl_type_len] = NpDeclType{ .name_id = name_id, .type_idx = type_idx };
    np_decl_type_len += 1;
}

fn npDeclTypeLookup(name_id: u32) ?u32 {
    if (name_id == @intCast(u32, 0)) return null;
    var i: usize = 0;
    while (i < np_decl_type_len) : (i += 1) {
        if (np_decl_types[i].name_id == name_id) return np_decl_types[i].type_idx;
    }
    return null;
}

fn npTypeExprIsNonNullPointer(ctx: *AnalyzerContext, type_idx: u32) bool {
    if (type_idx == @intCast(u32, 0)) return false;
    var tnode = ast_mod.astStoreNodeAt(ctx.store, type_idx);
    return tnode.kind == AstKind.ptr_type or tnode.kind == AstKind.many_ptr_type or tnode.kind == AstKind.fn_type;
}

fn npTypeExprIsPointer(ctx: *AnalyzerContext, type_idx: u32) bool {
    if (type_idx == @intCast(u32, 0)) return false;
    var tnode = ast_mod.astStoreNodeAt(ctx.store, type_idx);
    return tnode.kind == AstKind.ptr_type or tnode.kind == AstKind.many_ptr_type;
}

fn npFieldTypeInDecl(ctx: *AnalyzerContext, decl_idx: u32, field_id: u32) ?u32 {
    if (decl_idx == @intCast(u32, 0)) return null;
    var d = ast_mod.astStoreNodeAt(ctx.store, decl_idx);
    if (d.kind != AstKind.struct_decl and d.kind != AstKind.union_decl) return null;
    var n = ast_mod.astStoreNodeExtraChildCount(ctx.store, decl_idx);
    var i: usize = 0;
    while (i < @intCast(usize, n)) : (i += 1) {
        var f_idx = ast_mod.astStoreNodeExtraChildAt(ctx.store, decl_idx, @intCast(u32, i));
        var f = ast_mod.astStoreNodeAt(ctx.store, f_idx);
        if (f.kind != AstKind.field_decl) continue;
        if (ast_mod.astStoreNodePayload(ctx.store, f_idx) != field_id) continue;
        return f.child_0;
    }
    return null;
}

fn npTypeExprFieldType(ctx: *AnalyzerContext, type_idx: u32, field_id: u32) ?u32 {
    var cur = type_idx;
    var guard: u32 = 0;
    while (cur != @intCast(u32, 0) and guard < @intCast(u32, 16)) : (guard += 1) {
        var tnode = ast_mod.astStoreNodeAt(ctx.store, cur);
        if (tnode.kind == AstKind.ptr_type or tnode.kind == AstKind.many_ptr_type) {
            cur = tnode.child_0;
            continue;
        }
        // T9h: an optional base cannot be treated as a resolved non-optional
        // field owner. Return the optional type itself so classification
        // stays `maybe` instead of falling through to the safe field-name
        // fallback.
        if (tnode.kind == AstKind.optional_type) return cur;
        if (tnode.kind == AstKind.struct_decl or tnode.kind == AstKind.union_decl) {
            return npFieldTypeInDecl(ctx, cur, field_id);
        }
        if (tnode.kind == AstKind.ident_expr) {
            var decl = npTypeDeclLookup(ast_mod.astStoreIdentifier(ctx.store, cur)) orelse return null;
            return npFieldTypeInDecl(ctx, decl, field_id);
        }
        if (tnode.kind == AstKind.field_access) {
            var name_id = ast_mod.astStoreNodePayload(ctx.store, cur);
            var decl = npTypeDeclLookup(name_id) orelse return null;
            return npFieldTypeInDecl(ctx, decl, field_id);
        }
        return null;
    }
    return null;
}

fn npTypeExprElemType(ctx: *AnalyzerContext, type_idx: u32) ?u32 {
    if (type_idx == @intCast(u32, 0)) return null;
    var tnode = ast_mod.astStoreNodeAt(ctx.store, type_idx);
    if (tnode.kind == AstKind.slice_type or tnode.kind == AstKind.many_ptr_type or tnode.kind == AstKind.array_type) {
        return tnode.child_0;
    }
    return null;
}

fn npTypeExprPointeeType(ctx: *AnalyzerContext, type_idx: u32) ?u32 {
    if (type_idx == @intCast(u32, 0)) return null;
    var tnode = ast_mod.astStoreNodeAt(ctx.store, type_idx);
    if (tnode.kind == AstKind.ptr_type or tnode.kind == AstKind.many_ptr_type) return tnode.child_0;
    return null;
}

fn npTypeExprUnwrapOptional(ctx: *AnalyzerContext, type_idx: u32) ?u32 {
    if (type_idx == @intCast(u32, 0)) return null;
    var tnode = ast_mod.astStoreNodeAt(ctx.store, type_idx);
    if (tnode.kind == AstKind.optional_type) return tnode.child_0;
    return null;
}

fn npTypeExprUnwrapErrorUnion(ctx: *AnalyzerContext, type_idx: u32) ?u32 {
    if (type_idx == @intCast(u32, 0)) return null;
    var tnode = ast_mod.astStoreNodeAt(ctx.store, type_idx);
    if (tnode.kind == AstKind.error_union_type) return tnode.child_1;
    return null;
}

fn npExprType(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32) ?u32 {
    _ = state;
    if (expr_idx == @intCast(u32, 0)) return null;
    var node = ast_mod.astStoreNodeAt(ctx.store, expr_idx);
    var kind = node.kind;
    if (kind == AstKind.ident_expr) return npDeclTypeLookup(ast_mod.astStoreIdentifier(ctx.store, expr_idx));
    if (kind == AstKind.paren_expr) return npExprType(ctx, state, node.child_0);
    if (kind == AstKind.field_access) {
        var base_t = npExprType(ctx, state, node.child_0) orelse return null;
        return npTypeExprFieldType(ctx, base_t, ast_mod.astStoreNodePayload(ctx.store, expr_idx));
    }
    if (kind == AstKind.index_access) {
        var base_t = npExprType(ctx, state, node.child_0) orelse return null;
        return npTypeExprElemType(ctx, base_t);
    }
    if (kind == AstKind.deref) {
        var base_t = npExprType(ctx, state, node.child_0) orelse return null;
        return npTypeExprPointeeType(ctx, base_t);
    }
    if (kind == AstKind.try_expr) {
        var base_t = npExprType(ctx, state, node.child_0) orelse return null;
        return npTypeExprUnwrapErrorUnion(ctx, base_t);
    }
    if (kind == AstKind.catch_expr) {
        var base_t = npExprType(ctx, state, node.child_0) orelse return null;
        var unwrapped = npTypeExprUnwrapErrorUnion(ctx, base_t);
        if (unwrapped) |u| return u;
        return npTypeExprUnwrapOptional(ctx, base_t);
    }
    if (kind == AstKind.builtin_call) {
        var name_id = node.child_0;
        if (npBuiltinNameIs(ctx, name_id, "@ptrCast") or npBuiltinNameIs(ctx, name_id, "@intToPtr") or
            npBuiltinNameIs(ctx, name_id, "@alignCast")) {
            var argc = ast_mod.astStoreNodeExtraChildCount(ctx.store, expr_idx);
            if (argc >= @intCast(u32, 1)) {
                var type_idx = ast_mod.astStoreNodeExtraChildAt(ctx.store, expr_idx, @intCast(u32, 0));
                var tnode = ast_mod.astStoreNodeAt(ctx.store, type_idx);
                if (tnode.kind == AstKind.ptr_type or tnode.kind == AstKind.many_ptr_type or
                    tnode.kind == AstKind.slice_type or tnode.kind == AstKind.array_type or
                    tnode.kind == AstKind.optional_type or tnode.kind == AstKind.error_union_type or
                    tnode.kind == AstKind.fn_type) {
                    return type_idx;
                }
            }
        }
        return null;
    }
    if (kind == AstKind.slice_expr) {
        var base_t = npExprType(ctx, state, node.child_0) orelse return null;
        var tnode = ast_mod.astStoreNodeAt(ctx.store, base_t);
        if (tnode.kind == AstKind.slice_type or tnode.kind == AstKind.many_ptr_type or tnode.kind == AstKind.array_type) return base_t;
        return null;
    }
    if (kind == AstKind.add or kind == AstKind.sub) {
        var left_t = npExprType(ctx, state, node.child_0) orelse return null;
        if (npTypeExprIsPointer(ctx, left_t)) return left_t;
        return null;
    }
    return null;
}

fn npFieldTypeClass(ctx: *AnalyzerContext, type_id: u32) u8 {
    if (@intCast(usize, type_id) >= ctx.registry.types_len) return @intCast(u8, 2);
    var ty = ctx.registry.types_items[@intCast(usize, type_id)];
    if (ty.kind == type_mod.TypeKind.ptr_type or ty.kind == type_mod.TypeKind.many_ptr_type or ty.kind == type_mod.TypeKind.fn_type) return @intCast(u8, 1);
    return @intCast(u8, 2);
}

fn npFieldCacheGet(name_id: u32) ?u8 {
    var i: usize = 0;
    while (i < np_field_cache_len) : (i += 1) {
        if (np_field_cache[i].name_id == name_id) return np_field_cache[i].cls;
    }
    return null;
}

fn npFieldCachePut(name_id: u32, cls: u8) void {
    if (name_id == @intCast(u32, 0)) return;
    if (np_field_cache_len >= NP_FIELD_CACHE_CAP) return;
    np_field_cache[np_field_cache_len] = NpFieldCacheEntry{ .name_id = name_id, .cls = cls };
    np_field_cache_len += 1;
}

// Resolved-type fallback: a field name that appears only on non-optional
// pointer fields is safe. Ambiguous/optional/non-pointer declarations stay
// `maybe`; a name with no resolved field entry returns null so the caller can
// preserve the conservative default.
fn npRegistryFieldClass(ctx: *AnalyzerContext, name_id: u32) ?u8 {
    if (name_id == @intCast(u32, 0)) return null;
    if (npFieldCacheGet(name_id)) |cached| return cached;
    var any: bool = false;
    var bad: bool = false;
    var i: usize = 0;
    while (i < ctx.registry.types_len) : (i += 1) {
        var ty = ctx.registry.types_items[i];
        var fields: []type_mod.FieldEntry = undefined;
        var have_fields: bool = false;
        if (ty.kind == type_mod.TypeKind.struct_type) {
            if (@intCast(usize, ty.payload_idx) >= ctx.registry.st_len) continue;
            var sp = ctx.registry.st_items[@intCast(usize, ty.payload_idx)];
            var start = @intCast(usize, sp.fields_start);
            var count = @intCast(usize, sp.fields_count);
            if (start + count > ctx.registry.fe_len) continue;
            fields = ctx.registry.fe_items[start .. start + count];
            have_fields = true;
        } else if (ty.kind == type_mod.TypeKind.union_type) {
            if (@intCast(usize, ty.payload_idx) >= ctx.registry.un_len) continue;
            var up = ctx.registry.un_items[@intCast(usize, ty.payload_idx)];
            var start = @intCast(usize, up.fields_start);
            var count = @intCast(usize, up.fields_count);
            if (start + count > ctx.registry.fe_len) continue;
            fields = ctx.registry.fe_items[start .. start + count];
            have_fields = true;
        } else if (ty.kind == type_mod.TypeKind.tagged_union_type) {
            if (@intCast(usize, ty.payload_idx) >= ctx.registry.tu_len) continue;
            var tp = ctx.registry.tu_items[@intCast(usize, ty.payload_idx)];
            var start = @intCast(usize, tp.fields_start);
            var count = @intCast(usize, tp.fields_count);
            if (start + count > ctx.registry.fe_len) continue;
            fields = ctx.registry.fe_items[start .. start + count];
            have_fields = true;
        }
        if (!have_fields) continue;
        var fi: usize = 0;
        while (fi < fields.len) : (fi += 1) {
            if (fields[fi].name_id != name_id) continue;
            any = true;
            if (npFieldTypeClass(ctx, fields[fi].type_id) != @intCast(u8, 1)) bad = true;
        }
    }
    if (!any) return null;
    if (bad) {
        npFieldCachePut(name_id, @intCast(u8, 2));
        return @intCast(u8, 2);
    }
    npFieldCachePut(name_id, @intCast(u8, 1));
    return @intCast(u8, 1);
}

fn npResetFieldCache() void {
    np_field_cache_len = @intCast(usize, 0);
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
            // Module-root globals are the only name class the real
            // symbol_registrator inserts. Function locals, params, and
            // captures never enter that table, so their provenance comes
            // from the analyzer state map (seeded params, tracked vars,
            // captures). The old SymbolKind.local/.param arm was therefore
            // structurally dead on the real pipeline and is deleted
            // (LIFE-2 / L12). Non-local symbol kinds still cannot be
            // storage-provenanced here and stay conservative.
            var sym = sym_mod.symbolTableLookup(ctx.symbols, name_id);
            if (sym) |s| {
                if (s.kind == SymbolKind.global) {
                    t5_base = @intCast(u8, @enumToInt(Provenance.global));
                } else if (s.kind != SymbolKind.local and s.kind != SymbolKind.param) {
                    return @intCast(u8, @enumToInt(Provenance.unknown));
                }
            }
            if (t5_base == @intCast(u8, 255)) {
                var pv = smap_mod.stateMapGet(state, name_id);
                if (pv) |v| {
                    t5_base = v;
                } else {
                    // An untracked binding is a conservative local.
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
        // WARN_6011 needs the base's storage class, not just a tracked
        // value: `var arr: [N]T = ...; return arr[0..n]` escapes the stack
        // even though the initializer itself carries no provenance. Array
        // declarations are recorded `local` by onLifetimeStmt. A tracked
        // value wins (external/heap/global/local, including unknown for an
        // indirect pointer initializer such as `@ptrCast`); a module-root
        // global is safe; an untracked name is conservative local storage. A
        // dereference base is still not resolved (documented
        // no-alias-through-deref limit).
        var base_id = resolveOrigin(ctx, node.child_0);
        if (base_id) |bid| {
            var result = smap_mod.stateMapGet(state, bid);
            if (result) |v| {
                // An array local is `local_array` so a by-value return stays
                // clean; slicing it is still an escape of stack storage.
                if (v == @intCast(u8, @enumToInt(Provenance.local_array))) return @intCast(u8, @enumToInt(Provenance.local));
                return v;
            }
            var base_sym = sym_mod.symbolTableLookup(ctx.symbols, bid);
            if (base_sym) |s| {
                if (s.kind == SymbolKind.global) return @intCast(u8, @enumToInt(Provenance.global));
                if (s.kind != SymbolKind.local and s.kind != SymbolKind.param) {
                    return @intCast(u8, @enumToInt(Provenance.unknown));
                }
            }
            return @intCast(u8, @enumToInt(Provenance.local));
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
    // Only `untracked` (or an absent entry) reaches here: `allocated`, `freed`,
    // and the unowned states are handled above. Preserve the state and report
    // the untracked free; marking it freed would silently drop the diagnostic
    // (DF-4 regression).
    emitFreeingUntracked(ctx, target_id, expr_idx);
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
        _ = aliasRerootInbound(state, lhs_root);
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

fn npBuiltinNameIs(ctx: *AnalyzerContext, name_id: u32, expected: []const u8) bool {
    var got = interner_mod.stringInternerGet(ctx.interner, name_id);
    if (got.len != expected.len) return false;
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        if (got[i] != expected[i]) return false;
    }
    return true;
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
    if (kind == AstKind.if_expr) {
        // T9h: a capture-free `if` expression has the merged state of both
        // arms. Agreement preserves it (both safe -> safe); any divergence or
        // a missing else arm stays `maybe`.
        if (ast_mod.astStoreNodePayload(ctx.store, expr_idx) != @intCast(u32, 0)) return @enumToInt(PtrState.maybe);
        if (node.child_2 == @intCast(u32, 0)) return @enumToInt(PtrState.maybe);
        var then_st = classifyExpr(ctx, state, node.child_1);
        var else_st = classifyExpr(ctx, state, node.child_2);
        if (then_st == else_st) return then_st;
        return @enumToInt(PtrState.maybe);
    }
    if (kind == AstKind.int_literal) {
        var val = ast_mod.astStoreIntValue(ctx.store, expr_idx);
        if (val == @intCast(u64, 0)) return @enumToInt(PtrState.is_null);
        return @enumToInt(PtrState.safe);
    }
    if (kind == AstKind.builtin_call) {
        // T9h: `@ptrCast`/`@intToPtr` preserve the null state of their source
        // value. A cast of `&x`, a proven non-null pointer, a non-zero integer,
        // or a guarded-nonzero value is safe; a cast of an optional/unknown
        // call result stays `maybe`.
        var name_id = node.child_0;
        var preserves_source = npBuiltinNameIs(ctx, name_id, "@ptrCast") or npBuiltinNameIs(ctx, name_id, "@intToPtr") or
            npBuiltinNameIs(ctx, name_id, "@intCast") or npBuiltinNameIs(ctx, name_id, "@bitCast") or
            npBuiltinNameIs(ctx, name_id, "@alignCast") or npBuiltinNameIs(ctx, name_id, "@truncate");
        if (preserves_source) {
            var argc = ast_mod.astStoreNodeExtraChildCount(ctx.store, expr_idx);
            if (argc >= @intCast(u32, 2)) {
                var src_idx = ast_mod.astStoreNodeExtraChildAt(ctx.store, expr_idx, @intCast(u32, 1));
                var src_state = classifyExpr(ctx, state, src_idx);
                if (src_state == @enumToInt(PtrState.is_null)) return @enumToInt(PtrState.is_null);
                if (src_state == @enumToInt(PtrState.safe)) return @enumToInt(PtrState.safe);
            }
        }
        return @enumToInt(PtrState.maybe);
    }
    if (kind == AstKind.field_access) {
        // T9h: a declared non-optional pointer field is non-null.
        if (npExprType(ctx, state, expr_idx)) |field_t| {
            if (npTypeExprIsNonNullPointer(ctx, field_t)) return @enumToInt(PtrState.safe);
            return @enumToInt(PtrState.maybe);
        }
        var field_name = ast_mod.astStoreNodePayload(ctx.store, expr_idx);
        if (npRegistryFieldClass(ctx, field_name)) |cls| return cls;
        return @enumToInt(PtrState.maybe);
    }
    if (kind == AstKind.index_access) {
        // T9h: an element of `[]*T`/`[*]*T`/`[N]*T` is a non-optional pointer.
        if (npExprType(ctx, state, expr_idx)) |elem_t| {
            if (npTypeExprIsNonNullPointer(ctx, elem_t)) return @enumToInt(PtrState.safe);
            return @enumToInt(PtrState.maybe);
        }
        return @enumToInt(PtrState.maybe);
    }
    if (kind == AstKind.add or kind == AstKind.sub) {
        // T9h: pointer arithmetic preserves a non-null pointer base.
        if (npExprType(ctx, state, node.child_0)) |left_t| {
            if (npTypeExprIsPointer(ctx, left_t)) return classifyExpr(ctx, state, node.child_0);
        }
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
    var declared_t = node.child_0;
    if (declared_t != @intCast(u32, 0)) npDeclTypeSet(name_id, declared_t);
    if (init_idx != @intCast(u32, 0)) {
        // NP-3: `var` initializers are in scope for null derefs.
        analyzeExpr(ctx, state, init_idx);
        var st = classifyExpr(ctx, state, init_idx);
        // T9h: the declaration's type shape is recorded for field/index base
        // resolution, but the initializer's own classification is preserved:
        // an optional/unknown call result stays `maybe` even when the binding
        // is annotated non-optional.
        smap_mod.stateMapSet(state, name_id, st);
        if (declared_t == @intCast(u32, 0)) {
            if (npExprType(ctx, state, init_idx)) |inferred_t| npDeclTypeSet(name_id, inferred_t);
        }
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
        // T9h: keep the RHS-derived state; a declared pointer type does not
        // mask an optional/unknown call result.
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
        // T9h: a capture of an optional payload is the unwrapped non-optional
        // type (`if (p) |q|`, `while (p) |q|`), so record it for field/index
        // base resolution.
        if (npExprType(ctx, state, src_expr)) |src_t| {
            if (npTypeExprUnwrapOptional(ctx, src_t)) |payload_t| npDeclTypeSet(name_id, payload_t);
        }
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

const NP_CTRL_MAX: usize = 32;
const NP_CTRL_EXIT_MAX: usize = 64;
const NP_MERGE_CAP: usize = 160;

var np_ctrl_depth: usize = 0;
var np_ctrl_break_count: [NP_CTRL_MAX]usize = undefined;
var np_ctrl_continue_count: [NP_CTRL_MAX]usize = undefined;
var np_ctrl_breaks: [NP_CTRL_MAX][NP_CTRL_EXIT_MAX]*StateMap = undefined;
var np_ctrl_continues: [NP_CTRL_MAX][NP_CTRL_EXIT_MAX]*StateMap = undefined;

fn npPushCtrl() ?usize {
    if (np_ctrl_depth >= NP_CTRL_MAX) return null;
    var idx = np_ctrl_depth;
    np_ctrl_break_count[idx] = @intCast(usize, 0);
    np_ctrl_continue_count[idx] = @intCast(usize, 0);
    np_ctrl_depth += 1;
    return idx;
}

fn npPopCtrl() void {
    if (np_ctrl_depth > @intCast(usize, 0)) np_ctrl_depth -= 1;
}

fn npSnapshotState(ctx: *AnalyzerContext, state: *StateMap) *StateMap {
    var raw = alloc_mod.sandAlloc(ctx.alloc, @intCast(usize, @sizeOf(StateMap)), @intCast(usize, 4)) catch unreachable;
    var snap = @ptrCast(*StateMap, raw);
    snap.* = smap_mod.stateMapInit(ctx.alloc);
    var s: ?*StateMap = state;
    while (s) |sp| {
        var entries = smap_mod.stateMapGetEntries(sp);
        var i = entries.len;
        while (i > @intCast(usize, 0)) {
            i -= 1;
            var e = entries[i];
            if (smap_mod.stateMapGet(snap, e.name_id) == null) smap_mod.stateMapSet(snap, e.name_id, e.state);
        }
        s = sp.parent;
    }
    return snap;
}

fn npRecordCtrlExit(ctx: *AnalyzerContext, state: *StateMap, is_break: u8) void {
    var i = np_ctrl_depth;
    while (i > @intCast(usize, 0)) {
        i -= 1;
        var snap = npSnapshotState(ctx, state);
        if (is_break != @intCast(u8, 0)) {
            if (np_ctrl_break_count[i] < NP_CTRL_EXIT_MAX) {
                np_ctrl_breaks[i][np_ctrl_break_count[i]] = snap;
                np_ctrl_break_count[i] += 1;
            }
        } else {
            if (np_ctrl_continue_count[i] < NP_CTRL_EXIT_MAX) {
                np_ctrl_continues[i][np_ctrl_continue_count[i]] = snap;
                np_ctrl_continue_count[i] += 1;
            }
        }
        return;
    }
}

fn npAppendCtrlExits(frame_idx: usize, branches: []*StateMap, n: *usize) void {
    var bi: usize = 0;
    while (bi < np_ctrl_break_count[frame_idx]) : (bi += 1) {
        if (n.* >= branches.len) break;
        branches[n.*] = np_ctrl_breaks[frame_idx][bi];
        n.* += 1;
    }
    bi = 0;
    while (bi < np_ctrl_continue_count[frame_idx]) : (bi += 1) {
        if (n.* >= branches.len) break;
        branches[n.*] = np_ctrl_continues[frame_idx][bi];
        n.* += 1;
    }
}

fn npMergeNullExits(parent: *StateMap, branches: []*StateMap, scratch: *Sand) void {
    if (branches.len == @intCast(usize, 0)) return;
    var fallback: u8 = @enumToInt(PtrState.maybe);
    if (branches.len == @intCast(usize, 1)) {
        smap_mod.stateMapMergeStates(parent, branches[0], branches[0], fallback);
        return;
    }
    var acc = smap_mod.stateMapFork(parent, scratch);
    smap_mod.stateMapMergeStates(acc, branches[0], branches[1], fallback);
    var i: usize = 2;
    while (i < branches.len) : (i += 1) {
        smap_mod.stateMapMergeStates(acc, acc, branches[i], fallback);
    }
    smap_mod.stateMapMergeStates(parent, acc, acc, fallback);
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
        if (ctx.null_analysis_mode != @intCast(u8, 0)) {
            var np_if_exits: [2]*StateMap = undefined;
            np_if_exits[0] = then_state;
            np_if_exits[1] = else_state;
            npMergeNullExits(state, np_if_exits[0..], ctx.alloc);
        } else {
            smap_mod.stateMapMergeStates(state, then_state, else_state, @intCast(u8, 99));
        }
        if (ctx.doublefree_analysis_mode != @intCast(u8, 0)) {
            aliasMergeBranches(state, then_state, else_state);
        }
    } else if (kind == AstKind.while_stmt or kind == AstKind.while_capture) {
        if (ctx.doublefree_analysis_mode != @intCast(u8, 0)) {
            checkUseAfterFreeExpr(ctx, state, node.child_0);
        }
        analyzeExpr(ctx, state, node.child_0);
        var body_state = smap_mod.stateMapFork(state, ctx.alloc);
        var exit_state = smap_mod.stateMapFork(state, ctx.alloc);
        if (ctx.null_analysis_mode != @intCast(u8, 0)) {
            // T9h: the loop condition holds on every body iteration, so a
            // null/non-zero guard refines the body state. The loop may also
            // exit because the guard failed before the first iteration, which
            // is exactly the refinement carried by `exit_state`.
            applyNullGuardRefinement(ctx.store, node.child_0, body_state, exit_state);
        }
        var np_w_frame: ?usize = null;
        if (ctx.null_analysis_mode != @intCast(u8, 0)) np_w_frame = npPushCtrl();
        var t5_wcap = captureNameIdOf(ctx.store, node_idx);
        bindCaptureState(ctx, body_state, t5_wcap, node.child_0);
        walkBlock(ctx, body_state, node.child_1, visit_fn);
        if (ctx.null_analysis_mode != @intCast(u8, 0)) {
            var np_w_exits: [NP_MERGE_CAP]*StateMap = undefined;
            var np_w_n: usize = 0;
            np_w_exits[np_w_n] = body_state;
            np_w_n += 1;
            np_w_exits[np_w_n] = exit_state;
            np_w_n += 1;
            if (np_w_frame) |fi| npAppendCtrlExits(fi, np_w_exits[0..], &np_w_n);
            npMergeNullExits(state, np_w_exits[0..np_w_n], ctx.alloc);
            if (np_w_frame != null) npPopCtrl();
        } else {
            smap_mod.stateMapMergeStates(state, state, body_state, @intCast(u8, 99));
        }
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
        var np_s_exits: [NP_MERGE_CAP]*StateMap = undefined;
        var np_s_n: usize = 0;
        var si: usize = 0;
        while (si < @intCast(usize, prongs_n)) : (si += 1) {
            var prong_idx = ast_mod.astStoreNodeExtraChildAt(ctx.store, node_idx, @intCast(u32, si));
            if (sel.decisive and prong_idx != sel.prong) continue;
            var prong = ast_mod.astStoreNodeAt(ctx.store, prong_idx);
            var ps = smap_mod.stateMapFork(state, ctx.alloc);
            var t5_pcap = captureNameIdOf(ctx.store, prong_idx);
            bindCaptureState(ctx, ps, t5_pcap, node.child_0);
            walkBlock(ctx, ps, prong.child_0, visit_fn);
            if (ctx.null_analysis_mode != @intCast(u8, 0)) {
                if (np_s_n < NP_MERGE_CAP) {
                    np_s_exits[np_s_n] = ps;
                    np_s_n += 1;
                }
            } else {
                smap_mod.stateMapMergeStates(state, state, ps, @intCast(u8, 99));
                if (ctx.doublefree_analysis_mode != @intCast(u8, 0)) {
                    smap_mod.stateMapMergeInsertMissing(state, ps, @intCast(u8, @enumToInt(AllocState.unknown)));
                    aliasMergeBranchInto(state, ps);
                }
            }
        }
        if (ctx.null_analysis_mode != @intCast(u8, 0)) {
            if (np_s_n > @intCast(usize, 0)) npMergeNullExits(state, np_s_exits[0..np_s_n], ctx.alloc);
        }
    } else if (kind == AstKind.for_stmt) {
        var body_state = smap_mod.stateMapFork(state, ctx.alloc);
        var np_f_frame: ?usize = null;
        if (ctx.null_analysis_mode != @intCast(u8, 0)) np_f_frame = npPushCtrl();
        var t5_fcap = captureNameIdOf(ctx.store, node_idx);
        bindCaptureState(ctx, body_state, t5_fcap, node.child_0);
        walkBlock(ctx, body_state, node.child_1, visit_fn);
        if (ctx.null_analysis_mode != @intCast(u8, 0)) {
            var np_f_exits: [NP_MERGE_CAP]*StateMap = undefined;
            var np_f_n: usize = 0;
            np_f_exits[np_f_n] = body_state;
            np_f_n += 1;
            if (np_f_frame) |fi| npAppendCtrlExits(fi, np_f_exits[0..], &np_f_n);
            npMergeNullExits(state, np_f_exits[0..np_f_n], ctx.alloc);
            if (np_f_frame != null) npPopCtrl();
        } else {
            smap_mod.stateMapMergeStates(state, state, body_state, @intCast(u8, 99));
        }
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
    } else if (ctx.null_analysis_mode != @intCast(u8, 0) and (kind == AstKind.break_stmt or kind == AstKind.continue_stmt)) {
        var np_is_break: u8 = @intCast(u8, 0);
        if (kind == AstKind.break_stmt) np_is_break = @intCast(u8, 1);
        npRecordCtrlExit(ctx, state, np_is_break);
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
        // An array binding is stack storage regardless of what its
        // initializer's expression provenance says (`undefined`, a literal,
        // or a call): slicing it must classify local for WARN_6011. Record
        // the distinct `local_array` marker so a by-value array return is not
        // misreported as WARN_6010; the `slice_expr` arm maps it to `local`.
        // Pointer bindings still take their initializer's provenance so an
        // indirect pointer (e.g. `@ptrCast` of a heap allocation) is not
        // mislabeled.
        var t5_array_local: u8 = @intCast(u8, 0);
        if (node.child_0 != @intCast(u32, 0)) {
            var type_node = ast_mod.astStoreNodeAt(ctx.store, node.child_0);
            if (type_node.kind == AstKind.array_type) t5_array_local = @intCast(u8, 1);
        }
        if (t5_array_local == @intCast(u8, 0) and node.child_1 != @intCast(u32, 0)) {
            var init_node = ast_mod.astStoreNodeAt(ctx.store, node.child_1);
            if (init_node.kind == AstKind.array_init) t5_array_local = @intCast(u8, 1);
        }
        if (t5_array_local != @intCast(u8, 0)) {
            smap_mod.stateMapSet(state, ast_mod.astStoreNodePayload(ctx.store, node_idx), @intCast(u8, @enumToInt(Provenance.local_array)));
        } else if (node.child_1 != @intCast(u32, 0)) {
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
    np_ctrl_depth = @intCast(usize, 0);
    npResetDeclTypes();
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
        var param_idx = ast_mod.astStoreGetExtraChildAt(ctx.store, pp, @intCast(u32, pi));
        var pnode = ast_mod.astStoreNodeAt(ctx.store, param_idx);
        if (pnode.kind != AstKind.param_decl) continue;
        // T9h: remember the declared type shape so field/index bases can be
        // resolved without a resolved-type table.
        npDeclTypeSet(ast_mod.astStoreNodePayload(ctx.store, param_idx), pnode.child_0);
        if (paramTypeIsPointerLike(ctx, pnode.child_0)) {
            smap_mod.stateMapSet(&state, ast_mod.astStoreNodePayload(ctx.store, param_idx), @enumToInt(PtrState.safe));
        }
    }
    ctx.null_analysis_mode = @intCast(u8, 1);
    ctx.on_stmt_cb = onNullStmt;
    walkBlock(ctx, &state, fn_body_idx, detectorVisit);
    ctx.null_analysis_mode = @intCast(u8, 0);
}

pub fn runLifetimeAnalyzer(ctx: *AnalyzerContext, fn_decl_idx: u32, fn_body_idx: u32) void {
    var state = smap_mod.stateMapInit(ctx.alloc);
    // A function's proto index may legitimately be 0 (the first proto in the
    // store), so the payload is not an absence sentinel. (Task 9b flagged the
    // latent first-proto seed bug; this is the lifetime-pass fix for it.)
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
    // T9h: build the per-module declared-type map and reset the resolved-field
    // cache before the function walk.
    npCollectModuleTypeDecls(ctx, module_root_idx);
    npResetFieldCache();
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
