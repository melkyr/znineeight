// async_analysis.zig — Stage 1 suspension analysis (Track 2, Task 3).
//
// Computes the program-wide `is_suspending` fixed point over the AST direct-call
// graph and stores it in `CompilerContext.suspending_fns`
// (key = (module_id << 32) | name_id; value 0/1). The pass runs in `runCompiler`
// immediately after `phase_SymbolRegistration`, before `phase_TypeResolution`.
//
// Edges are direct calls only (ident_expr and module-qualified field_access
// callees, resolved through `symbolRegistryQualifiedLookup`). A function is
// seeded when its body directly contains `@asyncSuspend`. Propagation is a
// monotone worklist over a CSR reverse index (callers of a suspending callee
// become suspending); mutual recursion is ordinary propagation, never recursive
// descent. `frame_sizes` and `state_widths` are written by `asyncFrameSizeRun`
// (P2); `state_widths[key]` is the u8/u16/u32 `state` field type chosen from
// that function's suspension-point count (spec §3.2 item 3) and is the single
// source of truth read by P3, `@asyncInit` lowering, and the Stage-3 transform.
//
// NOTE: this module deliberately does NOT `@import("main.zig")`. Importing the
// bootstrap root from a submodule makes the self-emitter register main.zig as a
// non-root import, which renames the compiler entry (`..._main_1`) and drops the
// root `int main` wrapper; the compiler then fails to link. The pass therefore
// takes the concrete CompilerContext components it needs as parameters.

const alloc_mod = @import("allocator.zig");
const ast_mod = @import("ast.zig");
const AstKind = ast_mod.AstKind;
const ga_mod = @import("growable_array.zig");
const hash_mod = @import("util/hash.zig");
const itoa_mod = @import("util/itoa.zig");
const mr_mod = @import("module_registry.zig");
const pal = @import("pal.zig");
const rtt_mod = @import("resolved_type_table.zig");
const si_mod = @import("string_interner.zig");
const sym_mod = @import("symbol_table.zig");
const type_mod = @import("type_registry.zig");

pub fn asyncKey(module_id: u32, name_id: u32) u64 {
    return (@intCast(u64, module_id) << @intCast(u64, 32)) | @intCast(u64, name_id);
}

pub fn asyncIsSuspending(map: *hash_mod.U64ToU32Map, module_id: u32, name_id: u32) bool {
    var v = hash_mod.u64ToU32MapGet(map, asyncKey(module_id, name_id));
    if (v) |val| return val != @intCast(u32, 0);
    return false;
}

pub fn asyncFrameSizeOf(map: *hash_mod.U64ToU32Map, module_id: u32, name_id: u32) ?u32 {
    return hash_mod.u64ToU32MapGet(map, asyncKey(module_id, name_id));
}

fn allocU32(sand: *alloc_mod.Sand, count: usize) [*]u32 {
    var c = count;
    if (c == @intCast(usize, 0)) c = @intCast(usize, 1);
    var raw = alloc_mod.sandAlloc(sand, @intCast(usize, 4) * c, @intCast(usize, 4)) catch unreachable;
    return @ptrCast([*]u32, raw);
}

// Resolve a `fn_call` callee expression to an absolute (module_id,name_id) key.
// `ident_expr` -> current-module symbol; `field_access` (optionally chained)
// -> module-qualified symbol. Any other/unresolved callee yields no static edge.
pub fn resolveCalleeKey(store: *ast_mod.AstStore, sym_reg: *sym_mod.SymbolRegistry, module_id: u32, callee_idx: u32) ?u64 {
    var cn = ast_mod.astStoreNodeAt(store, callee_idx);
    if (cn.kind == AstKind.ident_expr) {
        var nid = ast_mod.astStoreIdentifier(store, callee_idx);
        if (sym_mod.symbolRegistryQualifiedLookup(sym_reg, module_id, nid)) |s| {
            if (s.kind == sym_mod.SymbolKind.function) {
                return asyncKey(s.module_id, s.name_id);
            }
        }
        return null;
    }
    if (cn.kind != AstKind.field_access) return null;
    var names: [16]u32 = undefined;
    var nlen: u32 = 0;
    names[@intCast(usize, nlen)] = ast_mod.astStoreNodePayload(store, callee_idx);
    nlen += 1;
    var cur: u32 = cn.child_0;
    var cw = ast_mod.astStoreNodeAt(store, cur);
    while (cw.kind == AstKind.field_access) {
        if (nlen >= @intCast(u32, 16)) return null;
        names[@intCast(usize, nlen)] = ast_mod.astStoreNodePayload(store, cur);
        nlen += 1;
        cur = cw.child_0;
        cw = ast_mod.astStoreNodeAt(store, cur);
    }
    if (cw.kind != AstKind.ident_expr) return null;
    var base_nid = ast_mod.astStoreIdentifier(store, cur);
    var cur_mod: u32 = module_id;
    if (sym_mod.symbolRegistryQualifiedLookup(sym_reg, module_id, base_nid)) |bs| {
        if (bs.kind != sym_mod.SymbolKind.module) return null;
        cur_mod = bs.module_id;
    } else {
        return null;
    }
    var i: u32 = nlen;
    while (i > @intCast(u32, 1)) {
        i -= 1;
        if (sym_mod.symbolRegistryQualifiedLookup(sym_reg, cur_mod, names[@intCast(usize, i)])) |ms| {
            if (ms.kind != sym_mod.SymbolKind.module) return null;
            cur_mod = ms.module_id;
        } else {
            return null;
        }
    }
    if (sym_mod.symbolRegistryQualifiedLookup(sym_reg, cur_mod, names[0])) |fs| {
        if (fs.kind == sym_mod.SymbolKind.function) {
            return asyncKey(fs.module_id, fs.name_id);
        }
    }
    return null;
}

