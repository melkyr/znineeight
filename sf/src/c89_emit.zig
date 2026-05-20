const pal = @import("pal.zig");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeKind = @import("type_registry.zig").TypeKind;
const StringInterner = @import("string_interner.zig").StringInterner;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const SwitchCaseArrayList = @import("lir.zig").SwitchCaseArrayList;
const U32ArrayList = @import("growable_array.zig").U32ArrayList;
const U64ToU32Map = @import("util/hash.zig").U64ToU32Map;
const U32ToU32Map = @import("util/hash.zig").U32ToU32Map;
const alloc_mod = @import("allocator.zig");
const Sand = @import("allocator.zig").Sand;
const hash_mod = @import("util/hash.zig");
const interner_mod = @import("string_interner.zig");
const type_resolver = @import("type_resolver.zig");
const TypeResolver = type_resolver.TypeResolver;
const sym_reg = @import("symbol_registrator.zig");

pub const BufferedWriter = struct {
    buf: [4096]u8,
    pos: usize,
};

pub fn bufferedWriterInit() BufferedWriter {
    return BufferedWriter{ .buf = undefined, .pos = @intCast(usize, 0) };
}

pub fn bufferedWriterFlush(self: *BufferedWriter) void {
    if (self.pos == @intCast(usize, 0)) return;
    pal.stdout_write(self.buf[0..self.pos]);
    self.pos = @intCast(usize, 0);
}

pub fn bufferedWriterWrite(self: *BufferedWriter, data: []const u8) void {
    var remaining = data;
    while (remaining.len > @intCast(usize, 0)) {
        var space = 4096 - self.pos;
        var copy_len = if (remaining.len < space) remaining.len else space;
        var i: usize = @intCast(usize, 0);
        while (i < copy_len) : (i += @intCast(usize, 1)) {
            self.buf[self.pos + i] = remaining[i];
        }
        self.pos += copy_len;
        remaining = remaining[copy_len..];
        if (self.pos == 4096) bufferedWriterFlush(self);
    }
}

pub fn bufferedWriterWriteByte(self: *BufferedWriter, byte: u8) void {
    if (self.pos == 4096) bufferedWriterFlush(self);
    self.buf[self.pos] = byte;
    self.pos += @intCast(usize, 1);
}

pub fn bufferedWriterWriteIndent(self: *BufferedWriter, level: u32) void {
    var total = level * @intCast(u32, 4);
    var i: u32 = @intCast(u32, 0);
    while (i < total) : (i += @intCast(u32, 1)) {
        if (self.pos == 4096) bufferedWriterFlush(self);
        self.buf[self.pos] = @intCast(u8, ' ');
        self.pos += @intCast(usize, 1);
    }
}

pub const NameMangler = struct {
    hash_seed: u32,
    cache: U64ToU32Map,
    keyword_set: U32ToU32Map,
    collision_mod: U32ToU32Map,
    collision_name: U32ToU32Map,
    interner: *StringInterner,
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
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k0), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k1), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k2), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k3), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k4), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k5), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k6), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k7), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k8), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k9), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k10), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k11), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k12), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k13), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k14), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k15), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k16), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k17), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k18), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k19), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k20), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k21), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k22), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k23), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k24), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k25), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k26), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k27), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k28), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k29), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k30), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k31), @intCast(u32, 1));
}

pub fn nameManglerInit(interner: *StringInterner, alloc: *Sand) NameMangler {
    var mangler = NameMangler{
        .hash_seed = @intCast(u32, 0),
        .cache = hash_mod.u64ToU32MapInit(alloc),
        .keyword_set = hash_mod.u32ToU32MapInit(alloc),
        .collision_mod = hash_mod.u32ToU32MapInit(alloc),
        .collision_name = hash_mod.u32ToU32MapInit(alloc),
        .interner = interner,
    };
    nameManglerPopulateKeywords(&mangler);
    return mangler;
}

