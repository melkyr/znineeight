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
// descent. `frame_sizes` is declared alongside but first written in Task 5.
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
const si_mod = @import("string_interner.zig");
const sym_mod = @import("symbol_table.zig");

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
fn resolveCalleeKey(store: *ast_mod.AstStore, sym_reg: *sym_mod.SymbolRegistry, module_id: u32, callee_idx: u32) ?u64 {
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
        if (n.child_0 != @intCast(u32, 0)) { ga_mod.u32ArrayListAppend(stack, n.child_0); }
        if (n.child_1 != @intCast(u32, 0)) { ga_mod.u32ArrayListAppend(stack, n.child_1); }
        if (n.child_2 != @intCast(u32, 0)) { ga_mod.u32ArrayListAppend(stack, n.child_2); }
        if (ast_mod.nodeHasExtraChildren(k)) {
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