// Walk one function body (iterative stack; builtin_call child_0 is a name id,
// so it is never pushed as a node) collecting direct edges + direct-suspend.
fn scanFunction(store: *ast_mod.AstStore, sym_reg: *sym_mod.SymbolRegistry, module_id: u32,
    caller_idx: u32, body_idx: u32, stack: *ga_mod.U32ArrayList,
    edge_caller: *ga_mod.U32ArrayList, edge_callee: *ga_mod.U32ArrayList,
    direct: *ga_mod.U8ArrayList, fn_index: *hash_mod.U64ToU32Map, async_suspend_name_id: u32) void {
    stack.len = @intCast(usize, 0);
    if (body_idx == @intCast(u32, 0)) return;
    ga_mod.u32ArrayListAppend(stack, body_idx);
    while (stack.len > @intCast(usize, 0)) {
        var ni = stack.items[stack.len - 1];
        stack.len -= @intCast(usize, 1);
        var n = ast_mod.astStoreNodeAt(store, ni);
        var k = n.kind;
        if (k == AstKind.fn_call) {
            if (n.child_0 != @intCast(u32, 0)) {
                if (resolveCalleeKey(store, sym_reg, module_id, n.child_0)) |ck| {
                    if (hash_mod.u64ToU32MapGet(fn_index, ck)) |gi| {
                        ga_mod.u32ArrayListAppend(edge_caller, caller_idx);
                        ga_mod.u32ArrayListAppend(edge_callee, gi);
                    }
                }
                ga_mod.u32ArrayListAppend(stack, n.child_0);
            }
            var ec = ast_mod.astStoreNodeExtraChildren(store, ni);
            var ei: usize = @intCast(usize, 0);
            while (ei < ec.len) : (ei += 1) { ga_mod.u32ArrayListAppend(stack, ec[ei]); }
            continue;
        }
        if (k == AstKind.builtin_call) {
            if (n.child_0 == async_suspend_name_id) {
                direct.items[@intCast(usize, caller_idx)] = @intCast(u8, 1);
            }
            var ec2 = ast_mod.astStoreNodeExtraChildren(store, ni);
            var ei2: usize = @intCast(usize, 0);
            while (ei2 < ec2.len) : (ei2 += 1) { ga_mod.u32ArrayListAppend(stack, ec2[ei2]); }
            continue;
        }
        if (n.child_0 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(k, @intCast(u8, 0))) { ga_mod.u32ArrayListAppend(stack, n.child_0); }
        if (n.child_1 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(k, @intCast(u8, 1))) { ga_mod.u32ArrayListAppend(stack, n.child_1); }
        if (n.child_2 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(k, @intCast(u8, 2))) { ga_mod.u32ArrayListAppend(stack, n.child_2); }
        if (ast_mod.nodeHasNodeExtraChildren(k)) {
            var ec3 = ast_mod.astStoreNodeExtraChildren(store, ni);
            var ei3: usize = @intCast(usize, 0);
            while (ei3 < ec3.len) : (ei3 += 1) { ga_mod.u32ArrayListAppend(stack, ec3[ei3]); }
        }
    }
}

fn emitSuspMarker(key: u64) void {
    var module_id: u32 = @intCast(u32, key >> @intCast(u64, 32));
    var name_id: u32 = @intCast(u32, key & @intCast(u64, 0xFFFFFFFF));
    var m1: []const u8 = "SUSP:m"; pal.markerWrite(m1);
    var b1: [12]u8 = undefined;
    var l1 = itoa_mod.itoa(module_id, b1[0..]);
    var s1: usize = @intCast(usize, 11) - @intCast(usize, @intCast(usize, l1));
    pal.markerWrite(b1[s1..@intCast(usize, 11)]);
    var m2: []const u8 = ":n"; pal.markerWrite(m2);
    var b2: [12]u8 = undefined;
    var l2 = itoa_mod.itoa(name_id, b2[0..]);
    var s2: usize = @intCast(usize, 11) - @intCast(usize, @intCast(usize, l2));
    pal.markerWrite(b2[s2..@intCast(usize, 11)]);
    var m3: []const u8 = "\n"; pal.markerWrite(m3);
}