pub fn nameManglerMangle(self: *NameMangler, name_id: u32, kind: u8, module_id: u32) u32 {
    var name = interner_mod.stringInternerGet(self.interner, name_id);
    if (isTempOrBuiltin(name) != @intCast(u8, 0)) return name_id;
    if (isC89Keyword(self, name_id) != @intCast(u8, 0)) return mangleC89Keyword(self, name);
    var key: u64 = (@intCast(u64, module_id) << @intCast(u64, 32)) | @intCast(u64, name_id);
    if (hash_mod.u64ToU32MapGet(&self.cache, key)) |cached| return cached;
    var hash = hash_mod.fnv1a(name);
    var kind_char: u8 = @intCast(u8, 'L');
    if (kind == @intCast(u8, 0)) kind_char = @intCast(u8, 'F');
    else if (kind == @intCast(u8, 1)) kind_char = @intCast(u8, 'G');
    else if (kind == @intCast(u8, 2)) kind_char = @intCast(u8, 'T');
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
    var counter: u32 = @intCast(u32, 0);
    while (true) {
        var existing_mod = hash_mod.u32ToU32MapGet(&self.collision_mod, mangled_id);
        if (existing_mod) |mod| {
            var existing_name = hash_mod.u32ToU32MapGet(&self.collision_name, mangled_id);
            if (existing_name) |name| {
                if (mod == module_id and name == name_id) break;
            }
            counter += @intCast(u32, 1);
            p = prefix_end;
            var max_nc = @intCast(usize, 31) - prefix_end - @intCast(usize, 3);
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

pub const C89Emitter = struct {
    writer: BufferedWriter,
    indent: u32,
    alloc: *Sand,
    registry: *TypeRegistry,
    interner: *StringInterner,
    mangler: *NameMangler,
    diag: *DiagnosticCollector,
    switch_cases: *SwitchCaseArrayList,
    call_args: *U32ArrayList,
};

pub fn c89EmitterInit(reg: *TypeRegistry, interner: *StringInterner, mangler: *NameMangler, diag: *DiagnosticCollector, sc: *SwitchCaseArrayList, ca: *U32ArrayList, alloc: *Sand) C89Emitter {
    return C89Emitter{
        .writer = bufferedWriterInit(),
        .indent = @intCast(u32, 0),
        .alloc = alloc,
        .registry = reg,
        .interner = interner,
        .mangler = mangler,
        .diag = diag,
        .switch_cases = sc,
        .call_args = ca,
    };
}

pub fn emitZigCompatH(writer: *BufferedWriter) void {
    var l00: []const u8 = "/* zig_compat.h - C89 compatibility layer */\n";
    bufferedWriterWrite(writer, l00);
    var l01: []const u8 = "#ifndef ZIG_COMPAT_H\n";
    bufferedWriterWrite(writer, l01);
    var l02: []const u8 = "#define ZIG_COMPAT_H\n";
    bufferedWriterWrite(writer, l02);
    var l03: []const u8 = "\n";
    bufferedWriterWrite(writer, l03);
    var l04: []const u8 = "/* 64-bit integers */\n";
    bufferedWriterWrite(writer, l04);
    var l05: []const u8 = "#if defined(_MSC_VER) && _MSC_VER <= 1200\n";
    bufferedWriterWrite(writer, l05);
    var l06: []const u8 = "  typedef __int64 z64;\n";
    bufferedWriterWrite(writer, l06);
    var l07: []const u8 = "  typedef unsigned __int64 zu64;\n";
    bufferedWriterWrite(writer, l07);
    var l08: []const u8 = "#elif defined(__WATCOMC__)\n";
    bufferedWriterWrite(writer, l08);
    var l09: []const u8 = "  typedef __int64 z64;\n";
    bufferedWriterWrite(writer, l09);
    var l10: []const u8 = "  typedef unsigned __int64 zu64;\n";
    bufferedWriterWrite(writer, l10);
    var l11: []const u8 = "#else\n";
    bufferedWriterWrite(writer, l11);
    var l12: []const u8 = "  typedef long long z64;\n";
    bufferedWriterWrite(writer, l12);
    var l13: []const u8 = "  typedef unsigned long long zu64;\n";
    bufferedWriterWrite(writer, l13);
    var l14: []const u8 = "#endif\n";
    bufferedWriterWrite(writer, l14);
    var l15: []const u8 = "\n";
    bufferedWriterWrite(writer, l15);
    var l16: []const u8 = "/* Boolean */\n";
    bufferedWriterWrite(writer, l16);
    var l17: []const u8 = "#ifndef bool\n";
    bufferedWriterWrite(writer, l17);
    var l18: []const u8 = "  typedef int bool;\n";
    bufferedWriterWrite(writer, l18);
    var l19: []const u8 = "  #define true 1\n";
    bufferedWriterWrite(writer, l19);
    var l20: []const u8 = "  #define false 0\n";
    bufferedWriterWrite(writer, l20);
    var l21: []const u8 = "#endif\n";
    bufferedWriterWrite(writer, l21);
    var l22: []const u8 = "\n";
    bufferedWriterWrite(writer, l22);
    var l23: []const u8 = "/* Null pointer */\n";
    bufferedWriterWrite(writer, l23);
    var l24: []const u8 = "#ifndef NULL\n";
    bufferedWriterWrite(writer, l24);
    var l25: []const u8 = "  #define NULL ((void*)0)\n";
    bufferedWriterWrite(writer, l25);
    var l26: []const u8 = "#endif\n";
    bufferedWriterWrite(writer, l26);
    var l27: []const u8 = "\n";
    bufferedWriterWrite(writer, l27);
    var l28: []const u8 = "#endif\n";
    bufferedWriterWrite(writer, l28);
}

pub fn emitSpecialTypes(emitter: *C89Emitter, reg: *TypeRegistry, g: *sym_reg.DepGraph) void {
    var resolver: TypeResolver = type_resolver.typeResolverInit(reg, emitter.diag, emitter.alloc);
    type_resolver.typeResolverBuild(&resolver, g);
    type_resolver.typeResolverResolve(&resolver);
    var sorted = type_resolver.typeResolverGetSorted(&resolver);
    var i: usize = @intCast(usize, 0);
    while (i < sorted.len) : (i += @intCast(usize, 1)) {
        var tid = sorted[i];
        var ty = reg.types_items[@intCast(usize, tid)];
        if (ty.kind == TypeKind.void_type) continue;
        if (ty.kind == TypeKind.bool_type) continue;
        if (ty.kind == TypeKind.noreturn_type) continue;
        if (ty.kind == TypeKind.null_type) continue;
        if (ty.kind == TypeKind.undefined_type) continue;
        if (ty.kind == TypeKind.integer_literal_type) continue;
        if (ty.kind == TypeKind.type_type) continue;
        if (ty.kind == TypeKind.module_type) continue;
        if (ty.name_id == @intCast(u32, 0)) continue;
    }
}
