const StringInterner = @import("string_interner.zig").StringInterner;
const interner_mod = @import("string_interner.zig");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const Sand = @import("allocator.zig").Sand;
const hash_mod = @import("util/hash.zig");
const U64ToU32Map = @import("util/hash.zig").U64ToU32Map;
const U32ToU32Map = @import("util/hash.zig").U32ToU32Map;
const itoa_mod = @import("util/itoa.zig");

// P1 (emitter sanitization): the single C-identifier minting authority.
// Every emitted C identifier is minted here: C-keyword escape + collision
// resolution + stable per-kind names (fn/global/type/local/temp/union-member/
// struct-field/synthetic-type/module/printer). Extern C symbols (PAL/runtime/
// `extern fn`) never leave here renamed: the emitter overrides their emitted
// name with the exact source name (hard boundary).

pub const NameMangler = struct {
    hash_seed: u32,
    cache: U64ToU32Map,
    keyword_set: U32ToU32Map,
    collision_mod: U32ToU32Map,
    collision_name: U32ToU32Map,
    interner: *StringInterner,
    exported: ?*U64ToU32Map,
    raw_cache_local: U64ToU32Map,
    raw_taken_local: U64ToU32Map,
    raw_cache_field: U64ToU32Map,
    raw_taken_field: U64ToU32Map,
    raw_cache_member: U64ToU32Map,
    raw_taken_member: U64ToU32Map,
};

fn writeHex(buf: []u8, pos: *usize, value: u32) void {
    var v = value;
    var hex_buf: [8]u8 = undefined;
    var i: u32 = @intCast(u32, 8);
    while (i > @intCast(u32, 0)) {
        i -= @intCast(u32, 1);
        var nibble = v & @intCast(u32, 0xF);
        if (nibble < @intCast(u32, 10)) {
            hex_buf[@intCast(usize, i)] = @intCast(u8, '0') + @intCast(u8, nibble);
        } else {
            hex_buf[@intCast(usize, i)] = @intCast(u8, 'A') + @intCast(u8, nibble - @intCast(u32, 10));
        }
        v = v >> @intCast(u32, 4);
    }
    var j: usize = @intCast(usize, 0);
    while (j < @intCast(usize, 8)) : (j += @intCast(usize, 1)) {
        buf[@intCast(usize, pos.*) + j] = hex_buf[j];
    }
    pos.* += @intCast(usize, 8);
}

fn isTempOrBuiltin(name: []const u8) u8 {
    if (name.len < @intCast(usize, 5)) return @intCast(u8, 0);
    if (name[0] != '_' or name[1] != '_') return @intCast(u8, 0);
    if (name[2] == 't' and name[3] == 'm' and name[4] == 'p') return @intCast(u8, 1);
    if (name[2] == 'r' and name[3] == 'e' and name[4] == 't') return @intCast(u8, 1);
    if (name.len >= @intCast(usize, 11) and name[2] == 'b' and name[3] == 'o' and name[4] == 'o' and
        name[5] == 't' and name[6] == 's' and name[7] == 't' and name[8] == 'r' and name[9] == 'a' and name[10] == 'p') {
        return @intCast(u8, 1);
    }
    return @intCast(u8, 0);
}

fn isC89Keyword(self: *NameMangler, name_id: u32) u8 {
    if (hash_mod.u32ToU32MapGet(&self.keyword_set, name_id)) |_| return @intCast(u8, 1);
    return @intCast(u8, 0);
}

fn mangleC89Keyword(self: *NameMangler, name: []const u8) u32 {
    var buf: [33]u8 = undefined;
    buf[0] = @intCast(u8, 'z');
    buf[1] = @intCast(u8, '_');
    var i: usize = @intCast(usize, 0);
    while (i < name.len and i + @intCast(usize, 2) < @intCast(usize, 33)) : (i += @intCast(usize, 1)) {
        buf[i + @intCast(usize, 2)] = name[i];
    }
    return interner_mod.stringInternerIntern(self.interner, buf[0 .. i + @intCast(usize, 2)]);
}