pub fn suspensionAnalysisRun(alloc: *alloc_mod.Sand, store: *ast_mod.AstStore,
    sym_reg: *sym_mod.SymbolRegistry, module_reg: *mr_mod.ModuleRegistry,
    interner: *si_mod.StringInterner, suspending_fns: *hash_mod.U64ToU32Map) void {
    var p_msg: []const u8 = "YA\n"; pal.markerWrite(p_msg);

    var asu_text: []const u8 = "@asyncSuspend";
    var async_suspend_name_id = si_mod.stringInternerIntern(interner, asu_text);

    var fn_index = hash_mod.u64ToU32MapInit(alloc);
    var fn_keys = ga_mod.u64ArrayListInit(alloc, @intCast(usize, 256));
    var direct = ga_mod.byteArrayListInit(alloc);
    var edge_caller = ga_mod.u32ArrayListInit(alloc);
    var edge_callee = ga_mod.u32ArrayListInit(alloc);

    var mods = mr_mod.moduleRegistryGetModules(module_reg);

    // Pass 1: register every top-level fn_decl as a dense function index.
    var mi: usize = @intCast(usize, 0);
    while (mi < mods.len) : (mi += 1) {
        var ast_root = mods[mi].ast_root;
        if (ast_root == @intCast(u32, 0)) continue;
        var root = ast_mod.astStoreNodeAt(store, ast_root);
        if (root.kind != AstKind.module_root) continue;
        var decls = ast_mod.astStoreNodeExtraChildren(store, ast_root);
        var di: usize = @intCast(usize, 0);
        while (di < decls.len) : (di += 1) {
            var decl = ast_mod.astStoreNodeAt(store, decls[di]);
            if (decl.kind != AstKind.fn_decl) continue;
            var proto_idx = ast_mod.astStoreNodePayload(store, decls[di]);
            var proto = store.fn_protos.items[@intCast(usize, proto_idx)];
            var key = asyncKey(mods[mi].id, proto.name_id);
            if (hash_mod.u64ToU32MapGet(&fn_index, key) == null) {
                hash_mod.u64ToU32MapPut(&fn_index, key, @intCast(u32, fn_keys.len));
                ga_mod.u64ArrayListAppend(&fn_keys, key);
                ga_mod.byteArrayListAppend(&direct, @intCast(u8, 0));
            }
        }
    }

    // Pass 2: collect direct edges and direct-@asyncSuspend seeds.
    var stack = ga_mod.u32ArrayListInit(alloc);
    mi = @intCast(usize, 0);
    while (mi < mods.len) : (mi += 1) {
        var ast_root2 = mods[mi].ast_root;
        if (ast_root2 == @intCast(u32, 0)) continue;
        var root2 = ast_mod.astStoreNodeAt(store, ast_root2);
        if (root2.kind != AstKind.module_root) continue;
        var decls2 = ast_mod.astStoreNodeExtraChildren(store, ast_root2);
        var di2: usize = @intCast(usize, 0);
        while (di2 < decls2.len) : (di2 += 1) {
            var decl2 = ast_mod.astStoreNodeAt(store, decls2[di2]);
            if (decl2.kind != AstKind.fn_decl) continue;
            var proto_idx2 = ast_mod.astStoreNodePayload(store, decls2[di2]);
            var proto2 = store.fn_protos.items[@intCast(usize, proto_idx2)];
            var key2 = asyncKey(mods[mi].id, proto2.name_id);
            var cidx = hash_mod.u64ToU32MapGet(&fn_index, key2);
            if (cidx) |ci0| {
                scanFunction(store, sym_reg, mods[mi].id, ci0, decl2.child_0, &stack,
                    &edge_caller, &edge_callee, &direct, &fn_index, async_suspend_name_id);
            }
        }
    }

    // Monotone worklist over the CSR reverse index (callers of a suspending g).
    var n: usize = fn_keys.len;
    if (n > @intCast(usize, 0)) {
        var rev_count = allocU32(alloc, n);
        var i: usize = @intCast(usize, 0);
        while (i < n) : (i += 1) { rev_count[i] = @intCast(u32, 0); }
        var e: usize = @intCast(usize, 0);
        while (e < edge_callee.len) : (e += 1) {
            var g = edge_callee.items[e];
            rev_count[@intCast(usize, g)] += @intCast(u32, 1);
        }
        var rev_off = allocU32(alloc, n + @intCast(usize, 1));
        var acc: u32 = @intCast(u32, 0);
        i = @intCast(usize, 0);
        while (i < n) : (i += 1) {
            rev_off[i] = acc;
            acc += rev_count[i];
        }
        rev_off[n] = acc;
        var rev_pos = allocU32(alloc, n);
        i = @intCast(usize, 0);
        while (i < n) : (i += 1) { rev_pos[i] = rev_off[i]; }
        var rev_to = allocU32(alloc, edge_callee.len);
        e = @intCast(usize, 0);
        while (e < edge_callee.len) : (e += 1) {
            var g2 = edge_callee.items[e];
            var p = rev_pos[@intCast(usize, g2)];
            rev_to[@intCast(usize, p)] = edge_caller.items[e];
            rev_pos[@intCast(usize, g2)] = p + @intCast(u32, 1);
        }
        var queue = allocU32(alloc, n);
        var head: usize = @intCast(usize, 0);
        var tail: usize = @intCast(usize, 0);
        i = @intCast(usize, 0);
        while (i < n) : (i += 1) {
            if (direct.items[i] != @intCast(u8, 0)) {
                hash_mod.u64ToU32MapPut(suspending_fns, fn_keys.items[i], @intCast(u32, 1));
                queue[tail] = @intCast(u32, i);
                tail += @intCast(usize, 1);
            }
        }
        while (head < tail) {
            var g3 = queue[head];
            head += @intCast(usize, 1);
            var k0 = rev_off[@intCast(usize, g3)];
            var k1 = rev_off[@intCast(usize, g3) + @intCast(usize, 1)];
            var kk: u32 = k0;
            while (kk < k1) : (kk += @intCast(u32, 1)) {
                var c = rev_to[@intCast(usize, kk)];
                var ckey = fn_keys.items[@intCast(usize, c)];
                if (hash_mod.u64ToU32MapGet(suspending_fns, ckey) == null) {
                    hash_mod.u64ToU32MapPut(suspending_fns, ckey, @intCast(u32, 1));
                    queue[tail] = c;
                    tail += @intCast(usize, 1);
                }
            }
        }
    }

    // Marker per suspending function: "SUSP:m<module_id>:n<name_id>\n".
    var m: usize = @intCast(usize, 0);
    while (m < fn_keys.len) : (m += 1) {
        var kk2 = fn_keys.items[m];
        var vv = hash_mod.u64ToU32MapGet(suspending_fns, kk2);
        if (vv) |val2| {
            if (val2 != @intCast(u32, 0)) {
                emitSuspMarker(kk2);
            }
        }
    }
}

