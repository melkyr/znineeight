// KEPT (unwired) — const-alias type resolution prepass. Currently unexercised by the 4 working examples (0 CAP hits per P3 deep-dive), but designed for transitive `const X = TypeName;` chains per Import_Symbol_reg.md.
const alloc_mod = @import("allocator.zig");
const sym_mod = @import("symbol_table.zig");
const Sand = @import("allocator.zig").Sand;

const SymbolRegistry = sym_mod.SymbolRegistry;
const SymbolTable = sym_mod.SymbolTable;
const type_mod = @import("type_registry.zig");
const TypeRegistry = type_mod.TypeRegistry;
const hash_mod = @import("util/hash.zig");
const interner_mod = @import("string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const AstStore = @import("ast.zig").AstStore;
const AstKind = @import("ast.zig").AstKind;
const pal = @import("pal.zig");

fn resolveWellKnownTypeName(name: []const u8) u32 {
    if (name.len == 4) {
        if (name[0] == 'v' and name[1] == 'o' and name[2] == 'i' and name[3] == 'd') return type_mod.TYPE_VOID;
        if (name[0] == 'b' and name[1] == 'o' and name[2] == 'o' and name[3] == 'l') return type_mod.TYPE_BOOL;
    }
    if (name.len == 3) {
        if (name[0] == 'i' and name[2] == '2') { if (name[1] == '3') return type_mod.TYPE_I32; }
        if (name[0] == 'u' and name[2] == '2') { if (name[1] == '3') return type_mod.TYPE_U32; }
        if (name[0] == 'u' and name[1] == '6' and name[2] == '4') return type_mod.TYPE_U64;
        if (name[0] == 'i' and name[1] == '6' and name[2] == '4') return type_mod.TYPE_I64;
        if (name[0] == 'f' and name[2] == '2') {
            if (name[1] == '3') return type_mod.TYPE_F32;
            if (name[1] == '6') return type_mod.TYPE_F64;
        }
    }
    if (name.len == 2) {
        if (name[0] == 'i' and name[1] == '8') return type_mod.TYPE_I8;
        if (name[0] == 'u' and name[1] == '8') return type_mod.TYPE_U8;
    }
    if (name.len == 5) {
        if (name[0] == 'u' and name[1] == 's' and name[2] == 'i' and name[3] == 'z' and name[4] == 'e') return type_mod.TYPE_USIZE;
        if (name[0] == 'i' and name[1] == 's' and name[2] == 'i' and name[3] == 'z' and name[4] == 'e') return type_mod.TYPE_ISIZE;
    }
    return type_mod.TYPE_UNDEFINED;
}

fn growDep(perm: *Sand, to_ptr: *[*]u32, next_ptr: *[*]u32, cap_ptr: *u32) void {
    var nc: u32 = cap_ptr.* * 2;
    if (nc < 16) nc = 16;
    var ntr = alloc_mod.sandAlloc(perm, @intCast(usize, 4) * @intCast(usize, nc), @intCast(usize, 4)) catch unreachable;
    var nto = @ptrCast([*]u32, ntr);
    var nnr = alloc_mod.sandAlloc(perm, @intCast(usize, 4) * @intCast(usize, nc), @intCast(usize, 4)) catch unreachable;
    var nno = @ptrCast([*]u32, nnr);
    var ci: usize = 0;
    while (ci < @intCast(usize, cap_ptr.*)) : (ci += 1) {
        nto[ci] = to_ptr.*[ci];
        nno[ci] = next_ptr.*[ci];
    }
    to_ptr.* = nto;
    next_ptr.* = nno;
    cap_ptr.* = nc;
}

pub fn constAliasPrepass(symbol_reg: *SymbolRegistry, registry: *type_mod.TypeRegistry, interner: *StringInterner, store: *AstStore, perm_alloc: *Sand) void {
    { var cap_m: []const u8 = "CAP:ent\n"; pal.markerWrite(cap_m); }

    var tl: u32 = 0;
    var cti: usize = 0;
    while (cti < symbol_reg.tables_len) : (cti += 1) {
        tl += @intCast(u32, symbol_reg.tables_items[cti].len);
    }
    { var cap_tm: []const u8 = "CAP:tlm"; pal.markerWriteInt(cap_tm, tl); }
    if (tl == 0) { var cap_m: []const u8 = "CAP:tl0\n"; pal.markerWrite(cap_m); return; }

    const SZ_U32: usize = 4;
    const U32_MAX: u32 = 4294967295;

    var dep_cap: u32 = tl;
    var dep_to_raw = alloc_mod.sandAlloc(perm_alloc, SZ_U32 * @intCast(usize, tl), SZ_U32) catch unreachable;
    var dep_to = @ptrCast([*]u32, dep_to_raw);
    var dep_next_raw = alloc_mod.sandAlloc(perm_alloc, SZ_U32 * @intCast(usize, tl), SZ_U32) catch unreachable;
    var dep_next = @ptrCast([*]u32, dep_next_raw);

    var head_cap: usize = interner.entries_len;
    if (head_cap < @intCast(usize, tl)) head_cap = @intCast(usize, tl);
    var dep_head_raw = alloc_mod.sandAlloc(perm_alloc, SZ_U32 * head_cap, SZ_U32) catch unreachable;
    var dep_head = @ptrCast([*]u32, dep_head_raw);

    var si0: usize = 0;
    while (si0 < head_cap) : (si0 += 1) { dep_head[si0] = U32_MAX; }

    var dep_count: u32 = 0;

    var wl_raw = alloc_mod.sandAlloc(perm_alloc, SZ_U32 * @intCast(usize, tl), SZ_U32) catch unreachable;
    var wl = @ptrCast([*]u32, wl_raw);
    var wl_len: u32 = 0;

    var alias_name_raw = alloc_mod.sandAlloc(perm_alloc, SZ_U32 * @intCast(usize, tl), SZ_U32) catch unreachable;
    var alias_name = @ptrCast([*]u32, alias_name_raw);
    var alias_sym_raw = alloc_mod.sandAlloc(perm_alloc, SZ_U32 * @intCast(usize, tl) * 2, SZ_U32) catch unreachable;
    var alias_sym_id = @ptrCast([*]u32, alias_sym_raw);

    var alias_count: u32 = 0;

    // Phase 1: Catalog
    {
        var mi: usize = 0;
        while (mi < symbol_reg.tables_len) : (mi += 1) {
            var table = symbol_reg.tables_items[mi];
            var si: usize = 0;
            while (si < table.len) : (si += 1) {
                var sym = &table.items[si];
                if (@enumToInt(sym.kind) != @enumToInt(sym_mod.SymbolKind.global)) continue;
                { var g0_m: []const u8 = "GATE:g0"; pal.markerWriteInt(g0_m, sym.type_id); }
                if (sym.type_id != 0) continue;
                { var g1_m: []const u8 = "GATE:g1\n"; pal.markerWrite(g1_m); }
                var decl_node = store.nodes.items[@intCast(usize, sym.decl_node)];
                if (@enumToInt(decl_node.kind) != 1) {
                    { var g2_m: []const u8 = "GATE:g2"; pal.markerWriteInt(g2_m, @intCast(u32, @enumToInt(decl_node.kind))); }
                    continue;
                }
                if (decl_node.child_1 == 0) {
                    { var g3_m: []const u8 = "GATE:g3\n"; pal.markerWrite(g3_m); }
                    continue;
                }
                var init = store.nodes.items[@intCast(usize, decl_node.child_1)];
                {
                    var c1_m: []const u8 = "CAT:ik"; pal.markerWriteInt(c1_m, @intCast(u32, @enumToInt(init.kind)));
                }
                if (@enumToInt(init.kind) != 24) continue;

                var dep_name = store.identifiers.items[@intCast(usize, init.payload)];
                {
                    var c2_m: []const u8 = "CAT:dn"; pal.markerWriteInt(c2_m, dep_name);
                }
                var dep_text = interner_mod.stringInternerGet(interner, dep_name);
                var dep_canonical = interner_mod.stringInternerIntern(interner, dep_text);

                alias_name[@intCast(usize, alias_count)] = dep_canonical;
                alias_sym_id[@intCast(usize, alias_count) * 2] = @intCast(u32, mi);
                alias_sym_id[@intCast(usize, alias_count) * 2 + 1] = @intCast(u32, si);

                if (dep_count >= dep_cap) growDep(perm_alloc, &dep_to, &dep_next, &dep_cap);
                dep_to[@intCast(usize, dep_count)] = alias_count;
                dep_next[@intCast(usize, dep_count)] = dep_head[@intCast(usize, dep_canonical)];
                dep_head[@intCast(usize, dep_canonical)] = dep_count;
                dep_count += 1;

                alias_count += 1;
            }
        }
    }

    { var cap_acm: []const u8 = "CAP:ac"; pal.markerWriteInt(cap_acm, alias_count); }
    if (alias_count == 0) { var cap_m: []const u8 = "CAP:ac0\n"; pal.markerWrite(cap_m); return; }

    // Phase 2: Seed
    {
        var ai: u32 = 0;
        while (ai < alias_count) : (ai += 1) {
            var dep_name = alias_name[@intCast(usize, ai)];
            var mod_id = alias_sym_id[@intCast(usize, ai) * 2];
            var sym_idx = alias_sym_id[@intCast(usize, ai) * 2 + 1];
            var table = symbol_reg.tables_items[@intCast(usize, mod_id)];
            var sym = &table.items[@intCast(usize, sym_idx)];
            var resolved: u32 = @intCast(u32, type_mod.TYPE_UNDEFINED);

            var mod_key = @intCast(u64, mod_id) * @intCast(u64, 4294967296) + @intCast(u64, dep_name);
            if (type_mod.nameCacheGet(registry, mod_key)) |tid| { resolved = tid; }

            if (resolved == type_mod.TYPE_UNDEFINED) {
                if (type_mod.nameCacheGet(registry, @intCast(u64, dep_name))) |tid| { resolved = tid; }
            }

            if (resolved == type_mod.TYPE_UNDEFINED) {
                var cmi: usize = 0;
                while (cmi < symbol_reg.tables_len) : (cmi += 1) {
                    var ckey = @intCast(u64, cmi) * @intCast(u64, 4294967296) + @intCast(u64, dep_name);
                    if (type_mod.nameCacheGet(registry, ckey)) |tid| { resolved = tid; break; }
                }
            }

            if (resolved == type_mod.TYPE_UNDEFINED) {
                var name_str = interner_mod.stringInternerGet(interner, dep_name);
                resolved = resolveWellKnownTypeName(name_str);
            }

            if (resolved != type_mod.TYPE_UNDEFINED) {
                sym.type_id = resolved;
                var ckey = @intCast(u64, mod_id) * @intCast(u64, 4294967296) + @intCast(u64, dep_name);
                type_mod.nameCachePut(registry, ckey, resolved);
                wl[@intCast(usize, wl_len)] = ai;
                wl_len += 1;
            }
        }
    }

    // Phase 3: Kahn
    { var kst_m: []const u8 = "KAHN:start\n"; pal.markerWrite(kst_m); }

    while (wl_len > 0) {
        wl_len -= 1;
        var resolved_idx = wl[@intCast(usize, wl_len)];
        var resolved_mod = alias_sym_id[@intCast(usize, resolved_idx) * 2];
        var resolved_table = symbol_reg.tables_items[@intCast(usize, resolved_mod)];
        var resolved_sym = &resolved_table.items[@intCast(usize, alias_sym_id[@intCast(usize, resolved_idx) * 2 + 1])];
        var rt = resolved_sym.type_id;

        var decl_node = store.nodes.items[@intCast(usize, resolved_sym.decl_node)];
        var alias_own_name = decl_node.payload;
        var alias_own_text = interner_mod.stringInternerGet(interner, alias_own_name);
        var alias_own_canonical = interner_mod.stringInternerIntern(interner, alias_own_text);

        var edge_idx = dep_head[@intCast(usize, alias_own_canonical)];
        while (edge_idx != U32_MAX) {
            var dep_alias_idx = dep_to[@intCast(usize, edge_idx)];
            var dep_mod = alias_sym_id[@intCast(usize, dep_alias_idx) * 2];
            var dep_sym_idx = alias_sym_id[@intCast(usize, dep_alias_idx) * 2 + 1];
            var dep_table = symbol_reg.tables_items[@intCast(usize, dep_mod)];
            var dep_sym = &dep_table.items[@intCast(usize, dep_sym_idx)];

            if (dep_sym.type_id == 0) {
                dep_sym.type_id = rt;
                var dep_name = alias_name[@intCast(usize, dep_alias_idx)];
                var dkey = @intCast(u64, dep_mod) * @intCast(u64, 4294967296) + @intCast(u64, dep_name);
                type_mod.nameCachePut(registry, dkey, rt);
                wl[@intCast(usize, wl_len)] = dep_alias_idx;
                wl_len += 1;
            }
            edge_idx = dep_next[@intCast(usize, edge_idx)];
        }
    }

    { var ken_m: []const u8 = "KAHN:end\n"; pal.markerWrite(ken_m); }
}
