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

fn hasNamePrefix(name: []const u8, prefix: []const u8) u8 {
    if (name.len < prefix.len) return @intCast(u8, 0);
    var i: usize = @intCast(usize, 0);
    while (i < prefix.len) : (i += @intCast(usize, 1)) {
        if (name[i] != prefix[i]) return @intCast(u8, 0);
    }
    return @intCast(u8, 1);
}

// Raw-minted source identifiers must not collide with the emitted runtime's
// symbol namespaces. Applied only in MintRaw (locals/params/fields/members);
// extern/export names and nameManglerMangle outputs keep their ABI names.
fn isRuntimeReservedName(name: []const u8) u8 {
    // `zig_default_arena` is the only extern var that reaches the raw mint
    // path (via a hoisted declaration); extern names keep their ABI spelling.
    if (name.len == @intCast(usize, 17) and hasNamePrefix(name, "zig_default_arena") != @intCast(u8, 0)) return @intCast(u8, 0);
    if (hasNamePrefix(name, "Z98_") != @intCast(u8, 0)) return @intCast(u8, 1);
    if (hasNamePrefix(name, "zig_") != @intCast(u8, 0)) return @intCast(u8, 1);
    if (hasNamePrefix(name, "pal_") != @intCast(u8, 0)) return @intCast(u8, 1);
    if (hasNamePrefix(name, "zT_") != @intCast(u8, 0)) return @intCast(u8, 1);
    if (hasNamePrefix(name, "zF_") != @intCast(u8, 0)) return @intCast(u8, 1);
    if (hasNamePrefix(name, "zG_") != @intCast(u8, 0)) return @intCast(u8, 1);
    return @intCast(u8, 0);
}

fn nameManglerPopulateKeywords(self: *NameMangler) void {
    // C89 keywords plus the documented-reserved MSVC 6 / OpenWatcom C-mode
    // extension keywords (I-1 report, Tier A). Bare `self` is deliberately
    // absent: neither compiler reserves it in C mode. Slice-typed locals (not
    // bare string literals) keep the array-literal lowering on the proven path.
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
    var k32: []const u8 = "cdecl";
    var k33: []const u8 = "near";
    var k34: []const u8 = "far";
    var k35: []const u8 = "huge";
    var k36: []const u8 = "pascal";
    var k37: []const u8 = "fortran";
    var k38: []const u8 = "interrupt";
    var k39: []const u8 = "stdcall";
    var k40: []const u8 = "fastcall";
    var k41: []const u8 = "asm";
    var k42: []const u8 = "inline";
    var k43: []const u8 = "based";
    var k44: []const u8 = "int8";
    var k45: []const u8 = "int16";
    var k46: []const u8 = "int32";
    var k47: []const u8 = "int64";
    var k48: []const u8 = "leave";
    var k49: []const u8 = "_asm";
    var k50: []const u8 = "_based";
    var k51: []const u8 = "_cdecl";
    var k52: []const u8 = "_declspec";
    var k53: []const u8 = "_emit";
    var k54: []const u8 = "_except";
    var k55: []const u8 = "_export";
    var k56: []const u8 = "_far";
    var k57: []const u8 = "_far16";
    var k58: []const u8 = "_fastcall";
    var k59: []const u8 = "_finally";
    var k60: []const u8 = "_fortran";
    var k61: []const u8 = "_huge";
    var k62: []const u8 = "_inline";
    var k63: []const u8 = "_int8";
    var k64: []const u8 = "_int16";
    var k65: []const u8 = "_int32";
    var k66: []const u8 = "_int64";
    var k67: []const u8 = "_interrupt";
    var k68: []const u8 = "_leave";
    var k69: []const u8 = "_loadds";
    var k70: []const u8 = "_near";
    var k71: []const u8 = "_pascal";
    var k72: []const u8 = "_saveregs";
    var k73: []const u8 = "_segment";
    var k74: []const u8 = "_segname";
    var k75: []const u8 = "_self";
    var k76: []const u8 = "_stdcall";
    var k77: []const u8 = "_syscall";
    var k78: []const u8 = "_try";
    var k79: []const u8 = "__asm";
    var k80: []const u8 = "__based";
    var k81: []const u8 = "__cdecl";
    var k82: []const u8 = "__declspec";
    var k83: []const u8 = "__emit";
    var k84: []const u8 = "__except";
    var k85: []const u8 = "__export";
    var k86: []const u8 = "__far";
    var k87: []const u8 = "__far16";
    var k88: []const u8 = "__fastcall";
    var k89: []const u8 = "__finally";
    var k90: []const u8 = "__fortran";
    var k91: []const u8 = "__huge";
    var k92: []const u8 = "__inline";
    var k93: []const u8 = "__int8";
    var k94: []const u8 = "__int16";
    var k95: []const u8 = "__int32";
    var k96: []const u8 = "__int64";
    var k97: []const u8 = "__interrupt";
    var k98: []const u8 = "__leave";
    var k99: []const u8 = "__loadds";
    var k100: []const u8 = "__near";
    var k101: []const u8 = "__pascal";
    var k102: []const u8 = "__saveregs";
    var k103: []const u8 = "__segment";
    var k104: []const u8 = "__segname";
    var k105: []const u8 = "__self";
    var k106: []const u8 = "__stdcall";
    var k107: []const u8 = "__syscall";
    var k108: []const u8 = "__try";
    var k109: []const u8 = "__unaligned";
    var k110: []const u8 = "__watcall";
    var k111: []const u8 = "__ptr32";
    var k112: []const u8 = "__ptr64";
    var k113: []const u8 = "_Cdecl";
    var k114: []const u8 = "_Except";
    var k115: []const u8 = "_Export";
    var k116: []const u8 = "_Far16";
    var k117: []const u8 = "_Fastcall";
    var k118: []const u8 = "_Finally";
    var k119: []const u8 = "_Leave";
    var k120: []const u8 = "_Packed";
    var k121: []const u8 = "_Pascal";
    var k122: []const u8 = "_Seg16";
    var k123: []const u8 = "_Syscall";
    var k124: []const u8 = "_System";
    var k125: []const u8 = "_Try";
    var keywords: [126][]const u8 = [126][]const u8{ k0, k1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11, k12, k13, k14, k15, k16, k17, k18, k19, k20, k21, k22, k23, k24, k25, k26, k27, k28, k29, k30, k31, k32, k33, k34, k35, k36, k37, k38, k39, k40, k41, k42, k43, k44, k45, k46, k47, k48, k49, k50, k51, k52, k53, k54, k55, k56, k57, k58, k59, k60, k61, k62, k63, k64, k65, k66, k67, k68, k69, k70, k71, k72, k73, k74, k75, k76, k77, k78, k79, k80, k81, k82, k83, k84, k85, k86, k87, k88, k89, k90, k91, k92, k93, k94, k95, k96, k97, k98, k99, k100, k101, k102, k103, k104, k105, k106, k107, k108, k109, k110, k111, k112, k113, k114, k115, k116, k117, k118, k119, k120, k121, k122, k123, k124, k125 };
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
    if (isC89Keyword(self, name_id) != @intCast(u8, 0) or isRuntimeReservedName(name) != @intCast(u8, 0)) {
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