// Fix F4 #4: ONE shared, backend-agnostic frame-layout/offset rule. P2
// (`asyncFrameSizeRun`), P3 (`asyncLayoutFrame`), and the `@asyncInit` lowering
// all accumulate the frozen layout (step@0, ctx@4, state@8, params, live, hidden
// tail) through `frameFieldSizeAlign` + `addFrameField`/`alignUpU32` below, so
// the three sites cannot drift. The result is byte-identical to the previous
// per-site arithmetic.
pub fn alignUpU32(v: u32, a: u32) u32 {
    return (v + a - @intCast(u32, 1)) & ~(a - @intCast(u32, 1));
}

// Natural size/alignment of a frame field type. A zero-size or unknown type
// falls back to 4/4 (conservative pointer-sized upper bound); a zero alignment
// keeps the default 4.
pub fn frameFieldSizeAlign(reg: *type_mod.TypeRegistry, tid: u32, out_size: *u32, out_align: *u32) void {
    var sz: u32 = @intCast(u32, 4);
    var al: u32 = @intCast(u32, 4);
    if (@intCast(usize, tid) < reg.types_len) {
        var t = reg.types_items[@intCast(usize, tid)];
        if (t.size != @intCast(u32, 0)) {
            sz = t.size;
            if (t.alignment != @intCast(u32, 0)) { al = t.alignment; }
        }
    }
    out_size.* = sz;
    out_align.* = al;
}

// Align `offset` to the field's alignment, return the field's offset, advance
// `offset` by its size, and fold its alignment into `max_align`.
pub fn addFrameField(reg: *type_mod.TypeRegistry, tid: u32, offset: *u32, max_align: *u32) u32 {
    var sz: u32 = @intCast(u32, 4);
    var al: u32 = @intCast(u32, 4);
    frameFieldSizeAlign(reg, tid, &sz, &al);
    offset.* = alignUpU32(offset.*, al);
    var at = offset.*;
    offset.* += sz;
    if (al > max_align.*) { max_align.* = al; }
    return at;
}

// True when `tid` is a `*void` pointer type (shared by P3 and the Stage-3
// transform; the explicit-suspend LIR marker test).
pub fn typeIsPtrVoid(reg: *type_mod.TypeRegistry, tid: u32) bool {
    if (@intCast(usize, tid) >= reg.types_len) return false;
    var t = reg.types_items[@intCast(usize, tid)];
    if (t.kind != type_mod.TypeKind.ptr_type) return false;
    var base = reg.ptr_items[@intCast(usize, t.payload_idx)].base;
    return base == type_mod.TYPE_VOID;
}

fn frameLocalTypeId(resolved_types: *rtt_mod.ResolvedTypeTable, n: ast_mod.AstNode) u32 {
    if (n.child_0 != @intCast(u32, 0)) {
        if (rtt_mod.resolvedTypeTableGet(resolved_types, n.child_0)) |t| return t;
    } else if (n.child_1 != @intCast(u32, 0)) {
        if (rtt_mod.resolvedTypeTableGet(resolved_types, n.child_1)) |t| return t;
    }
    return type_mod.TYPE_UNDEFINED;
}

// Conservative rule (a), widened (Fix F1): reserve a frame field for EVERY AST
// node reachable in the function body — not just `var_decl` — so the
// authoritative size upper-bounds the temps P3 finds live across a suspension.
// The walk no longer stops at the first suspension: a value defined after one
// suspension and read after a later one must be reserved too. Type selection
// prefers the node's own resolved type (the value's final, post-coercion type
// as lowering sees it), falling back to the declaration's type node for
// `var_decl`. Over-reservation is intentional; P3's `precise <= frame_sizes[key]`
// assert stays the guard.
fn scanFrameLocals(store: *ast_mod.AstStore, body_idx: u32,
    stack: *ga_mod.U32ArrayList, reg: *type_mod.TypeRegistry,
    resolved_types: *rtt_mod.ResolvedTypeTable, offset: *u32, max_align: *u32) void {
    stack.len = @intCast(usize, 0);
    if (body_idx == @intCast(u32, 0)) return;
    ga_mod.u32ArrayListAppend(stack, body_idx);
    while (stack.len > @intCast(usize, 0)) {
        var ni = stack.items[stack.len - @intCast(usize, 1)];
        stack.len -= @intCast(usize, 1);
        var n = ast_mod.astStoreNodeAt(store, ni);
        var k = n.kind;
        var lvt: u32 = type_mod.TYPE_UNDEFINED;
        if (rtt_mod.resolvedTypeTableGet(resolved_types, ni)) |t| { lvt = t; }
        if (lvt == type_mod.TYPE_UNDEFINED and k == AstKind.var_decl) { lvt = frameLocalTypeId(resolved_types, n); }
        _ = addFrameField(reg, lvt, offset, max_align);
        if (k == AstKind.builtin_call) {
            var ecb = ast_mod.astStoreNodeExtraChildren(store, ni);
            var bi: usize = ecb.len;
            while (bi > @intCast(usize, 0)) {
                bi -= @intCast(usize, 1);
                ga_mod.u32ArrayListAppend(stack, ecb[bi]);
            }
            continue;
        }
        if (k == AstKind.fn_call) {
            var ecf = ast_mod.astStoreNodeExtraChildren(store, ni);
            var fi: usize = ecf.len;
            while (fi > @intCast(usize, 0)) {
                fi -= @intCast(usize, 1);
                ga_mod.u32ArrayListAppend(stack, ecf[fi]);
            }
            if (n.child_0 != @intCast(u32, 0)) { ga_mod.u32ArrayListAppend(stack, n.child_0); }
            continue;
        }
        if (ast_mod.nodeHasNodeExtraChildren(k)) {
            var ec3 = ast_mod.astStoreNodeExtraChildren(store, ni);
            var ei3: usize = ec3.len;
            while (ei3 > @intCast(usize, 0)) {
                ei3 -= @intCast(usize, 1);
                ga_mod.u32ArrayListAppend(stack, ec3[ei3]);
            }
        }
        if (n.child_2 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(k, @intCast(u8, 2))) { ga_mod.u32ArrayListAppend(stack, n.child_2); }
        if (n.child_1 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(k, @intCast(u8, 1))) { ga_mod.u32ArrayListAppend(stack, n.child_1); }
        if (n.child_0 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(k, @intCast(u8, 0))) { ga_mod.u32ArrayListAppend(stack, n.child_0); }
    }
}