fn nameManglerPopulateKeywords(self: *NameMangler) void {
    var k0: []const u8 = "auto";
    var k1: []const u8 = "break";
    var k2: []const u8 = "case";
    var k3: []const u8 = "char";
    var k4: []const u8 = "const";
    var k5: []const u8 = "continue";
    var k6: []const u8 = "default";
    var k7: []const u8 = "do";
    var k8: []const u8 = "double";
    var k9: []const u8 = "else";
    var k10: []const u8 = "enum";
    var k11: []const u8 = "extern";
    var k12: []const u8 = "float";
    var k13: []const u8 = "for";
    var k14: []const u8 = "goto";
    var k15: []const u8 = "if";
    var k16: []const u8 = "int";
    var k17: []const u8 = "long";
    var k18: []const u8 = "register";
    var k19: []const u8 = "return";
    var k20: []const u8 = "short";
    var k21: []const u8 = "signed";
    var k22: []const u8 = "sizeof";
    var k23: []const u8 = "static";
    var k24: []const u8 = "struct";
    var k25: []const u8 = "switch";
    var k26: []const u8 = "typedef";
    var k27: []const u8 = "union";
    var k28: []const u8 = "unsigned";
    var k29: []const u8 = "void";
    var k30: []const u8 = "volatile";
    var k31: []const u8 = "while";
    var keywords: [32][]const u8 = [32][]const u8{ k0, k1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11, k12, k13, k14, k15, k16, k17, k18, k19, k20, k21, k22, k23, k24, k25, k26, k27, k28, k29, k30, k31 };
    var ki: usize = @intCast(usize, 0);
    while (ki < keywords.len) : (ki += @intCast(usize, 1)) {
        hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, keywords[ki]), @intCast(u32, 1));
    }
}

pub fn nameManglerInit(interner: *StringInterner, alloc: *Sand, cache_hint: usize) NameMangler {
    var mangler = NameMangler{
        .hash_seed = @intCast(u32, 0),
        .cache = hash_mod.u64ToU32MapInitCap(alloc, cache_hint),
        .keyword_set = hash_mod.u32ToU32MapInitCap(alloc, @intCast(usize, 32)),
        .collision_mod = hash_mod.u32ToU32MapInit(alloc),
        .collision_name = hash_mod.u32ToU32MapInit(alloc),
        .interner = interner,
        .exported = null,
        .raw_cache_local = hash_mod.u64ToU32MapInit(alloc),
        .raw_taken_local = hash_mod.u64ToU32MapInit(alloc),
        .raw_cache_field = hash_mod.u64ToU32MapInit(alloc),
        .raw_taken_field = hash_mod.u64ToU32MapInit(alloc),
        .raw_cache_member = hash_mod.u64ToU32MapInit(alloc),
        .raw_taken_member = hash_mod.u64ToU32MapInit(alloc),
    };
    nameManglerPopulateKeywords(&mangler);
    return mangler;
}

pub fn nameManglerMangle(self: *NameMangler, name_id: u32, kind: u8, module_id: u32) u32 {
    var name = interner_mod.stringInternerGet(self.interner, name_id);
    if (isTempOrBuiltin(name) != @intCast(u8, 0)) return name_id;
    if (isC89Keyword(self, name_id) != @intCast(u8, 0)) return mangleC89Keyword(self, name);
    var key: u64 = (@intCast(u64, module_id) << @intCast(u64, 35)) | (@intCast(u64, kind) << @intCast(u64, 32)) | @intCast(u64, name_id);
    if (self.exported) |exp_map| {
        if (hash_mod.u64ToU32MapGet(exp_map, key)) |_| return name_id;
    }
    if (hash_mod.u64ToU32MapGet(&self.cache, key)) |cached| {
        return cached;
    }
    var hash = hash_mod.fnv1a(name);
    var kind_char: u8 = @intCast(u8, 'L');
    if (kind == @intCast(u8, 0)) { kind_char = @intCast(u8, 'F'); }
    else if (kind == @intCast(u8, 1)) { kind_char = @intCast(u8, 'G'); }
    else if (kind == @intCast(u8, 2)) { kind_char = @intCast(u8, 'T'); }
    var buf: [32]u8 = undefined;
    var p: usize = @intCast(usize, 0);
    buf[p] = @intCast(u8, 'z'); p += @intCast(usize, 1);
    buf[p] = kind_char;          p += @intCast(usize, 1);
    buf[p] = @intCast(u8, '_');  p += @intCast(usize, 1);
    writeHex(buf[0..], &p, hash);
    buf[p] = @intCast(u8, '_');  p += @intCast(usize, 1);
    var prefix_end = p;
    var idx: usize = @intCast(usize, 0);
    while (idx < name.len and p < @intCast(usize, 31)) : (idx += @intCast(usize, 1)) {
        buf[p] = name[idx];
        p += @intCast(usize, 1);
    }
    if (p > @intCast(usize, 31)) p = @intCast(usize, 31);
    var mangled_id = interner_mod.stringInternerIntern(self.interner, buf[0..p]);
    // Collision resolution: if mangled_id already used by a different (module_id,name_id),
    // append _N suffix, truncating base name to fit within 31-char C89 limit.
    // Digit count computed dynamically to avoid truncation inside the suffix number.
    var counter: u32 = @intCast(u32, 0);
    while (true) {
        var existing_mod = hash_mod.u32ToU32MapGet(&self.collision_mod, mangled_id);
        if (existing_mod) |_| {
            counter += @intCast(u32, 1);
            p = prefix_end;
            var cnt = counter;
            var dc: u32 = @intCast(u32, 1);
            while (cnt >= @intCast(u32, 10)) : (cnt /= @intCast(u32, 10)) {
                dc += @intCast(u32, 1);
            }
            var max_nc: usize = @intCast(usize, 31) - prefix_end - @intCast(usize, 1) - @intCast(usize, dc);
            var ci: usize = @intCast(usize, 0);
            while (ci < name.len and p < prefix_end + max_nc) : (ci += @intCast(usize, 1)) {
                buf[p] = name[ci];
                p += @intCast(usize, 1);
            }
            buf[p] = @intCast(u8, '_'); p += @intCast(usize, 1);
            var cv = counter;
            var cd: [4]u8 = undefined;
            var di: u32 = @intCast(u32, 0);
            while (cv > @intCast(u32, 0)) {
                cd[@intCast(usize, di)] = @intCast(u8, '0') + @intCast(u8, cv % @intCast(u32, 10));
                cv /= @intCast(u32, 10);
                di += @intCast(u32, 1);
            }
            if (di == @intCast(u32, 0)) {
                buf[p] = @intCast(u8, '0'); p += @intCast(usize, 1);
            } else {
                var dk: u32 = di;
                while (dk > @intCast(u32, 0)) {
                    dk -= @intCast(u32, 1);
                    buf[p] = cd[@intCast(usize, dk)]; p += @intCast(usize, 1);
                }
            }
            if (p > @intCast(usize, 31)) p = @intCast(usize, 31);
            mangled_id = interner_mod.stringInternerIntern(self.interner, buf[0..p]);
        } else {
            break;
        }
    }
    hash_mod.u32ToU32MapPut(&self.collision_mod, mangled_id, module_id);
    hash_mod.u32ToU32MapPut(&self.collision_name, mangled_id, name_id);
    hash_mod.u64ToU32MapPut(&self.cache, key, mangled_id);
    return mangled_id;
}