// Full AST walk (no early stop) collecting implicit-await edges for the P2/P3
// hidden-field reservation: marks the callee awaited, the caller as having a
// child, and — for value-returning callees — the caller as needing a
// parent-result slot plus that value type.
fn scanImplicitAwaits(store: *ast_mod.AstStore, sym_reg: *sym_mod.SymbolRegistry,
    module_id: u32, caller_key: u64, body_idx: u32, stack: *ga_mod.U32ArrayList,
    suspending_fns: *hash_mod.U64ToU32Map, fn_ret_types: *hash_mod.U64ToU32Map,
    awaited_fns: *hash_mod.U64ToU32Map, hidden_fns: *hash_mod.U64ToU32Map,
    parent_type_list: *ga_mod.U32ArrayList, parent_start: *hash_mod.U64ToU32Map,
    parent_count: *hash_mod.U64ToU32Map) void {
    stack.len = @intCast(usize, 0);
    if (body_idx == @intCast(u32, 0)) return;
    ga_mod.u32ArrayListAppend(stack, body_idx);
    while (stack.len > @intCast(usize, 0)) {
        var ni = stack.items[stack.len - @intCast(usize, 1)];
        stack.len -= @intCast(usize, 1);
        var n = ast_mod.astStoreNodeAt(store, ni);
        var k = n.kind;
        if (k == AstKind.fn_call) {
            if (n.child_0 != @intCast(u32, 0)) {
                if (resolveCalleeKey(store, sym_reg, module_id, n.child_0)) |ck| {
                    var cmid = @intCast(u32, ck >> @intCast(u64, 32));
                    var cnid = @intCast(u32, ck & @intCast(u64, 0xFFFFFFFF));
                    if (asyncIsSuspending(suspending_fns, cmid, cnid)) {
                        _ = hash_mod.u64ToU32MapPut(awaited_fns, ck, @intCast(u32, 1));
                        var hf: u32 = @intCast(u32, 1);
                        if (hash_mod.u64ToU32MapGet(hidden_fns, caller_key)) |old| { hf = old | @intCast(u32, 1); }
                        var rt: u32 = type_mod.TYPE_VOID;
                        if (hash_mod.u64ToU32MapGet(fn_ret_types, ck)) |r| { rt = r; }
                        if (rt != type_mod.TYPE_VOID) {
                            hf = hf | @intCast(u32, 2);
                            var pc: u32 = @intCast(u32, 0);
                            if (hash_mod.u64ToU32MapGet(parent_count, caller_key)) |oldc| { pc = oldc; }
                            if (pc == @intCast(u32, 0)) {
                                _ = hash_mod.u64ToU32MapPut(parent_start, caller_key, @intCast(u32, parent_type_list.len));
                            }
                            ga_mod.u32ArrayListAppend(parent_type_list, rt);
                            _ = hash_mod.u64ToU32MapPut(parent_count, caller_key, pc + @intCast(u32, 1));
                        }
                        _ = hash_mod.u64ToU32MapPut(hidden_fns, caller_key, hf);
                    }
                }
                ga_mod.u32ArrayListAppend(stack, n.child_0);
            }
            var ec = ast_mod.astStoreNodeExtraChildren(store, ni);
            var ei: usize = @intCast(usize, 0);
            while (ei < ec.len) : (ei += 1) { ga_mod.u32ArrayListAppend(stack, ec[ei]); }
            continue;
        }
        if (k == AstKind.builtin_call) {
            var ec2 = ast_mod.astStoreNodeExtraChildren(store, ni);
            var ei2: usize = @intCast(usize, 0);
            while (ei2 < ec2.len) : (ei2 += 1) { ga_mod.u32ArrayListAppend(stack, ec2[ei2]); }
            continue;
        }
        if (n.child_0 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(k, @intCast(u8, 0))) { ga_mod.u32ArrayListAppend(stack, n.child_0); }
        if (n.child_1 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(k, @intCast(u8, 1))) { ga_mod.u32ArrayListAppend(stack, n.child_1); }
        if (n.child_2 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(k, @intCast(u8, 2))) { ga_mod.u32ArrayListAppend(stack, n.child_2); }
        if (ast_mod.nodeHasNodeExtraChildren(k)) {
            var ec3 = ast_mod.astStoreNodeExtraChildren(store, ni);
            var ei3: usize = @intCast(usize, 0);
            while (ei3 < ec3.len) : (ei3 += 1) { ga_mod.u32ArrayListAppend(stack, ec3[ei3]); }
        }
    }
    // Ordering invariant (Task 6D5): the LIFO walk above visits siblings in
    // reverse source order and inner call args before their outer call (matching
    // lowering's evaluation order). Reverse this caller's freshly-appended
    // segment to recover program order so P2's slot order equals P4's await
    // order; P3 mirrors P2 exactly.
    if (hash_mod.u64ToU32MapGet(parent_count, caller_key)) |pc| {
        if (pc > @intCast(u32, 1)) {
            if (hash_mod.u64ToU32MapGet(parent_start, caller_key)) |ps| {
                var lo: usize = @intCast(usize, ps);
                var hi: usize = parent_type_list.len;
                while (lo + @intCast(usize, 1) < hi) {
                    var tmp = parent_type_list.items[lo];
                    parent_type_list.items[lo] = parent_type_list.items[hi - @intCast(usize, 1)];
                    parent_type_list.items[hi - @intCast(usize, 1)] = tmp;
                    lo += @intCast(usize, 1);
                    hi -= @intCast(usize, 1);
                }
            }
        }
    }
}