pub fn nameManglerMangleGlobal(self: *NameMangler, registry: *TypeRegistry, name_id: u32, module_id: u32, type_id: u32) u32 {
    if (type_id < @intCast(u32, registry.types_len)) {
        var ty = registry.types_items[@intCast(usize, type_id)];
        if (ty.name_id != @intCast(u32, 0) and ty.name_id == name_id) {
            // Type-storage global: identity = the stored type (name + owning module),
            // so every module aliasing this type agrees on ONE C symbol.
            return nameManglerMangle(self, ty.name_id, @intCast(u8, 1), ty.module_id);
        }
    }
    // User module global: keep per-module keying.
    return nameManglerMangle(self, name_id, @intCast(u8, 1), module_id);
}

// Raw-identifier rule (local/struct-field/union-member kinds): the source name
// passes through byte-identical; a C keyword becomes `z_<name>`; a candidate
// already claimed in the same scope by a different name gets a `_N` suffix.
// Scopes are per C function (locals) or per owning aggregate (fields/members),
// so identical source names in different scopes stay byte-identical.
fn nameManglerMintRaw(self: *NameMangler, name_id: u32, scope: u32, cache: *U64ToU32Map, taken: *U64ToU32Map) []const u8 {
    var key: u64 = (@intCast(u64, scope) << @intCast(u64, 32)) | @intCast(u64, name_id);
    if (hash_mod.u64ToU32MapGet(cache, key)) |cached| {
        return interner_mod.stringInternerGet(self.interner, cached);
    }
    var name = interner_mod.stringInternerGet(self.interner, name_id);
    var cand_id: u32 = name_id;
    if (isC89Keyword(self, name_id) != @intCast(u8, 0)) {
        cand_id = mangleC89Keyword(self, name);
    }
    var counter: u32 = @intCast(u32, 0);
    while (true) {
        var tkey: u64 = (@intCast(u64, scope) << @intCast(u64, 32)) | @intCast(u64, cand_id);
        if (hash_mod.u64ToU32MapGet(taken, tkey)) |_| {
            counter += @intCast(u32, 1);
            var cand = interner_mod.stringInternerGet(self.interner, cand_id);
            var buf: [128]u8 = undefined;
            var p: usize = @intCast(usize, 0);
            var ci: usize = @intCast(usize, 0);
            while (ci < cand.len and p < @intCast(usize, 118)) : (ci += @intCast(usize, 1)) {
                buf[p] = cand[ci];
                p += @intCast(usize, 1);
            }
            buf[p] = @intCast(u8, 95);
            p += @intCast(usize, 1);
            var db: [16]u8 = undefined;
            var dl = itoa_mod.itoa(counter, db[0..]);
            var ds: usize = @intCast(usize, 15) - @intCast(usize, dl);
            var di: usize = ds;
            while (di < @intCast(usize, 15) and p < @intCast(usize, 127)) : (di += @intCast(usize, 1)) {
                buf[p] = db[di];
                p += @intCast(usize, 1);
            }
            cand_id = interner_mod.stringInternerIntern(self.interner, buf[0..p]);
        } else {
            break;
        }
    }
    hash_mod.u64ToU32MapPut(cache, key, cand_id);
    var done_key: u64 = (@intCast(u64, scope) << @intCast(u64, 32)) | @intCast(u64, cand_id);
    hash_mod.u64ToU32MapPut(taken, done_key, @intCast(u32, 1));
    return interner_mod.stringInternerGet(self.interner, cand_id);
}

pub fn nameManglerMintLocal(self: *NameMangler, name_id: u32, scope: u32) []const u8 {
    return nameManglerMintRaw(self, name_id, scope, &self.raw_cache_local, &self.raw_taken_local);
}

pub fn nameManglerMintField(self: *NameMangler, name_id: u32, scope: u32) []const u8 {
    return nameManglerMintRaw(self, name_id, scope, &self.raw_cache_field, &self.raw_taken_field);
}

pub fn nameManglerMintMember(self: *NameMangler, name_id: u32, scope: u32) []const u8 {
    return nameManglerMintRaw(self, name_id, scope, &self.raw_cache_member, &self.raw_taken_member);
}