// Authoritative state-width rule (spec §3.2 item 3): u8 for <=255 suspension
// points, u16 for <=65535, else u32. `asyncFrameSizeRun` computes the count and
// stores the chosen type in `state_widths`; every consumer reads that map.
fn asyncStateTypeForCount(count: u32) u32 {
    if (count <= @intCast(u32, 255)) return type_mod.TYPE_U8;
    if (count <= @intCast(u32, 65535)) return type_mod.TYPE_U16;
    return type_mod.TYPE_U32;
}

// Count the suspension points used to choose the `state` width: every explicit
// `@asyncSuspend` (and the `@asyncInit` placeholder, which shares the
// `int_const 0` -> `*void` LIR shape) plus every implicit-await call to a
// suspending callee. This is the single source of truth for the width rule; it
// is a conservative upper bound on the Stage-3 LIR suspension-point count, so
// the chosen width can never be too small (no silent truncation).
fn scanSuspensionCount(store: *ast_mod.AstStore, sym_reg: *sym_mod.SymbolRegistry,
    module_id: u32, body_idx: u32, stack: *ga_mod.U32ArrayList,
    suspending_fns: *hash_mod.U64ToU32Map, async_suspend_name_id: u32,
    async_init_name_id: u32) u32 {
    var count: u32 = @intCast(u32, 0);
    stack.len = @intCast(usize, 0);
    if (body_idx == @intCast(u32, 0)) return count;
    ga_mod.u32ArrayListAppend(stack, body_idx);
    while (stack.len > @intCast(usize, 0)) {
        var ni = stack.items[stack.len - @intCast(usize, 1)];
        stack.len -= @intCast(usize, 1);
        var n = ast_mod.astStoreNodeAt(store, ni);
        var k = n.kind;
        if (k == AstKind.builtin_call) {
            if (n.child_0 == async_suspend_name_id or n.child_0 == async_init_name_id) {
                count += @intCast(u32, 1);
            }
            var ecb = ast_mod.astStoreNodeExtraChildren(store, ni);
            var bi: usize = @intCast(usize, 0);
            while (bi < ecb.len) : (bi += 1) { ga_mod.u32ArrayListAppend(stack, ecb[bi]); }
            continue;
        }
        if (k == AstKind.fn_call) {
            if (n.child_0 != @intCast(u32, 0)) {
                if (resolveCalleeKey(store, sym_reg, module_id, n.child_0)) |ck| {
                    var cmid = @intCast(u32, ck >> @intCast(u64, 32));
                    var cnid = @intCast(u32, ck & @intCast(u64, 0xFFFFFFFF));
                    if (asyncIsSuspending(suspending_fns, cmid, cnid)) {
                        count += @intCast(u32, 1);
                    }
                }
                ga_mod.u32ArrayListAppend(stack, n.child_0);
            }
            var ecf = ast_mod.astStoreNodeExtraChildren(store, ni);
            var fi: usize = @intCast(usize, 0);
            while (fi < ecf.len) : (fi += 1) { ga_mod.u32ArrayListAppend(stack, ecf[fi]); }
            continue;
        }
        if (n.child_0 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(k, @intCast(u8, 0))) { ga_mod.u32ArrayListAppend(stack, n.child_0); }
        if (n.child_1 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(k, @intCast(u8, 1))) { ga_mod.u32ArrayListAppend(stack, n.child_1); }
        if (n.child_2 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(k, @intCast(u8, 2))) { ga_mod.u32ArrayListAppend(stack, n.child_2); }
        if (ast_mod.nodeHasNodeExtraChildren(k)) {
            var ec3 = ast_mod.astStoreNodeExtraChildren(store, ni);
            var ei3: usize = @intCast(usize, 0);
            while (ei3 < ec3.len) : (ei3 += 1) { ga_mod.u32ArrayListAppend(stack, ec3[ei3]); }
        }
    }
    return count;
}

fn asyncPtrVoid(reg: *type_mod.TypeRegistry) u32 {
    return type_mod.typeRegistryGetOrCreatePtr(reg, type_mod.TYPE_VOID, false);
}

fn emitFrameMarker(key: u64, size: u32) void {
    var module_id: u32 = @intCast(u32, key >> @intCast(u64, 32));
    var name_id: u32 = @intCast(u32, key & @intCast(u64, 0xFFFFFFFF));
    var m1: []const u8 = "FRAME:m"; pal.markerWrite(m1);
    var b1: [12]u8 = undefined;
    var l1 = itoa_mod.itoa(module_id, b1[0..]);
    var s1: usize = @intCast(usize, 11) - @intCast(usize, @intCast(usize, l1));
    pal.markerWrite(b1[s1..@intCast(usize, 11)]);
    var m2: []const u8 = ":n"; pal.markerWrite(m2);
    var b2: [12]u8 = undefined;
    var l2 = itoa_mod.itoa(name_id, b2[0..]);
    var s2: usize = @intCast(usize, 11) - @intCast(usize, @intCast(usize, l2));
    pal.markerWrite(b2[s2..@intCast(usize, 11)]);
    var m3: []const u8 = ":s"; pal.markerWrite(m3);
    var b3: [12]u8 = undefined;
    var l3 = itoa_mod.itoa(size, b3[0..]);
    var s3: usize = @intCast(usize, 11) - @intCast(usize, @intCast(usize, l3));
    pal.markerWrite(b3[s3..@intCast(usize, 11)]);
    var m4: []const u8 = "\n"; pal.markerWrite(m4);
}