// Deterministic per-function scope key for local mints: interned
// "<module_id>_<name_id>". The key value only partitions the occupancy maps;
// minted strings depend on the scope GROUPING, not on the key value, so the
// same program mints the same names in every compilation.
pub fn nameManglerFnScope(self: *NameMangler, fn_name_id: u32, fn_module_id: u32) u32 {
    var buf: [24]u8 = undefined;
    var p: usize = @intCast(usize, 0);
    var db: [16]u8 = undefined;
    var dl = itoa_mod.itoa(fn_module_id, db[0..]);
    var ds: usize = @intCast(usize, 15) - @intCast(usize, dl);
    var i: usize = ds;
    while (i < @intCast(usize, 15) and p < @intCast(usize, 10)) : (i += @intCast(usize, 1)) {
        buf[p] = db[i];
        p += @intCast(usize, 1);
    }
    buf[p] = @intCast(u8, 95);
    p += @intCast(usize, 1);
    var dl2 = itoa_mod.itoa(fn_name_id, db[0..]);
    var ds2: usize = @intCast(usize, 15) - @intCast(usize, dl2);
    i = ds2;
    while (i < @intCast(usize, 15) and p < @intCast(usize, 23)) : (i += @intCast(usize, 1)) {
        buf[p] = db[i];
        p += @intCast(usize, 1);
    }
    return interner_mod.stringInternerIntern(self.interner, buf[0..p]);
}

// Temp rule: `zT_<temp_id>` (stable, keyword-safe).
pub fn nameManglerMintTemp(self: *NameMangler, temp_id: u32) []const u8 {
    var buf: [20]u8 = undefined;
    buf[0] = @intCast(u8, 'z');
    buf[1] = @intCast(u8, 'T');
    buf[2] = @intCast(u8, '_');
    var len = itoa_mod.itoa(temp_id, buf[3..]);
    var dig_start: usize = @intCast(usize, 19) - @intCast(usize, len);
    var di: usize = @intCast(usize, 3);
    var i: usize = @intCast(usize, 0);
    while (i < @intCast(usize, len)) : (i += @intCast(usize, 1)) {
        buf[di + i] = buf[dig_start + i];
    }
    var end: usize = di + @intCast(usize, len);
    var mid = interner_mod.stringInternerIntern(self.interner, buf[0..end]);
    return interner_mod.stringInternerGet(self.interner, mid);
}

// D5-5: one synthetic type-name rule for the array/slice/optional/tuple C
// names. Shape: `prefix + transformed(elem_name)` then, when `len_text` is
// non-empty, `"_" + len_text` (with the `_` only when an element name was
// present). `transformed` maps ' ' and '*' to '_'. The interned buffer is
// mangled at module 0, byte-identical to the prior per-kind builders.
pub fn nameManglerMintSyntheticType(self: *NameMangler, prefix: []const u8, elem_name: []const u8, len_text: []const u8, cap: usize) []const u8 {
    var buf: [128]u8 = undefined;
    var p: usize = @intCast(usize, 0);
    var i: usize = @intCast(usize, 0);
    while (i < prefix.len and p < cap) : (i += @intCast(usize, 1)) {
        buf[p] = prefix[i]; p += @intCast(usize, 1);
    }
    i = @intCast(usize, 0);
    while (i < elem_name.len and p < cap) : (i += @intCast(usize, 1)) {
        var c = elem_name[i];
        if (c == @intCast(u8, 32) or c == @intCast(u8, 42)) { c = @intCast(u8, 95); }
        buf[p] = c; p += @intCast(usize, 1);
    }
    if (len_text.len > @intCast(usize, 0)) {
        if (elem_name.len > @intCast(usize, 0) and p < cap) {
            buf[p] = @intCast(u8, 95); p += @intCast(usize, 1);
        }
        i = @intCast(usize, 0);
        while (i < len_text.len and p < cap) : (i += @intCast(usize, 1)) {
            buf[p] = len_text[i]; p += @intCast(usize, 1);
        }
    }
    var nid = interner_mod.stringInternerIntern(self.interner, buf[0..p]);
    var mid = nameManglerMangle(self, nid, @intCast(u8, 2), @intCast(u32, 0));
    return interner_mod.stringInternerGet(self.interner, mid);
}