pub fn asyncFrameSizeRun(alloc: *alloc_mod.Sand, store: *ast_mod.AstStore,
    sym_reg: *sym_mod.SymbolRegistry, interner: *si_mod.StringInterner,
    module_reg: *mr_mod.ModuleRegistry,
    typereg: *type_mod.TypeRegistry,
    resolved_types: *rtt_mod.ResolvedTypeTable,
    suspending_fns: *hash_mod.U64ToU32Map, frame_sizes: *hash_mod.U64ToU32Map,
    state_widths: *hash_mod.U64ToU32Map,
    awaited_fns: *hash_mod.U64ToU32Map, async_hidden_fns: *hash_mod.U64ToU32Map,
    driver_targets: *hash_mod.U64ToU32Map,
    parent_result_type_list: *ga_mod.U32ArrayList, parent_result_start: *hash_mod.U64ToU32Map,
    parent_result_count: *hash_mod.U64ToU32Map) void {
    var p_msg: []const u8 = "AFS\n"; pal.markerWrite(p_msg);
    var stack = ga_mod.u32ArrayListInit(alloc);
    var mods = mr_mod.moduleRegistryGetModules(module_reg);
    var asu_text: []const u8 = "@asyncSuspend";
    var async_suspend_name_id = si_mod.stringInternerIntern(interner, asu_text);
    var ain_text: []const u8 = "@asyncInit";
    var async_init_name_id = si_mod.stringInternerIntern(interner, ain_text);

    // Pass 0: resolve every top-level function's return type (asyncKey -> tid),
    // needed to type the caller-side hidden parent_result slot.
    var fn_ret_types = hash_mod.u64ToU32MapInit(alloc);
    var mi0: usize = @intCast(usize, 0);
    while (mi0 < mods.len) : (mi0 += 1) {
        var ar0 = mods[mi0].ast_root;
        if (ar0 == @intCast(u32, 0)) continue;
        var r0 = ast_mod.astStoreNodeAt(store, ar0);
        if (r0.kind != AstKind.module_root) continue;
        var d0 = ast_mod.astStoreNodeExtraChildren(store, ar0);
        var di0: usize = @intCast(usize, 0);
        while (di0 < d0.len) : (di0 += 1) {
            var dc0 = ast_mod.astStoreNodeAt(store, d0[di0]);
            if (dc0.kind != AstKind.fn_decl) continue;
            var pr0 = store.fn_protos.items[@intCast(usize, ast_mod.astStoreNodePayload(store, d0[di0]))];
            var rt0: u32 = type_mod.TYPE_VOID;
            if (rtt_mod.resolvedTypeTableGet(resolved_types, pr0.return_type_node)) |rr0| { rt0 = rr0; }
            _ = hash_mod.u64ToU32MapPut(&fn_ret_types, asyncKey(mods[mi0].id, pr0.name_id), rt0);
        }
    }

    // Pass 0b: scan every suspending function's body for implicit awaits and
    // populate the awaited set + caller hidden-field predicates.
    var mi0b: usize = @intCast(usize, 0);
    while (mi0b < mods.len) : (mi0b += 1) {
        var ar0b = mods[mi0b].ast_root;
        if (ar0b == @intCast(u32, 0)) continue;
        var r0b = ast_mod.astStoreNodeAt(store, ar0b);
        if (r0b.kind != AstKind.module_root) continue;
        var d0b = ast_mod.astStoreNodeExtraChildren(store, ar0b);
        var di0b: usize = @intCast(usize, 0);
        while (di0b < d0b.len) : (di0b += 1) {
            var dc0b = ast_mod.astStoreNodeAt(store, d0b[di0b]);
            if (dc0b.kind != AstKind.fn_decl) continue;
            var pr0b = store.fn_protos.items[@intCast(usize, ast_mod.astStoreNodePayload(store, d0b[di0b]))];
            if (!asyncIsSuspending(suspending_fns, mods[mi0b].id, pr0b.name_id)) continue;
            scanImplicitAwaits(store, sym_reg, mods[mi0b].id, asyncKey(mods[mi0b].id, pr0b.name_id), dc0b.child_0, &stack,
                suspending_fns, &fn_ret_types, awaited_fns, async_hidden_fns, parent_result_type_list, parent_result_start, parent_result_count);
        }
    }

    var mi: usize = @intCast(usize, 0);
    while (mi < mods.len) : (mi += 1) {
        var ast_root = mods[mi].ast_root;
        if (ast_root == @intCast(u32, 0)) continue;
        var root = ast_mod.astStoreNodeAt(store, ast_root);
        if (root.kind != AstKind.module_root) continue;
        var decls = ast_mod.astStoreNodeExtraChildren(store, ast_root);
        var di: usize = @intCast(usize, 0);
        while (di < decls.len) : (di += 1) {
            var decl = ast_mod.astStoreNodeAt(store, decls[di]);
            if (decl.kind != AstKind.fn_decl) continue;
            var proto_idx = ast_mod.astStoreNodePayload(store, decls[di]);
            var proto = store.fn_protos.items[@intCast(usize, proto_idx)];
            if (!asyncIsSuspending(suspending_fns, mods[mi].id, proto.name_id)) continue;
            var key = asyncKey(mods[mi].id, proto.name_id);
            // Task 8-F: root `main` (module 0 + AST pub bit) or any `export fn`
            // (AST bit3) is a synchronous-driver target; it needs the hidden
            // result field so the driver can return the value.
            var is_driver_target: bool = false;
            if ((@intCast(u16, decl.flags) & @intCast(u16, 0x08)) != @intCast(u16, 0)) { is_driver_target = true; }
            if (mods[mi].id == @intCast(u32, 0) and (@intCast(u16, decl.flags) & @intCast(u16, 0x02)) != @intCast(u16, 0)) {
                var dm = si_mod.stringInternerGet(interner, proto.name_id);
                if (dm.len == @intCast(usize, 4) and dm[0] == 'm' and dm[1] == 'a' and dm[2] == 'i' and dm[3] == 'n') { is_driver_target = true; }
            }
            if (is_driver_target) { _ = hash_mod.u64ToU32MapPut(driver_targets, key, @intCast(u32, 1)); }
            // Authoritative state width: one source of truth, read by P3, the
            // `@asyncInit` lowering, and the Stage-3 transform.
            var susp_count = scanSuspensionCount(store, sym_reg, mods[mi].id, decl.child_0, &stack, suspending_fns, async_suspend_name_id, async_init_name_id);
            var state_type = asyncStateTypeForCount(susp_count);
            _ = hash_mod.u64ToU32MapPut(state_widths, key, state_type);
            var offset: u32 = @intCast(u32, 0);
            var max_align: u32 = @intCast(u32, 1);
            // Amendment 7: hidden pointer-sized step word @ offset 0 ALWAYS.
            _ = addFrameField(typereg, type_mod.TYPE_USIZE, &offset, &max_align);
            _ = addFrameField(typereg, type_mod.TYPE_USIZE, &offset, &max_align);
            _ = addFrameField(typereg, state_type, &offset, &max_align);
            if (proto.params_count > @intCast(u16, 0)) {
                var p_payload: u64 = (@intCast(u64, proto.params_start) << @intCast(u64, 32)) | @intCast(u64, proto.params_count);
                var pnodes = ast_mod.astStoreGetExtraChildren(store, p_payload);
                var pi: usize = @intCast(usize, 0);
                while (pi < pnodes.len) : (pi += @intCast(usize, 1)) {
                    var pnode = ast_mod.astStoreNodeAt(store, pnodes[pi]);
                    if (pnode.child_0 == @intCast(u32, 0)) continue;
                    var pt: u32 = type_mod.TYPE_UNDEFINED;
                    if (rtt_mod.resolvedTypeTableGet(resolved_types, pnode.child_0)) |rtp| { pt = rtp; }
                    _ = addFrameField(typereg, pt, &offset, &max_align);
                }
            }
            scanFrameLocals(store, decl.child_0, &stack, typereg, resolved_types, &offset, &max_align);
            // Amendment 9/10 hidden tail fields: child (kind 5), result (kind 6),
            // then one parent_result (kind 7) per value-returning implicit
            // await, in program order.
            var hid: u32 = @intCast(u32, 0);
            if (hash_mod.u64ToU32MapGet(async_hidden_fns, key)) |h| { hid = h; }
            if ((hid & @intCast(u32, 1)) != @intCast(u32, 0)) {
                _ = addFrameField(typereg, asyncPtrVoid(typereg), &offset, &max_align);
            }
            if (hash_mod.u64ToU32MapGet(awaited_fns, key) != null or hash_mod.u64ToU32MapGet(driver_targets, key) != null) {
                _ = addFrameField(typereg, asyncPtrVoid(typereg), &offset, &max_align);
            }
            if ((hid & @intCast(u32, 2)) != @intCast(u32, 0)) {
                var pstart: u32 = @intCast(u32, 0);
                if (hash_mod.u64ToU32MapGet(parent_result_start, key)) |ps| { pstart = ps; }
                var pcount: u32 = @intCast(u32, 0);
                if (hash_mod.u64ToU32MapGet(parent_result_count, key)) |pc| { pcount = pc; }
                var pk: u32 = @intCast(u32, 0);
                while (pk < pcount) : (pk += @intCast(u32, 1)) {
                    var prt = parent_result_type_list.items[@intCast(usize, pstart + pk)];
                    _ = addFrameField(typereg, prt, &offset, &max_align);
                }
            }
            // Rule A (cross-track ABI): pad EVERY frame to 8 so consecutive
            // pool frames stay 8-aligned given an 8-aligned pool base. A frame
            // only aligned to its own `max_align` (often 4) would otherwise
            // start the next frame at a 4-mod-8 offset.
            var total = alignUpU32(offset, max_align);
            if (total == @intCast(u32, 0)) total = @intCast(u32, 1);
            total = alignUpU32(total, @intCast(u32, 8));
            hash_mod.u64ToU32MapPut(frame_sizes, key, total);
            emitFrameMarker(key, total);
        }
    }
}