// Printer/table/scratch rule: prefix + decimal index, interned (the generated
// printer/table naming rule; also the packed-field scratch name rule).
pub fn nameManglerMintIndexName(self: *NameMangler, prefix: []const u8, n: u32) []const u8 {
    var buf: [64]u8 = undefined;
    var p: usize = @intCast(usize, 0);
    var i: usize = @intCast(usize, 0);
    while (i < prefix.len and p < @intCast(usize, 63)) : (i += @intCast(usize, 1)) { buf[p] = prefix[i]; p += @intCast(usize, 1); }
    var db: [16]u8 = undefined;
    var dl = itoa_mod.itoa(n, db[0..]);
    var ds: usize = @intCast(usize, 15) - @intCast(usize, dl);
    var j: usize = ds;
    while (j < @intCast(usize, 15) and p < @intCast(usize, 63)) : (j += @intCast(usize, 1)) { buf[p] = db[j]; p += @intCast(usize, 1); }
    var nid = interner_mod.stringInternerIntern(self.interner, buf[0..p]);
    return interner_mod.stringInternerGet(self.interner, nid);
}

// Module rule: `<file-stem>_<fnv1a(path) hex8>` (the module stem used for the
// emitted .c/.h file names and build-script entries).
pub fn nameManglerMintModuleStem(self: *NameMangler, path_str: []const u8) []const u8 {
    var last_slash: usize = @intCast(usize, 0);
    var has_slash: u8 = @intCast(u8, 0);
    var ps_i: usize = @intCast(usize, 0);
    while (ps_i < path_str.len) : (ps_i += @intCast(usize, 1)) {
        if (path_str[ps_i] == @intCast(u8, '/')) { last_slash = ps_i; has_slash = @intCast(u8, 1); }
    }
    var base: []const u8 = undefined;
    if (has_slash != @intCast(u8, 0)) {
        var dbl_start: usize = last_slash + @intCast(usize, 1);
        base = path_str[dbl_start..path_str.len];
    } else {
        base = path_str;
    }
    var bl = base.len;
    if (bl >= @intCast(usize, 4) and base[bl - @intCast(usize, 4)] == @intCast(u8, '.') and base[bl - @intCast(usize, 3)] == @intCast(u8, 'z') and base[bl - @intCast(usize, 2)] == @intCast(u8, 'i') and base[bl - @intCast(usize, 1)] == @intCast(u8, 'g')) {
        var bl4: usize = bl - @intCast(usize, 4);
        base = base[0..bl4];
    } else if (bl >= @intCast(usize, 4) and base[bl - @intCast(usize, 4)] == @intCast(u8, '.') and base[bl - @intCast(usize, 3)] == @intCast(u8, 'z') and base[bl - @intCast(usize, 2)] == @intCast(u8, '9') and base[bl - @intCast(usize, 1)] == @intCast(u8, '8')) {
        var bl4: usize = bl - @intCast(usize, 4);
        base = base[0..bl4];
    }
    bl = base.len;
    if (bl > @intCast(usize, 64)) {
        base = base[0..@intCast(usize, 64)];
    }
    var hash = hash_mod.fnv1a(path_str);
    var buf: [96]u8 = undefined;
    var pos: usize = @intCast(usize, 0);
    var bi: usize = @intCast(usize, 0);
    while (bi < base.len) : (bi += @intCast(usize, 1)) {
        buf[pos] = base[bi];
        pos += @intCast(usize, 1);
    }
    buf[pos] = @intCast(u8, '_');
    pos += @intCast(usize, 1);
    writeHex(buf[0..], &pos, hash);
    var qid = interner_mod.stringInternerIntern(self.interner, buf[0..pos]);
    return interner_mod.stringInternerGet(self.interner, qid);
}
